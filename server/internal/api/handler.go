package api

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/service"
	"github.com/watzon/neocode/server/internal/store"
)

type Handler struct {
	app     *service.App
	mux     *http.ServeMux
	handler http.Handler
}

func NewHandler(app *service.App) *Handler {
	h := &Handler{app: app, mux: http.NewServeMux()}
	h.routes()
	h.handler = h.withRequestLogging(h.mux)
	return h
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.handler.ServeHTTP(w, r)
}

type loggingResponseWriter struct {
	http.ResponseWriter
	statusCode int
	body       bytes.Buffer
	bytesSent  int
}

func (w *loggingResponseWriter) WriteHeader(statusCode int) {
	w.statusCode = statusCode
	w.ResponseWriter.WriteHeader(statusCode)
}

func (w *loggingResponseWriter) Write(data []byte) (int, error) {
	if w.statusCode == 0 {
		w.statusCode = http.StatusOK
	}
	if w.body.Len() < 2048 {
		remaining := 2048 - w.body.Len()
		if remaining > len(data) {
			remaining = len(data)
		}
		_, _ = w.body.Write(data[:remaining])
	}
	n, err := w.ResponseWriter.Write(data)
	w.bytesSent += n
	return n, err
}

func (h *Handler) withRequestLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		startedAt := time.Now()
		writer := &loggingResponseWriter{ResponseWriter: w}
		next.ServeHTTP(writer, r)

		statusCode := writer.statusCode
		if statusCode == 0 {
			statusCode = http.StatusOK
		}
		duration := time.Since(startedAt)
		if !shouldLogRequest(r, statusCode, duration) {
			return
		}

		fields := []string{
			fmt.Sprintf("method=%s", r.Method),
			fmt.Sprintf("path=%s", r.URL.Path),
			fmt.Sprintf("status=%d", statusCode),
			fmt.Sprintf("duration=%s", duration.Round(time.Millisecond)),
			fmt.Sprintf("bytes=%d", writer.bytesSent),
		}
		if workspaceID := requestWorkspaceID(r); workspaceID != "" {
			fields = append(fields, fmt.Sprintf("workspace=%s", workspaceID))
		}
		if remoteAddr := strings.TrimSpace(r.RemoteAddr); remoteAddr != "" {
			fields = append(fields, fmt.Sprintf("remote=%s", remoteAddr))
		}
		if statusCode >= http.StatusBadRequest {
			message := compactLogMessage(writer.body.String())
			if message != "" {
				fields = append(fields, fmt.Sprintf("error=%q", message))
			}
		}
		log.Printf("request %s", strings.Join(fields, " "))
	})
}

func shouldLogRequest(r *http.Request, statusCode int, duration time.Duration) bool {
	if statusCode >= http.StatusBadRequest {
		return true
	}
	if duration >= 2*time.Second {
		return true
	}
	if strings.Contains(r.URL.Path, "/git/") {
		return true
	}
	return r.Method != http.MethodGet && r.Method != http.MethodHead
}

func requestWorkspaceID(r *http.Request) string {
	if !strings.HasPrefix(r.URL.Path, "/v1/workspaces/") {
		return strings.TrimSpace(r.Header.Get("X-NeoCode-Workspace-ID"))
	}
	path := strings.TrimPrefix(r.URL.Path, "/v1/workspaces/")
	parts := splitPath(path)
	if len(parts) == 0 {
		return strings.TrimSpace(r.Header.Get("X-NeoCode-Workspace-ID"))
	}
	return parts[0]
}

func compactLogMessage(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	trimmed = strings.ReplaceAll(trimmed, "\n", " ")
	trimmed = strings.Join(strings.Fields(trimmed), " ")
	if len(trimmed) > 300 {
		return trimmed[:300] + "..."
	}
	return trimmed
}

func (h *Handler) routes() {
	h.mux.HandleFunc("/v1/server", h.withAuth(h.handleServerInfo))
	h.mux.HandleFunc("/v1/capabilities", h.withAuth(h.handleCapabilities))
	h.mux.HandleFunc("/v1/events", h.withAuth(h.handleServerEvents))
	h.mux.HandleFunc("/v1/workspaces", h.withAuth(h.handleWorkspaces))
	h.mux.HandleFunc("/v1/workspaces/", h.withAuth(h.handleWorkspaceRoutes))
	h.mux.HandleFunc("/v1/sessions/", h.withAuth(h.handleSessionRoutes))
	h.mux.HandleFunc("/v1/permissions/", h.withAuth(h.handlePermissionRoutes))
	h.mux.HandleFunc("/v1/questions/", h.withAuth(h.handleQuestionRoutes))
	h.mux.HandleFunc("/v1/attachments", h.withAuth(h.handleAttachments))
	h.mux.HandleFunc("/v1/attachments/", h.withAuth(h.handleAttachmentByID))
}

