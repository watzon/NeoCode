package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/watzon/neocode/server/internal/core"
)

type EchoRuntime struct{}

func (EchoRuntime) HandleInput(_ context.Context, _ core.Workspace, _ core.Session, input core.Input) (core.RuntimeResult, error) {
	text := strings.TrimSpace(input.Text)
	return core.RuntimeResult{
		Status: core.SessionStatusIdle,
		Reply: &core.Message{
			Role: core.MessageRoleAssistant,
			Text: fmt.Sprintf("Echo: %s", text),
		},
		Events: []core.RuntimeEvent{{Type: "runtime.completed", Payload: map[string]any{"mode": input.Mode}}},
	}, nil
}

type NoopGitProvider struct{}

func (NoopGitProvider) Status(context.Context, core.Workspace) (core.GitStatus, error) {
	return core.GitStatus{}, nil
}

func (NoopGitProvider) Diff(context.Context, core.Workspace) (core.GitDiff, error) {
	return core.GitDiff{}, nil
}

func (NoopGitProvider) Preview(context.Context, core.Workspace) (core.GitCommitPreview, error) {
	return core.GitCommitPreview{}, nil
}

func (NoopGitProvider) Commit(context.Context, core.Workspace, string, bool) error    { return nil }
func (NoopGitProvider) Push(context.Context, core.Workspace) error                    { return nil }
func (NoopGitProvider) Branches(context.Context, core.Workspace) ([]string, error)    { return nil, nil }
func (NoopGitProvider) CurrentBranch(context.Context, core.Workspace) (string, error) { return "", nil }
func (NoopGitProvider) Initialize(context.Context, core.Workspace) error              { return nil }
func (NoopGitProvider) SwitchBranch(context.Context, core.Workspace, string) error    { return nil }
func (NoopGitProvider) CreateBranch(context.Context, core.Workspace, string) error    { return nil }

type NoopFileProvider struct{}

func (NoopFileProvider) Search(context.Context, core.Workspace, string, int) ([]core.FileMatch, error) {
	return []core.FileMatch{}, nil
}

func (NoopFileProvider) Read(context.Context, core.Workspace, string) (core.FileContent, error) {
	return core.FileContent{}, nil
}

func (NoopFileProvider) ResolveReferences(context.Context, core.Workspace, string) ([]core.ResolvedFileReference, error) {
	return []core.ResolvedFileReference{}, nil
}
