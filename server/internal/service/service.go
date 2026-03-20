package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/store"
)

var ErrUnauthorized = errors.New("unauthorized")

type Config struct {
	Info          core.ServerInfo
	Authenticator core.Authenticator
	Store         *store.MemoryStore
	Runtime       core.Runtime
	Bridge        core.RuntimeBridge
	Git           core.GitProvider
	Files         core.FileProvider
	Providers     core.ProviderResponse
	Agents        []core.Agent
	Commands      []core.Command
	Now           func() time.Time
}

type App struct {
	info          core.ServerInfo
	authenticator core.Authenticator
	store         *store.MemoryStore
	runtime       core.Runtime
	bridge        core.RuntimeBridge
	git           core.GitProvider
	files         core.FileProvider
	providers     core.ProviderResponse
	agents        []core.Agent
	commands      []core.Command
	now           func() time.Time
	ids           atomic.Uint64
}

func New(cfg Config) *App {
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	info := cfg.Info
	if info.Caps == (core.CapabilitySet{}) {
		info.Caps = core.DefaultCapabilities()
	}
	return &App{
		info:          info,
		authenticator: cfg.Authenticator,
		store:         cfg.Store,
		runtime:       cfg.Runtime,
		bridge:        cfg.Bridge,
		git:           cfg.Git,
		files:         cfg.Files,
		providers:     cfg.Providers,
		agents:        cfg.Agents,
		commands:      cfg.Commands,
		now:           now,
	}
}

func (a *App) Authorized(token string) bool {
	if a.authenticator == nil {
		return true
	}
	return a.authenticator.Authorize(token)
}

func (a *App) ServerInfo() core.ServerInfo {
	info := a.info
	info.Time = a.now().UTC()
	return info
}

func (a *App) Capabilities() core.CapabilitySet {
	return a.info.Caps
}

type CreateWorkspaceRequest struct {
	Name          string `json:"name"`
	RootURI       string `json:"rootUri,omitempty"`
	LocalPathHint string `json:"localPathHint,omitempty"`
	IsLocal       bool   `json:"isLocal"`
}

func (a *App) CreateWorkspace(_ context.Context, req CreateWorkspaceRequest) (core.Workspace, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return core.Workspace{}, errors.New("workspace name is required")
	}
	now := a.now().UTC()
	workspace := core.Workspace{
		ID:            a.nextID("ws"),
		Name:          name,
		RootURI:       strings.TrimSpace(req.RootURI),
		LocalPathHint: strings.TrimSpace(req.LocalPathHint),
		IsLocal:       req.IsLocal,
		Capabilities:  a.info.Caps,
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	a.store.PutWorkspace(workspace)
	return workspace, nil
}

func (a *App) ListWorkspaces(context.Context) []core.Workspace {
	return a.store.Workspaces()
}

func (a *App) Workspace(_ context.Context, workspaceID string) (core.Workspace, error) {
	return a.store.Workspace(workspaceID)
}

func (a *App) SessionStatuses(ctx context.Context, workspaceID string) (map[string]core.SessionActivity, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	if a.bridge != nil {
		return a.bridge.SessionStatuses(ctx, workspace)
	}
	sessions := a.store.SessionsByWorkspace(workspaceID)
	out := make(map[string]core.SessionActivity, len(sessions))
	for _, session := range sessions {
		statusType := string(session.Status)
		if statusType == string(core.SessionStatusRunning) {
			statusType = "busy"
		} else {
			statusType = "idle"
		}
		out[session.ID] = core.SessionActivity{Type: statusType}
	}
	return out, nil
}

