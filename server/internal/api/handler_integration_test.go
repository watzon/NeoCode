package api

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/watzon/neocode/server/internal/auth"
	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/service"
	"github.com/watzon/neocode/server/internal/store"
)

type testRuntime struct{}

func (testRuntime) HandleInput(context.Context, core.Workspace, core.Session, core.Input) (core.RuntimeResult, error) {
	return core.RuntimeResult{
		Status: core.SessionStatusIdle,
		Reply:  &core.Message{Role: core.MessageRoleAssistant, Text: "ack"},
		Events: []core.RuntimeEvent{{Type: "runtime.completed", Payload: map[string]any{"ok": true}}},
	}, nil
}

type testGit struct{}

func (testGit) Status(context.Context, core.Workspace) (core.GitStatus, error) {
	return core.GitStatus{Branch: "main", HasChanges: true}, nil
}

func (testGit) Diff(context.Context, core.Workspace) (core.GitDiff, error) {
	return core.GitDiff{Patch: "diff --git", FileCount: 1}, nil
}
func (testGit) Preview(context.Context, core.Workspace) (core.GitCommitPreview, error) {
	return core.GitCommitPreview{Branch: "main"}, nil
}
func (testGit) Commit(context.Context, core.Workspace, string, bool) error { return nil }
func (testGit) Push(context.Context, core.Workspace) error                 { return nil }
func (testGit) Branches(context.Context, core.Workspace) ([]string, error) {
	return []string{"main"}, nil
}
func (testGit) CurrentBranch(context.Context, core.Workspace) (string, error) { return "main", nil }
func (testGit) Initialize(context.Context, core.Workspace) error              { return nil }
func (testGit) SwitchBranch(context.Context, core.Workspace, string) error    { return nil }
func (testGit) CreateBranch(context.Context, core.Workspace, string) error    { return nil }

type testFiles struct{}

func (testFiles) Search(context.Context, core.Workspace, string, int) ([]core.FileMatch, error) {
	return []core.FileMatch{{Path: "README.md", Name: "README.md"}}, nil
}

func (testFiles) Read(context.Context, core.Workspace, string) (core.FileContent, error) {
	return core.FileContent{Path: "README.md", Content: "hello", Encoding: "utf-8"}, nil
}

func (testFiles) ResolveReferences(context.Context, core.Workspace, string) ([]core.ResolvedFileReference, error) {
	return []core.ResolvedFileReference{{Path: "README.md", Source: "@README.md", Start: 0, End: 10}}, nil
}

func newTestHandler() *Handler {
	return NewHandler(service.New(service.Config{
		Info:          core.ServerInfo{Name: "NeoCode", Version: "test", Mode: core.ServerModeEmbedded},
		Authenticator: auth.StaticToken("secret"),
		Store:         store.NewMemoryStore(),
		Runtime:       testRuntime{},
		Git:           testGit{},
		Files:         testFiles{},
		Now:           func() time.Time { return time.Unix(1700000000, 0).UTC() },
	}))
}

func doJSONRequest(t *testing.T, handler http.Handler, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var payload []byte
	if body != nil {
		var err error
		payload, err = json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(payload))
	req.Header.Set("Authorization", "Bearer secret")
	req.Header.Set("Content-Type", "application/json")
	resp := httptest.NewRecorder()
	handler.ServeHTTP(resp, req)
	return resp
}

func TestHandlerAuthRequired(t *testing.T) {
	handler := newTestHandler()
	req := httptest.NewRequest(http.MethodGet, "/v1/server", nil)
	resp := httptest.NewRecorder()
	handler.ServeHTTP(resp, req)
	if resp.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", resp.Code)
	}
}

