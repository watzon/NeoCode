package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/watzon/neocode/server/internal/auth"
	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/store"
)

type fakeRuntime struct {
	result core.RuntimeResult
	err    error
}

func (f fakeRuntime) HandleInput(context.Context, core.Workspace, core.Session, core.Input) (core.RuntimeResult, error) {
	return f.result, f.err
}

type fakeGit struct {
	status core.GitStatus
	diff   core.GitDiff
}

func (f fakeGit) Status(context.Context, core.Workspace) (core.GitStatus, error) {
	return f.status, nil
}
func (f fakeGit) Diff(context.Context, core.Workspace) (core.GitDiff, error) { return f.diff, nil }
func (f fakeGit) Preview(context.Context, core.Workspace) (core.GitCommitPreview, error) {
	return core.GitCommitPreview{Branch: "main"}, nil
}
func (f fakeGit) Commit(context.Context, core.Workspace, string, bool) error { return nil }
func (f fakeGit) Push(context.Context, core.Workspace) error                 { return nil }
func (f fakeGit) Branches(context.Context, core.Workspace) ([]string, error) {
	return []string{"main"}, nil
}
func (f fakeGit) CurrentBranch(context.Context, core.Workspace) (string, error) { return "main", nil }
func (f fakeGit) Initialize(context.Context, core.Workspace) error              { return nil }
func (f fakeGit) SwitchBranch(context.Context, core.Workspace, string) error    { return nil }
func (f fakeGit) CreateBranch(context.Context, core.Workspace, string) error    { return nil }

type fakeFiles struct {
	matches []core.FileMatch
	content core.FileContent
	refs    []core.ResolvedFileReference
}

func (f fakeFiles) Search(context.Context, core.Workspace, string, int) ([]core.FileMatch, error) {
	return f.matches, nil
}
func (f fakeFiles) Read(context.Context, core.Workspace, string) (core.FileContent, error) {
	return f.content, nil
}
func (f fakeFiles) ResolveReferences(context.Context, core.Workspace, string) ([]core.ResolvedFileReference, error) {
	return f.refs, nil
}

func fixedTime() time.Time { return time.Unix(1700000000, 0).UTC() }

func TestAppWorkspaceSessionAndInputFlow(t *testing.T) {
	app := New(Config{
		Info:          core.ServerInfo{Name: "NeoCode", Version: "test", Mode: core.ServerModeEmbedded},
		Authenticator: auth.StaticToken("token"),
		Store:         store.NewMemoryStore(),
		Runtime: fakeRuntime{result: core.RuntimeResult{
			Status: core.SessionStatusNeedsInput,
			Reply:  &core.Message{Role: core.MessageRoleAssistant, Text: "hi"},
			Events: []core.RuntimeEvent{{Type: "question.created", Payload: map[string]any{"id": "q1"}}},
		}},
		Git:   fakeGit{},
		Files: fakeFiles{},
		Now:   fixedTime,
	})

	workspace, err := app.CreateWorkspace(context.Background(), CreateWorkspaceRequest{Name: "Repo", RootURI: "file:///repo", IsLocal: true})
	if err != nil {
		t.Fatalf("create workspace: %v", err)
	}
	session, err := app.CreateSession(context.Background(), workspace.ID, "Chat")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	session, err = app.SendInput(context.Background(), session.ID, core.Input{Text: "hello", Mode: "chat"})
	if err != nil {
		t.Fatalf("send input: %v", err)
	}
	if session.Status != core.SessionStatusNeedsInput {
		t.Fatalf("unexpected session status: %s", session.Status)
	}
	if len(session.Messages) != 2 {
		t.Fatalf("expected 2 messages, got %d", len(session.Messages))
	}
	events, err := app.SessionEvents(context.Background(), session.ID, 0)
	if err != nil {
		t.Fatalf("session events: %v", err)
	}
	if len(events) != 4 {
		t.Fatalf("expected 4 events, got %d", len(events))
	}
}

func TestAppSendInputRuntimeFailure(t *testing.T) {
	app := New(Config{
		Info:    core.ServerInfo{Name: "NeoCode", Version: "test"},
		Store:   store.NewMemoryStore(),
		Runtime: fakeRuntime{err: errors.New("boom")},
		Git:     fakeGit{},
		Files:   fakeFiles{},
		Now:     fixedTime,
	})
	workspace, _ := app.CreateWorkspace(context.Background(), CreateWorkspaceRequest{Name: "Repo"})
	session, _ := app.CreateSession(context.Background(), workspace.ID, "Chat")
	updated, err := app.SendInput(context.Background(), session.ID, core.Input{Text: "hello"})
	if err == nil {
		t.Fatal("expected error")
	}
	if updated.Status != core.SessionStatusFailed {
		t.Fatalf("unexpected status: %s", updated.Status)
	}
}