func (h *Handler) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !h.app.Authorized(r.Header.Get("Authorization")) {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next(w, r)
	}
}

func (h *Handler) handleServerInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeMethodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, h.app.ServerInfo())
}

func (h *Handler) handleCapabilities(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeMethodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, h.app.Capabilities())
}

func (h *Handler) handleServerEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeMethodNotAllowed(w)
		return
	}
	after, _ := strconv.ParseUint(r.URL.Query().Get("after"), 10, 64)
	events := h.app.ServerEvents(r.Context(), after)
	if strings.Contains(r.Header.Get("Accept"), "text/event-stream") {
		writeServerSSE(w, events)
		return
	}
	writeJSON(w, http.StatusOK, events)
}

func (h *Handler) handleWorkspaces(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, h.app.ListWorkspaces(r.Context()))
	case http.MethodPost:
		var req service.CreateWorkspaceRequest
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		workspace, err := h.app.CreateWorkspace(r.Context(), req)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusCreated, workspace)
	default:
		writeMethodNotAllowed(w)
	}
}

func (h *Handler) handleWorkspaceRoutes(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/workspaces/")
	parts := splitPath(path)
	if len(parts) == 0 {
		writeNotFound(w)
		return
	}
	workspaceID := parts[0]
	if len(parts) == 1 {
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		workspace, err := h.app.Workspace(r.Context(), workspaceID)
		writeResult(w, workspace, err)
		return
	}

	switch parts[1] {
	case "sessions":
		h.handleWorkspaceSessions(w, r, workspaceID)
	case "session-status":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		statuses, err := h.app.SessionStatuses(r.Context(), workspaceID)
		writeResult(w, statuses, err)
	case "providers":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		providers, err := h.app.ListProviders(r.Context(), workspaceID)
		writeResult(w, providers, err)
	case "agents":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		agents, err := h.app.ListAgents(r.Context(), workspaceID)
		writeResult(w, agents, err)
	case "commands":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		commands, err := h.app.ListCommands(r.Context(), workspaceID)
		writeResult(w, commands, err)
	case "events":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		h.handleWorkspaceEventStream(w, r, workspaceID)
	case "permissions":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		permissions, err := h.app.ListPermissions(r.Context(), workspaceID)
		writeResult(w, permissions, err)
	case "questions":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		questions, err := h.app.ListQuestions(r.Context(), workspaceID)
		writeResult(w, questions, err)
	case "git":
		h.handleWorkspaceGit(w, r, workspaceID, parts[2:])
	case "files":
		h.handleWorkspaceFiles(w, r, workspaceID, parts[2:])
	case "dashboard":
		if len(parts) > 2 && parts[2] == "sessions" {
			if r.Method != http.MethodPost {
				writeMethodNotAllowed(w)
				return
			}
			var req struct {
				SessionIDs []string `json:"sessionIDs"`
			}
			if err := decodeJSON(r, &req); err != nil {
				writeError(w, http.StatusBadRequest, err.Error())
				return
			}
			summaries, err := h.app.DashboardSessionSummaries(r.Context(), workspaceID, req.SessionIDs)
			writeResult(w, summaries, err)
			return
		}
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		summary, err := h.app.Dashboard(r.Context(), workspaceID)
		writeResult(w, summary, err)
	default:
		writeNotFound(w)
	}
}