func TestHandlerFullFlow(t *testing.T) {
	handler := newTestHandler()

	workspaceResp := doJSONRequest(t, handler, http.MethodPost, "/v1/workspaces", map[string]any{
		"name":    "Repo",
		"rootUri": "file:///repo",
		"isLocal": true,
	})
	if workspaceResp.Code != http.StatusCreated {
		t.Fatalf("workspace create failed: %d %s", workspaceResp.Code, workspaceResp.Body.String())
	}
	var workspace core.Workspace
	_ = json.Unmarshal(workspaceResp.Body.Bytes(), &workspace)

	sessionResp := doJSONRequest(t, handler, http.MethodPost, "/v1/workspaces/"+workspace.ID+"/sessions", map[string]any{"title": "Chat"})
	if sessionResp.Code != http.StatusCreated {
		t.Fatalf("session create failed: %d %s", sessionResp.Code, sessionResp.Body.String())
	}
	var session core.Session
	_ = json.Unmarshal(sessionResp.Body.Bytes(), &session)

	inputResp := doJSONRequest(t, handler, http.MethodPost, "/v1/sessions/"+session.ID+"/input", map[string]any{"text": "hello"})
	if inputResp.Code != http.StatusOK {
		t.Fatalf("input failed: %d %s", inputResp.Code, inputResp.Body.String())
	}
	_ = json.Unmarshal(inputResp.Body.Bytes(), &session)
	if len(session.Messages) != 2 {
		t.Fatalf("expected 2 messages, got %d", len(session.Messages))
	}

	eventsReq := httptest.NewRequest(http.MethodGet, "/v1/sessions/"+session.ID+"/events?after=0", nil)
	eventsReq.Header.Set("Authorization", "Bearer secret")
	eventsReq.Header.Set("Accept", "text/event-stream")
	eventsResp := httptest.NewRecorder()
	handler.ServeHTTP(eventsResp, eventsReq)
	if eventsResp.Code != http.StatusOK || !strings.Contains(eventsResp.Body.String(), "event: message.created") {
		t.Fatalf("unexpected events response: %d %s", eventsResp.Code, eventsResp.Body.String())
	}

	gitResp := doJSONRequest(t, handler, http.MethodGet, "/v1/workspaces/"+workspace.ID+"/git/status", nil)
	if gitResp.Code != http.StatusOK || !strings.Contains(gitResp.Body.String(), "main") {
		t.Fatalf("unexpected git status: %d %s", gitResp.Code, gitResp.Body.String())
	}

	branchesResp := doJSONRequest(t, handler, http.MethodGet, "/v1/workspaces/"+workspace.ID+"/git/branches", nil)
	if branchesResp.Code != http.StatusOK || !strings.Contains(branchesResp.Body.String(), "branches") {
		t.Fatalf("unexpected git branches: %d %s", branchesResp.Code, branchesResp.Body.String())
	}

	providersResp := doJSONRequest(t, handler, http.MethodGet, "/v1/workspaces/"+workspace.ID+"/providers", nil)
	if providersResp.Code != http.StatusOK {
		t.Fatalf("unexpected providers response: %d %s", providersResp.Code, providersResp.Body.String())
	}

	commandsResp := doJSONRequest(t, handler, http.MethodGet, "/v1/workspaces/"+workspace.ID+"/commands", nil)
	if commandsResp.Code != http.StatusOK {
		t.Fatalf("unexpected commands response: %d %s", commandsResp.Code, commandsResp.Body.String())
	}

	searchResp := doJSONRequest(t, handler, http.MethodPost, "/v1/workspaces/"+workspace.ID+"/files/search", map[string]any{"query": "read"})
	if searchResp.Code != http.StatusOK || !strings.Contains(searchResp.Body.String(), "README.md") {
		t.Fatalf("unexpected file search: %d %s", searchResp.Code, searchResp.Body.String())
	}

	contentReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspace.ID+"/files/content?path=README.md", nil)
	contentReq.Header.Set("Authorization", "Bearer secret")
	contentResp := httptest.NewRecorder()
	handler.ServeHTTP(contentResp, contentReq)
	if contentResp.Code != http.StatusOK || !strings.Contains(contentResp.Body.String(), "hello") {
		t.Fatalf("unexpected file content: %d %s", contentResp.Code, contentResp.Body.String())
	}

	refsResp := doJSONRequest(t, handler, http.MethodPost, "/v1/workspaces/"+workspace.ID+"/files/resolve-references", map[string]any{"text": "@README.md"})
	if refsResp.Code != http.StatusOK || !strings.Contains(refsResp.Body.String(), "@README.md") {
		t.Fatalf("unexpected refs response: %d %s", refsResp.Code, refsResp.Body.String())
	}

	promptResp := doJSONRequest(t, handler, http.MethodPost, "/v1/sessions/"+session.ID+"/prompt", map[string]any{"text": "follow up"})
	if promptResp.Code != http.StatusOK {
		t.Fatalf("unexpected prompt response: %d %s", promptResp.Code, promptResp.Body.String())
	}

	messagesResp := doJSONRequest(t, handler, http.MethodGet, "/v1/sessions/"+session.ID+"/messages", nil)
	if messagesResp.Code != http.StatusOK {
		t.Fatalf("unexpected messages response: %d %s", messagesResp.Code, messagesResp.Body.String())
	}

	attachmentResp := doJSONRequest(t, handler, http.MethodPost, "/v1/attachments", map[string]any{
		"filename":      "hello.txt",
		"mimeType":      "text/plain",
		"contentBase64": base64.StdEncoding.EncodeToString([]byte("hello")),
	})
	if attachmentResp.Code != http.StatusCreated {
		t.Fatalf("attachment create failed: %d %s", attachmentResp.Code, attachmentResp.Body.String())
	}
	var attachment core.Attachment
	_ = json.Unmarshal(attachmentResp.Body.Bytes(), &attachment)

	attachmentGet := doJSONRequest(t, handler, http.MethodGet, "/v1/attachments/"+attachment.ID, nil)
	if attachmentGet.Code != http.StatusOK || !strings.Contains(attachmentGet.Body.String(), base64.StdEncoding.EncodeToString([]byte("hello"))) {
		t.Fatalf("unexpected attachment get: %d %s", attachmentGet.Code, attachmentGet.Body.String())
	}

	dashboardResp := doJSONRequest(t, handler, http.MethodGet, "/v1/workspaces/"+workspace.ID+"/dashboard", nil)
	if dashboardResp.Code != http.StatusOK || !strings.Contains(dashboardResp.Body.String(), "messageCount") {
		t.Fatalf("unexpected dashboard response: %d %s", dashboardResp.Code, dashboardResp.Body.String())
	}

	serverEventsReq := httptest.NewRequest(http.MethodGet, "/v1/events?after=0", nil)
	serverEventsReq.Header.Set("Authorization", "Bearer secret")
	serverEventsReq.Header.Set("Accept", "text/event-stream")
	serverEventsResp := httptest.NewRecorder()
	handler.ServeHTTP(serverEventsResp, serverEventsReq)
	if serverEventsResp.Code != http.StatusOK || !strings.Contains(serverEventsResp.Body.String(), "event:") {
		t.Fatalf("unexpected server events response: %d %s", serverEventsResp.Code, serverEventsResp.Body.String())
	}
}