func (a *App) CreateSession(ctx context.Context, workspaceID, title string) (core.Session, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return core.Session{}, err
	}
	if a.bridge != nil {
		session, err := a.bridge.CreateSession(ctx, workspace, title)
		if err != nil {
			return core.Session{}, err
		}
		a.store.PutSession(withWorkspace(session, workspace.ID))
		a.appendEvent(session.ID, "session.created", map[string]any{"title": session.Title, "workspaceId": workspaceID})
		return withWorkspace(session, workspace.ID), nil
	}
	now := a.now().UTC()
	title = strings.TrimSpace(title)
	if title == "" {
		title = "New session"
	}
	session := core.Session{
		ID:          a.nextID("sess"),
		WorkspaceID: workspace.ID,
		Title:       title,
		Status:      core.SessionStatusIdle,
		Messages:    []core.Message{},
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	a.store.PutSession(session)
	a.appendEvent(session.ID, "session.created", map[string]any{"title": title, "workspaceId": workspaceID})
	return session, nil
}

func (a *App) Sessions(_ context.Context, workspaceID string) ([]core.Session, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	if a.bridge != nil {
		sessions, err := a.bridge.ListSessions(context.Background(), workspace)
		if err != nil {
			return nil, err
		}
		for _, session := range sessions {
			a.store.PutSession(withWorkspace(session, workspaceID))
		}
		return annotateWorkspace(sessions, workspaceID), nil
	}
	return a.store.SessionsByWorkspace(workspaceID), nil
}

func (a *App) Session(_ context.Context, sessionID string) (core.Session, error) {
	session, err := a.store.Session(sessionID)
	if err == nil || a.bridge == nil {
		return session, err
	}
	workspace, ok := a.firstWorkspace()
	if !ok {
		return core.Session{}, err
	}
	sessions, bridgeErr := a.bridge.ListSessions(context.Background(), workspace)
	if bridgeErr != nil {
		return core.Session{}, err
	}
	for _, item := range sessions {
		if item.ID == sessionID {
			resolved := withWorkspace(item, workspace.ID)
			a.store.PutSession(resolved)
			return resolved, nil
		}
	}
	return core.Session{}, err
}

func (a *App) UpdateSession(ctx context.Context, sessionID, title string) (core.Session, error) {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return core.Session{}, err
	}
	if a.bridge != nil {
		updated, err := a.bridge.UpdateSession(ctx, workspace, sessionID, title)
		if err != nil {
			return core.Session{}, err
		}
		updated = withWorkspace(updated, session.WorkspaceID)
		updated.Messages = session.Messages
		a.store.PutSession(updated)
		return updated, nil
	}
	session.Title = strings.TrimSpace(title)
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	return session, nil
}

func (a *App) DeleteSession(ctx context.Context, sessionID string) (bool, error) {
	_, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return false, err
	}
	if a.bridge != nil {
		ok, err := a.bridge.DeleteSession(ctx, workspace, sessionID)
		if err == nil && ok {
			a.store.DeleteSession(sessionID)
		}
		return ok, err
	}
	a.store.DeleteSession(sessionID)
	return true, nil
}

func (a *App) SendInput(ctx context.Context, sessionID string, input core.Input) (core.Session, error) {
	session, err := a.store.Session(sessionID)
	if err != nil {
		return core.Session{}, err
	}
	workspace, err := a.store.Workspace(session.WorkspaceID)
	if err != nil {
		return core.Session{}, err
	}
	if strings.TrimSpace(input.Text) == "" {
		return core.Session{}, errors.New("input text is required")
	}
	userMessage := core.Message{
		ID:        a.nextID("msg"),
		Role:      core.MessageRoleUser,
		Text:      input.Text,
		Metadata:  copyStringMap(input.Metadata),
		CreatedAt: a.now().UTC(),
	}
	session.Messages = append(session.Messages, userMessage)
	session.Status = core.SessionStatusRunning
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	a.appendEvent(session.ID, "message.created", map[string]any{"role": userMessage.Role, "text": userMessage.Text})

	result, err := a.runtime.HandleInput(ctx, workspace, session, input)
	if err != nil {
		session.Status = core.SessionStatusFailed
		session.UpdatedAt = a.now().UTC()
		a.store.PutSession(session)
		a.appendEvent(session.ID, "session.failed", map[string]any{"error": err.Error()})
		return session, fmt.Errorf("runtime handle input: %w", err)
	}

	if result.Reply != nil {
		reply := *result.Reply
		if reply.ID == "" {
			reply.ID = a.nextID("msg")
		}
		if reply.CreatedAt.IsZero() {
			reply.CreatedAt = a.now().UTC()
		}
		session.Messages = append(session.Messages, reply)
		a.appendEvent(session.ID, "message.created", map[string]any{"role": reply.Role, "text": reply.Text})
	}

	for _, event := range result.Events {
		a.appendEvent(session.ID, event.Type, event.Payload)
	}

	if result.Status != "" {
		session.Status = result.Status
	} else {
		session.Status = core.SessionStatusIdle
	}
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	return session, nil
}