func (h *Handler) handleWorkspaceSessions(w http.ResponseWriter, r *http.Request, workspaceID string) {
	switch r.Method {
	case http.MethodGet:
		sessions, err := h.app.Sessions(r.Context(), workspaceID)
		writeResult(w, sessions, err)
	case http.MethodPost:
		var req struct {
			Title string `json:"title"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		session, err := h.app.CreateSession(r.Context(), workspaceID, req.Title)
		if err != nil {
			writeStoreError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, session)
	default:
		writeMethodNotAllowed(w)
	}
}

func (h *Handler) handleWorkspaceGit(w http.ResponseWriter, r *http.Request, workspaceID string, parts []string) {
	if len(parts) == 0 {
		writeNotFound(w)
		return
	}
	switch parts[0] {
	case "status":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		status, err := h.app.GitStatus(r.Context(), workspaceID)
		writeResult(w, status, err)
	case "diff":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		diff, err := h.app.GitDiff(r.Context(), workspaceID)
		writeResult(w, diff, err)
	case "preview":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		preview, err := h.app.GitPreview(r.Context(), workspaceID)
		writeResult(w, preview, err)
	case "commit":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			Message         string `json:"message"`
			IncludeUnstaged bool   `json:"includeUnstaged"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.GitCommit(r.Context(), workspaceID, req.Message, req.IncludeUnstaged))
	case "push":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.GitPush(r.Context(), workspaceID))
	case "branches":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		branches, current, err := h.app.GitBranches(r.Context(), workspaceID)
		writeResult(w, map[string]any{"branches": branches, "current": current}, err)
	case "initialize":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.GitInitialize(r.Context(), workspaceID))
	case "switch":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			Branch string `json:"branch"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.GitSwitchBranch(r.Context(), workspaceID, req.Branch))
	case "create-branch":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			Branch string `json:"branch"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.GitCreateBranch(r.Context(), workspaceID, req.Branch))
	default:
		writeNotFound(w)
	}
}

func (h *Handler) handleWorkspaceFiles(w http.ResponseWriter, r *http.Request, workspaceID string, parts []string) {
	if len(parts) == 0 {
		writeNotFound(w)
		return
	}
	switch parts[0] {
	case "search":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			Query string `json:"query"`
			Limit int    `json:"limit"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		matches, err := h.app.FileSearch(r.Context(), workspaceID, req.Query, req.Limit)
		writeResult(w, matches, err)
	case "content":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		content, err := h.app.FileContent(r.Context(), workspaceID, r.URL.Query().Get("path"))
		writeResult(w, content, err)
	case "resolve-references":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			Text string `json:"text"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		refs, err := h.app.ResolveFileReferences(r.Context(), workspaceID, req.Text)
		writeResult(w, refs, err)
	default:
		writeNotFound(w)
	}
}

func (h *Handler) handleSessionRoutes(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/sessions/")
	parts := splitPath(path)
	if len(parts) == 0 {
		writeNotFound(w)
		return
	}
	sessionID := parts[0]
	if len(parts) == 1 {
		switch r.Method {
		case http.MethodGet:
			session, err := h.app.Session(r.Context(), sessionID)
			writeResult(w, session, err)
		case http.MethodPatch:
			var req struct {
				Title string `json:"title"`
			}
			if err := decodeJSON(r, &req); err != nil {
				writeError(w, http.StatusBadRequest, err.Error())
				return
			}
			session, err := h.app.UpdateSession(r.Context(), sessionID, req.Title)
			writeResult(w, session, err)
		case http.MethodDelete:
			ok, err := h.app.DeleteSession(r.Context(), sessionID)
			writeResult(w, map[string]bool{"ok": ok}, err)
		default:
			writeMethodNotAllowed(w)
		}
		return
	}

	switch parts[1] {
	case "messages":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		envelopes, err := h.app.ListMessageEnvelopes(r.Context(), sessionID)
		writeResult(w, envelopes, err)
	case "summarize":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			ProviderID string `json:"providerID"`
			ModelID    string `json:"modelID"`
			Auto       bool   `json:"auto"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.SummarizeSession(r.Context(), sessionID, req.ProviderID, req.ModelID, req.Auto))
	case "revert":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var req struct {
			MessageID string `json:"messageID"`
			PartID    string `json:"partID"`
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		session, err := h.app.RevertSession(r.Context(), sessionID, req.MessageID, req.PartID)
		writeResult(w, session, err)
	case "unrevert":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		session, err := h.app.UnrevertSession(r.Context(), sessionID)
		writeResult(w, session, err)
	case "abort":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.AbortSession(r.Context(), sessionID))
	case "input":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var input core.Input
		if err := decodeJSON(r, &input); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		session, err := h.app.SendInput(r.Context(), sessionID, input)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, session)
	case "events":
		if r.Method != http.MethodGet {
			writeMethodNotAllowed(w)
			return
		}
		after, _ := strconv.ParseUint(r.URL.Query().Get("after"), 10, 64)
		events, err := h.app.SessionEvents(r.Context(), sessionID, after)
		if err != nil {
			writeStoreError(w, err)
			return
		}
		if strings.Contains(r.Header.Get("Accept"), "text/event-stream") {
			writeSSE(w, events)
			return
		}
		writeJSON(w, http.StatusOK, events)
	case "prompt":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var input core.PromptInput
		if err := decodeJSON(r, &input); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.SendPrompt(r.Context(), sessionID, input))
	case "command":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		var input core.CommandInput
		if err := decodeJSON(r, &input); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.SendCommand(r.Context(), sessionID, input))
	default:
		writeNotFound(w)
	}
}

func (h *Handler) handlePermissionRoutes(w http.ResponseWriter, r *http.Request) {
	parts := splitPath(strings.TrimPrefix(r.URL.Path, "/v1/permissions/"))
	if len(parts) != 2 || parts[1] != "reply" || r.Method != http.MethodPost {
		writeMethodNotAllowed(w)
		return
	}
	var req struct {
		WorkspaceID string               `json:"workspaceId"`
		Reply       core.PermissionReply `json:"reply"`
		Message     string               `json:"message"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeResult(w, map[string]bool{"ok": true}, h.app.ReplyToPermission(r.Context(), req.WorkspaceID, parts[0], req.Reply, req.Message))
}

func (h *Handler) handleQuestionRoutes(w http.ResponseWriter, r *http.Request) {
	parts := splitPath(strings.TrimPrefix(r.URL.Path, "/v1/questions/"))
	if len(parts) != 2 {
		writeNotFound(w)
		return
	}
	requestID := parts[0]
	var req struct {
		WorkspaceID string                `json:"workspaceId"`
		Answers     []core.QuestionAnswer `json:"answers"`
	}
	switch parts[1] {
	case "reply":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.ReplyToQuestion(r.Context(), req.WorkspaceID, requestID, req.Answers))
	case "reject":
		if r.Method != http.MethodPost {
			writeMethodNotAllowed(w)
			return
		}
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeResult(w, map[string]bool{"ok": true}, h.app.RejectQuestion(r.Context(), req.WorkspaceID, requestID))
	default:
		writeNotFound(w)
	}
}