func TestAppAttachmentGitFilesAndDashboard(t *testing.T) {
	app := New(Config{
		Info:  core.ServerInfo{Name: "NeoCode", Version: "test"},
		Store: store.NewMemoryStore(),
		Runtime: fakeRuntime{result: core.RuntimeResult{
			Status: core.SessionStatusIdle,
			Reply:  &core.Message{Role: core.MessageRoleAssistant, Text: "done"},
		}},
		Git: fakeGit{status: core.GitStatus{Branch: "main", HasChanges: true}, diff: core.GitDiff{Patch: "diff --git", FileCount: 1}},
		Files: fakeFiles{
			matches: []core.FileMatch{{Path: "main.go", Name: "main.go"}},
			content: core.FileContent{Path: "main.go", Content: "package main", Encoding: "utf-8"},
			refs:    []core.ResolvedFileReference{{Path: "main.go", Source: "@main.go", Start: 0, End: 8}},
		},
		Now: fixedTime,
	})
	workspace, _ := app.CreateWorkspace(context.Background(), CreateWorkspaceRequest{Name: "Repo"})
	attachment, err := app.CreateAttachment(context.Background(), "hello.txt", "text/plain", []byte("hello"))
	if err != nil {
		t.Fatalf("create attachment: %v", err)
	}
	if attachment.SizeBytes != 5 {
		t.Fatalf("unexpected attachment size: %d", attachment.SizeBytes)
	}
	record, err := app.Attachment(context.Background(), attachment.ID)
	if err != nil || string(record.Content) != "hello" {
		t.Fatalf("unexpected attachment fetch: %v %#v", err, record)
	}
	status, err := app.GitStatus(context.Background(), workspace.ID)
	if err != nil || status.Branch != "main" {
		t.Fatalf("unexpected git status: %v %#v", err, status)
	}
	diff, err := app.GitDiff(context.Background(), workspace.ID)
	if err != nil || diff.FileCount != 1 {
		t.Fatalf("unexpected git diff: %v %#v", err, diff)
	}
	matches, err := app.FileSearch(context.Background(), workspace.ID, "main", 10)
	if err != nil || len(matches) != 1 {
		t.Fatalf("unexpected matches: %v %#v", err, matches)
	}
	content, err := app.FileContent(context.Background(), workspace.ID, "main.go")
	if err != nil || content.Content != "package main" {
		t.Fatalf("unexpected content: %v %#v", err, content)
	}
	refs, err := app.ResolveFileReferences(context.Background(), workspace.ID, "@main.go")
	if err != nil || len(refs) != 1 {
		t.Fatalf("unexpected refs: %v %#v", err, refs)
	}
	session, _ := app.CreateSession(context.Background(), workspace.ID, "Chat")
	_, _ = app.SendInput(context.Background(), session.ID, core.Input{Text: "hello"})
	dashboard, err := app.Dashboard(context.Background(), workspace.ID)
	if err != nil {
		t.Fatalf("dashboard: %v", err)
	}
	if dashboard.SessionCount != 1 || dashboard.MessageCount != 2 {
		t.Fatalf("unexpected dashboard: %#v", dashboard)
	}
}

func TestAppSessionManagementAndGitHelpers(t *testing.T) {
	app := New(Config{
		Info:    core.ServerInfo{Name: "NeoCode", Version: "test"},
		Store:   store.NewMemoryStore(),
		Runtime: fakeRuntime{result: core.RuntimeResult{Status: core.SessionStatusIdle}},
		Git:     fakeGit{status: core.GitStatus{Branch: "main"}},
		Files:   fakeFiles{},
		Now:     fixedTime,
	})
	workspace, _ := app.CreateWorkspace(context.Background(), CreateWorkspaceRequest{Name: "Repo"})
	session, _ := app.CreateSession(context.Background(), workspace.ID, "Chat")
	updated, err := app.UpdateSession(context.Background(), session.ID, "Renamed")
	if err != nil || updated.Title != "Renamed" {
		t.Fatalf("update session: %v %#v", err, updated)
	}
	statuses, err := app.SessionStatuses(context.Background(), workspace.ID)
	if err != nil || statuses[session.ID].Type != "idle" {
		t.Fatalf("session statuses: %v %#v", err, statuses)
	}
	branches, current, err := app.GitBranches(context.Background(), workspace.ID)
	if err != nil || current != "main" || len(branches) != 1 {
		t.Fatalf("git branches: %v %v %q", err, branches, current)
	}
	if err := app.GitCommit(context.Background(), workspace.ID, "msg", true); err != nil {
		t.Fatalf("git commit: %v", err)
	}
	ok, err := app.DeleteSession(context.Background(), session.ID)
	if err != nil || !ok {
		t.Fatalf("delete session: %v %v", ok, err)
	}
}