func (a *App) ListMessages(ctx context.Context, sessionID string) ([]core.Message, error) {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return nil, err
	}
	if a.bridge != nil {
		messages, err := a.bridge.ListMessages(ctx, workspace, sessionID)
		if err != nil {
			return nil, err
		}
		session.Messages = messages
		session.UpdatedAt = a.now().UTC()
		a.store.PutSession(session)
		return messages, nil
	}
	return session.Messages, nil
}

func (a *App) ListMessageEnvelopes(ctx context.Context, sessionID string) ([]json.RawMessage, error) {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return nil, err
	}
	if a.bridge == nil {
		envelopes := make([]json.RawMessage, 0, len(session.Messages))
		for _, message := range session.Messages {
			payload, err := json.Marshal(map[string]any{
				"info": map[string]any{
					"id":        message.ID,
					"sessionID": sessionID,
					"role":      string(message.Role),
					"summary":   message.Summary,
					"time": map[string]any{
						"created":   float64(message.CreatedAt.UnixMilli()),
						"updated":   float64(message.CreatedAt.UnixMilli()),
						"completed": float64(message.CreatedAt.UnixMilli()),
					},
				},
				"parts": []map[string]any{{
					"id":        message.ID + ":text",
					"sessionID": sessionID,
					"messageID": message.ID,
					"type":      "text",
					"text":      message.Text,
					"time": map[string]any{
						"created":   float64(message.CreatedAt.UnixMilli()),
						"updated":   float64(message.CreatedAt.UnixMilli()),
						"completed": float64(message.CreatedAt.UnixMilli()),
					},
				}},
			})
			if err != nil {
				return nil, err
			}
			envelopes = append(envelopes, payload)
		}
		return envelopes, nil
	}
	return a.bridge.ListMessageEnvelopes(ctx, workspace, sessionID)
}

func (a *App) SummarizeSession(ctx context.Context, sessionID, providerID, modelID string, auto bool) error {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return err
	}
	if a.bridge != nil {
		return a.bridge.SummarizeSession(ctx, workspace, sessionID, providerID, modelID, auto)
	}
	session.Summary = &core.SessionSummary{Files: len(session.Messages)}
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	return nil
}

func (a *App) RevertSession(ctx context.Context, sessionID, messageID, partID string) (core.Session, error) {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return core.Session{}, err
	}
	if a.bridge != nil {
		updated, err := a.bridge.RevertSession(ctx, workspace, sessionID, messageID, partID)
		if err != nil {
			return core.Session{}, err
		}
		updated = withWorkspace(updated, session.WorkspaceID)
		a.store.PutSession(updated)
		return updated, nil
	}
	session.Revert = &core.SessionRevert{MessageID: messageID, PartID: partID}
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	a.appendEvent(session.ID, "session.reverted", map[string]any{"messageId": messageID, "partId": partID})
	return session, nil
}

func (a *App) UnrevertSession(ctx context.Context, sessionID string) (core.Session, error) {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return core.Session{}, err
	}
	if a.bridge != nil {
		updated, err := a.bridge.UnrevertSession(ctx, workspace, sessionID)
		if err != nil {
			return core.Session{}, err
		}
		updated = withWorkspace(updated, session.WorkspaceID)
		a.store.PutSession(updated)
		return updated, nil
	}
	session.Revert = nil
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	a.appendEvent(session.ID, "session.unreverted", nil)
	return session, nil
}