func (h *Handler) handleAttachments(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeMethodNotAllowed(w)
		return
	}
	var req struct {
		Filename string `json:"filename"`
		MimeType string `json:"mimeType"`
		Content  string `json:"contentBase64"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	content, err := base64.StdEncoding.DecodeString(req.Content)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid base64 content")
		return
	}
	attachment, err := h.app.CreateAttachment(r.Context(), req.Filename, req.MimeType, content)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, attachment)
}

func (h *Handler) handleAttachmentByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeMethodNotAllowed(w)
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/v1/attachments/")
	record, err := h.app.Attachment(r.Context(), id)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, struct {
		core.Attachment
		ContentBase64 string `json:"contentBase64"`
	}{Attachment: record.Attachment, ContentBase64: base64.StdEncoding.EncodeToString(record.Content)})
}

func decodeJSON(r *http.Request, dst any) error {
	defer r.Body.Close()
	data, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		return err
	}
	if len(data) == 0 {
		data = []byte("{}")
	}
	return json.Unmarshal(data, dst)
}

func splitPath(path string) []string {
	cleaned := strings.Trim(path, "/")
	if cleaned == "" {
		return nil
	}
	return strings.Split(cleaned, "/")
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeSSE(w http.ResponseWriter, events []core.SessionEvent) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	for _, event := range events {
		payload, _ := json.Marshal(event)
		_, _ = fmt.Fprintf(w, "id: %d\nevent: %s\ndata: %s\n\n", event.Cursor, event.Type, payload)
	}
}

func writeServerSSE(w http.ResponseWriter, events []core.ServerEvent) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	for _, event := range events {
		payload, _ := json.Marshal(event)
		_, _ = fmt.Fprintf(w, "id: %d\nevent: %s\ndata: %s\n\n", event.Cursor, event.Type, payload)
	}
}

func writeMethodNotAllowed(w http.ResponseWriter) {
	writeError(w, http.StatusMethodNotAllowed, "method not allowed")
}

func writeNotFound(w http.ResponseWriter) {
	writeError(w, http.StatusNotFound, "not found")
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func writeStoreError(w http.ResponseWriter, err error) {
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	writeError(w, http.StatusBadRequest, err.Error())
}

func writeResult(w http.ResponseWriter, value any, err error) {
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, value)
}
