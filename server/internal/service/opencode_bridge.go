package service

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/runtime"
)

type OpenCodeBridge struct {
	Manager *runtime.Manager
}

func (b OpenCodeBridge) client(ctx context.Context, workspace core.Workspace) (*runtimeClient, error) {
	client, err := b.Manager.Ensure(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return &runtimeClient{client: client}, nil
}

type runtimeClient struct {
	client interface {
		Health(context.Context) (bool, string, error)
		SessionStatuses(context.Context) (map[string]core.SessionActivity, error)
		ListSessions(context.Context) ([]core.Session, error)
		CreateSession(context.Context, string) (core.Session, error)
		UpdateSession(context.Context, string, string) (core.Session, error)
		DeleteSession(context.Context, string) (bool, error)
		SummarizeSession(context.Context, string, string, string, bool) error
		RevertSession(context.Context, string, string, string) (core.Session, error)
		UnrevertSession(context.Context, string) (core.Session, error)
		AbortSession(context.Context, string) error
		ListPermissions(context.Context) ([]core.PermissionRequest, error)
		ReplyPermission(context.Context, string, core.PermissionReply, string) error
		ListQuestions(context.Context) ([]core.QuestionRequest, error)
		ReplyQuestion(context.Context, string, []core.QuestionAnswer) error
		RejectQuestion(context.Context, string) error
		ListProviders(context.Context) (core.ProviderResponse, error)
		ListAgents(context.Context) ([]core.Agent, error)
		ListCommands(context.Context) ([]core.Command, error)
		RawMessages(context.Context, string) ([]json.RawMessage, error)
		ListMessages(context.Context, string) ([]core.Message, error)
		DashboardSessionSummaries(context.Context, []core.Session) ([]core.DashboardSessionSummary, error)
		SendPrompt(context.Context, string, core.PromptInput) error
		SendCommand(context.Context, string, core.CommandInput) error
		StreamEvents(context.Context) (<-chan core.ServerEvent, <-chan error, error)
	}
}

func (b OpenCodeBridge) SessionStatuses(ctx context.Context, workspace core.Workspace) (map[string]core.SessionActivity, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.SessionStatuses(ctx)
}
func (b OpenCodeBridge) ListSessions(ctx context.Context, workspace core.Workspace) ([]core.Session, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.ListSessions(ctx)
}
func (b OpenCodeBridge) CreateSession(ctx context.Context, workspace core.Workspace, title string) (core.Session, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return core.Session{}, err
	}
	return client.client.CreateSession(ctx, title)
}
func (b OpenCodeBridge) UpdateSession(ctx context.Context, workspace core.Workspace, sessionID, title string) (core.Session, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return core.Session{}, err
	}
	return client.client.UpdateSession(ctx, sessionID, title)
}
func (b OpenCodeBridge) DeleteSession(ctx context.Context, workspace core.Workspace, sessionID string) (bool, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return false, err
	}
	return client.client.DeleteSession(ctx, sessionID)
}
func (b OpenCodeBridge) SummarizeSession(ctx context.Context, workspace core.Workspace, sessionID, providerID, modelID string, auto bool) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.SummarizeSession(ctx, sessionID, providerID, modelID, auto)
}
func (b OpenCodeBridge) RevertSession(ctx context.Context, workspace core.Workspace, sessionID, messageID, partID string) (core.Session, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return core.Session{}, err
	}
	return client.client.RevertSession(ctx, sessionID, messageID, partID)
}
func (b OpenCodeBridge) UnrevertSession(ctx context.Context, workspace core.Workspace, sessionID string) (core.Session, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return core.Session{}, err
	}
	return client.client.UnrevertSession(ctx, sessionID)
}
func (b OpenCodeBridge) AbortSession(ctx context.Context, workspace core.Workspace, sessionID string) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.AbortSession(ctx, sessionID)
}
func (b OpenCodeBridge) ReplyToPermission(ctx context.Context, workspace core.Workspace, requestID string, reply core.PermissionReply, message string) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.ReplyPermission(ctx, requestID, reply, message)
}
func (b OpenCodeBridge) ReplyToQuestion(ctx context.Context, workspace core.Workspace, requestID string, answers []core.QuestionAnswer) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.ReplyQuestion(ctx, requestID, answers)
}
func (b OpenCodeBridge) RejectQuestion(ctx context.Context, workspace core.Workspace, requestID string) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.RejectQuestion(ctx, requestID)
}
func (b OpenCodeBridge) ListProviders(ctx context.Context, workspace core.Workspace) (core.ProviderResponse, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return core.ProviderResponse{}, err
	}
	response, err := client.client.ListProviders(ctx)
	if err != nil {
		return core.ProviderResponse{}, err
	}
	return enrichProviderResponse(response), nil
}
func (b OpenCodeBridge) ListAgents(ctx context.Context, workspace core.Workspace) ([]core.Agent, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.ListAgents(ctx)
}
func (b OpenCodeBridge) ListCommands(ctx context.Context, workspace core.Workspace) ([]core.Command, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.ListCommands(ctx)
}
func (b OpenCodeBridge) ListMessageEnvelopes(ctx context.Context, workspace core.Workspace, sessionID string) ([]json.RawMessage, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.RawMessages(ctx, sessionID)
}
func (b OpenCodeBridge) ListMessages(ctx context.Context, workspace core.Workspace, sessionID string) ([]core.Message, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.ListMessages(ctx, sessionID)
}
func (b OpenCodeBridge) DashboardSessionSummaries(ctx context.Context, workspace core.Workspace, sessionIDs []string) ([]core.DashboardSessionSummary, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	sessions, err := client.client.ListSessions(ctx)
	if err != nil {
		return nil, err
	}
	if len(sessionIDs) > 0 {
		allowed := map[string]struct{}{}
		for _, sessionID := range sessionIDs {
			allowed[sessionID] = struct{}{}
		}
		filtered := make([]core.Session, 0, len(sessionIDs))
		for _, session := range sessions {
			if _, ok := allowed[session.ID]; ok {
				filtered = append(filtered, session)
			}
		}
		sessions = filtered
	}
	return client.client.DashboardSessionSummaries(ctx, sessions)
}
func (b OpenCodeBridge) ListPermissions(ctx context.Context, workspace core.Workspace) ([]core.PermissionRequest, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.ListPermissions(ctx)
}
func (b OpenCodeBridge) ListQuestions(ctx context.Context, workspace core.Workspace) ([]core.QuestionRequest, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, err
	}
	return client.client.ListQuestions(ctx)
}
func (b OpenCodeBridge) SendPrompt(ctx context.Context, workspace core.Workspace, sessionID string, input core.PromptInput) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.SendPrompt(ctx, sessionID, input)
}
func (b OpenCodeBridge) SendCommand(ctx context.Context, workspace core.Workspace, sessionID string, input core.CommandInput) error {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return err
	}
	return client.client.SendCommand(ctx, sessionID, input)
}
func (b OpenCodeBridge) StreamEvents(ctx context.Context, workspace core.Workspace) (<-chan core.ServerEvent, <-chan error, error) {
	client, err := b.client(ctx, workspace)
	if err != nil {
		return nil, nil, err
	}
	return client.client.StreamEvents(ctx)
}

func (b OpenCodeBridge) RawEventStream(ctx context.Context, workspace core.Workspace) (*http.Response, error) {
	return b.Manager.RawEventStream(ctx, workspace)
}