func (a *App) AbortSession(ctx context.Context, sessionID string) error {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return err
	}
	if a.bridge != nil {
		return a.bridge.AbortSession(ctx, workspace, sessionID)
	}
	session.Status = core.SessionStatusIdle
	session.UpdatedAt = a.now().UTC()
	a.store.PutSession(session)
	a.appendEvent(session.ID, "session.aborted", nil)
	return nil
}

func (a *App) SessionEvents(_ context.Context, sessionID string, after uint64) ([]core.SessionEvent, error) {
	if _, err := a.store.Session(sessionID); err != nil {
		return nil, err
	}
	return a.store.EventsAfter(sessionID, after), nil
}

func (a *App) ServerEvents(_ context.Context, after uint64) []core.ServerEvent {
	return a.store.ServerEventsAfter(after)
}

func (a *App) PublishServerEvent(event core.ServerEvent) core.ServerEvent {
	if event.ID == "" {
		event.ID = a.nextID("svr_evt")
	}
	if event.CreatedAt.IsZero() {
		event.CreatedAt = a.now().UTC()
	}
	return a.store.AppendServerEvent(event)
}

func (a *App) RawRuntimeEventStream(ctx context.Context, workspaceID string) (*http.Response, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	if bridge, ok := a.bridge.(interface {
		RawEventStream(context.Context, core.Workspace) (*http.Response, error)
	}); ok {
		return bridge.RawEventStream(ctx, workspace)
	}
	return nil, errors.New("runtime event stream unavailable")
}

func (a *App) ListPermissions(ctx context.Context, workspaceID string) ([]core.PermissionRequest, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	if a.bridge == nil {
		return nil, nil
	}
	return a.bridge.ListPermissions(ctx, workspace)
}

func (a *App) ReplyToPermission(ctx context.Context, workspaceID, requestID string, reply core.PermissionReply, message string) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	if a.bridge == nil {
		return nil
	}
	err = a.bridge.ReplyToPermission(ctx, workspace, requestID, reply, message)
	if err == nil {
		a.PublishServerEvent(core.ServerEvent{WorkspaceID: workspaceID, Type: "permission.replied", Payload: map[string]any{"requestId": requestID, "reply": reply, "message": message}})
	}
	return err
}

func (a *App) ListQuestions(ctx context.Context, workspaceID string) ([]core.QuestionRequest, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	if a.bridge == nil {
		return nil, nil
	}
	return a.bridge.ListQuestions(ctx, workspace)
}

func (a *App) ReplyToQuestion(ctx context.Context, workspaceID, requestID string, answers []core.QuestionAnswer) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	if a.bridge == nil {
		return nil
	}
	err = a.bridge.ReplyToQuestion(ctx, workspace, requestID, answers)
	if err == nil {
		a.PublishServerEvent(core.ServerEvent{WorkspaceID: workspaceID, Type: "question.replied", Payload: map[string]any{"requestId": requestID}})
	}
	return err
}

func (a *App) RejectQuestion(ctx context.Context, workspaceID, requestID string) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	if a.bridge == nil {
		return nil
	}
	err = a.bridge.RejectQuestion(ctx, workspace, requestID)
	if err == nil {
		a.PublishServerEvent(core.ServerEvent{WorkspaceID: workspaceID, Type: "question.rejected", Payload: map[string]any{"requestId": requestID}})
	}
	return err
}

func (a *App) ListProviders(ctx context.Context, workspaceID string) (core.ProviderResponse, error) {
	if a.bridge != nil {
		workspace, err := a.store.Workspace(workspaceID)
		if err != nil {
			return core.ProviderResponse{}, err
		}
		return a.bridge.ListProviders(ctx, workspace)
	}
	return a.providers, nil
}

func (a *App) ListAgents(ctx context.Context, workspaceID string) ([]core.Agent, error) {
	if a.bridge != nil {
		workspace, err := a.store.Workspace(workspaceID)
		if err != nil {
			return nil, err
		}
		return a.bridge.ListAgents(ctx, workspace)
	}
	return append([]core.Agent(nil), a.agents...), nil
}

func (a *App) ListCommands(ctx context.Context, workspaceID string) ([]core.Command, error) {
	if a.bridge != nil {
		workspace, err := a.store.Workspace(workspaceID)
		if err != nil {
			return nil, err
		}
		return a.bridge.ListCommands(ctx, workspace)
	}
	return append([]core.Command(nil), a.commands...), nil
}

func (a *App) SendPrompt(ctx context.Context, sessionID string, input core.PromptInput) error {
	session, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return err
	}
	if a.bridge != nil {
		return a.bridge.SendPrompt(ctx, workspace, sessionID, input)
	}
	_, err = a.SendInput(ctx, sessionID, core.Input{Text: input.Text})
	if err == nil {
		a.appendEvent(session.ID, "prompt.accepted", map[string]any{"agent": input.Agent})
	}
	return err
}

func (a *App) SendCommand(ctx context.Context, sessionID string, input core.CommandInput) error {
	_, workspace, err := a.sessionWorkspace(sessionID)
	if err != nil {
		return err
	}
	if a.bridge != nil {
		return a.bridge.SendCommand(ctx, workspace, sessionID, input)
	}
	_, err = a.SendInput(ctx, sessionID, core.Input{Text: strings.TrimSpace(input.Command + " " + input.Arguments)})
	return err
}

func (a *App) GitStatus(ctx context.Context, workspaceID string) (core.GitStatus, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return core.GitStatus{}, err
	}
	return a.git.Status(ctx, workspace)
}

func (a *App) GitDiff(ctx context.Context, workspaceID string) (core.GitDiff, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return core.GitDiff{}, err
	}
	return a.git.Diff(ctx, workspace)
}

func (a *App) GitPreview(ctx context.Context, workspaceID string) (core.GitCommitPreview, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return core.GitCommitPreview{}, err
	}
	return a.git.Preview(ctx, workspace)
}

func (a *App) GitCommit(ctx context.Context, workspaceID, message string, includeUnstaged bool) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	return a.git.Commit(ctx, workspace, message, includeUnstaged)
}

func (a *App) GitPush(ctx context.Context, workspaceID string) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	return a.git.Push(ctx, workspace)
}

func (a *App) GitBranches(ctx context.Context, workspaceID string) ([]string, string, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, "", err
	}
	branches, err := a.git.Branches(ctx, workspace)
	if err != nil {
		return nil, "", err
	}
	current, err := a.git.CurrentBranch(ctx, workspace)
	if err != nil {
		return nil, "", err
	}
	return branches, current, nil
}

func (a *App) GitInitialize(ctx context.Context, workspaceID string) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	return a.git.Initialize(ctx, workspace)
}

func (a *App) GitSwitchBranch(ctx context.Context, workspaceID, branch string) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	return a.git.SwitchBranch(ctx, workspace, branch)
}

func (a *App) GitCreateBranch(ctx context.Context, workspaceID, branch string) error {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return err
	}
	return a.git.CreateBranch(ctx, workspace, branch)
}

func (a *App) FileSearch(ctx context.Context, workspaceID, query string, limit int) ([]core.FileMatch, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	return a.files.Search(ctx, workspace, query, limit)
}

func (a *App) FileContent(ctx context.Context, workspaceID, path string) (core.FileContent, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return core.FileContent{}, err
	}
	return a.files.Read(ctx, workspace, path)
}

func (a *App) ResolveFileReferences(ctx context.Context, workspaceID, text string) ([]core.ResolvedFileReference, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	return a.files.ResolveReferences(ctx, workspace, text)
}

func (a *App) CreateAttachment(_ context.Context, filename, mimeType string, content []byte) (core.Attachment, error) {
	filename = strings.TrimSpace(filename)
	if filename == "" {
		return core.Attachment{}, errors.New("filename is required")
	}
	record := core.AttachmentRecord{
		Attachment: core.Attachment{
			ID:        a.nextID("att"),
			Filename:  filename,
			MimeType:  strings.TrimSpace(mimeType),
			SizeBytes: int64(len(content)),
			CreatedAt: a.now().UTC(),
		},
		Content: append([]byte(nil), content...),
	}
	a.store.PutAttachment(record)
	return record.Attachment, nil
}

func (a *App) Attachment(_ context.Context, attachmentID string) (core.AttachmentRecord, error) {
	return a.store.Attachment(attachmentID)
}

func (a *App) Dashboard(_ context.Context, workspaceID string) (core.DashboardSummary, error) {
	if _, err := a.store.Workspace(workspaceID); err != nil {
		return core.DashboardSummary{}, err
	}
	sessions := a.store.SessionsByWorkspace(workspaceID)
	summary := core.DashboardSummary{WorkspaceID: workspaceID, SessionCount: len(sessions)}
	for _, session := range sessions {
		for _, message := range session.Messages {
			summary.MessageCount++
			switch message.Role {
			case core.MessageRoleUser:
				summary.UserMessageCount++
			case core.MessageRoleAssistant:
				summary.AssistantMsgCount++
			}
			if message.CreatedAt.After(summary.LastActivityAt) {
				summary.LastActivityAt = message.CreatedAt
			}
		}
		if session.UpdatedAt.After(summary.LastActivityAt) {
			summary.LastActivityAt = session.UpdatedAt
		}
	}
	return summary, nil
}

func (a *App) DashboardSessionSummaries(ctx context.Context, workspaceID string, sessionIDs []string) ([]core.DashboardSessionSummary, error) {
	workspace, err := a.store.Workspace(workspaceID)
	if err != nil {
		return nil, err
	}
	if a.bridge != nil {
		return a.bridge.DashboardSessionSummaries(ctx, workspace, sessionIDs)
	}
	return nil, nil
}

func (a *App) appendEvent(sessionID, eventType string, payload map[string]any) {
	a.store.AppendEvent(core.SessionEvent{
		ID:        a.nextID("evt"),
		SessionID: sessionID,
		Type:      eventType,
		Payload:   copyAnyMap(payload),
		CreatedAt: a.now().UTC(),
	})
}

func (a *App) nextID(prefix string) string {
	value := a.ids.Add(1)
	return fmt.Sprintf("%s_%d", prefix, value)
}

func copyStringMap(in map[string]string) map[string]string {
	if len(in) == 0 {
		return nil
	}
	out := make(map[string]string, len(in))
	for key, value := range in {
		out[key] = value
	}
	return out
}

func copyAnyMap(in map[string]any) map[string]any {
	if len(in) == 0 {
		return nil
	}
	out := make(map[string]any, len(in))
	for key, value := range in {
		out[key] = value
	}
	return out
}

func annotateWorkspace(in []core.Session, workspaceID string) []core.Session {
	out := make([]core.Session, 0, len(in))
	for _, session := range in {
		out = append(out, withWorkspace(session, workspaceID))
	}
	return out
}

func withWorkspace(session core.Session, workspaceID string) core.Session {
	session.WorkspaceID = workspaceID
	return session
}

func (a *App) sessionWorkspace(sessionID string) (core.Session, core.Workspace, error) {
	session, err := a.store.Session(sessionID)
	if err != nil {
		if workspace, ok := a.firstWorkspace(); ok {
			return core.Session{ID: sessionID, WorkspaceID: workspace.ID}, workspace, nil
		}
		return core.Session{}, core.Workspace{}, err
	}
	workspace, err := a.store.Workspace(session.WorkspaceID)
	if err != nil {
		return core.Session{}, core.Workspace{}, err
	}
	return session, workspace, nil
}

func (a *App) firstWorkspace() (core.Workspace, bool) {
	workspaces := a.store.Workspaces()
	if len(workspaces) == 0 {
		return core.Workspace{}, false
	}
	return workspaces[0], true
}
