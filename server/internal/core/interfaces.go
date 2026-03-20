package core

import (
	"context"
	"encoding/json"
)

type Authenticator interface {
	Authorize(token string) bool
}

type Runtime interface {
	HandleInput(ctx context.Context, workspace Workspace, session Session, input Input) (RuntimeResult, error)
}

type RuntimeBridge interface {
	SessionStatuses(ctx context.Context, workspace Workspace) (map[string]SessionActivity, error)
	ListSessions(ctx context.Context, workspace Workspace) ([]Session, error)
	CreateSession(ctx context.Context, workspace Workspace, title string) (Session, error)
	UpdateSession(ctx context.Context, workspace Workspace, sessionID, title string) (Session, error)
	DeleteSession(ctx context.Context, workspace Workspace, sessionID string) (bool, error)
	SummarizeSession(ctx context.Context, workspace Workspace, sessionID, providerID, modelID string, auto bool) error
	RevertSession(ctx context.Context, workspace Workspace, sessionID, messageID, partID string) (Session, error)
	UnrevertSession(ctx context.Context, workspace Workspace, sessionID string) (Session, error)
	AbortSession(ctx context.Context, workspace Workspace, sessionID string) error
	ReplyToPermission(ctx context.Context, workspace Workspace, requestID string, reply PermissionReply, message string) error
	ReplyToQuestion(ctx context.Context, workspace Workspace, requestID string, answers []QuestionAnswer) error
	RejectQuestion(ctx context.Context, workspace Workspace, requestID string) error
	ListProviders(ctx context.Context, workspace Workspace) (ProviderResponse, error)
	ListAgents(ctx context.Context, workspace Workspace) ([]Agent, error)
	ListCommands(ctx context.Context, workspace Workspace) ([]Command, error)
	ListMessageEnvelopes(ctx context.Context, workspace Workspace, sessionID string) ([]json.RawMessage, error)
	ListMessages(ctx context.Context, workspace Workspace, sessionID string) ([]Message, error)
	DashboardSessionSummaries(ctx context.Context, workspace Workspace, sessionIDs []string) ([]DashboardSessionSummary, error)
	ListPermissions(ctx context.Context, workspace Workspace) ([]PermissionRequest, error)
	ListQuestions(ctx context.Context, workspace Workspace) ([]QuestionRequest, error)
	SendPrompt(ctx context.Context, workspace Workspace, sessionID string, input PromptInput) error
	SendCommand(ctx context.Context, workspace Workspace, sessionID string, input CommandInput) error
	StreamEvents(ctx context.Context, workspace Workspace) (<-chan ServerEvent, <-chan error, error)
}

type GitProvider interface {
	Status(ctx context.Context, workspace Workspace) (GitStatus, error)
	Diff(ctx context.Context, workspace Workspace) (GitDiff, error)
	Preview(ctx context.Context, workspace Workspace) (GitCommitPreview, error)
	Commit(ctx context.Context, workspace Workspace, message string, includeUnstaged bool) error
	Push(ctx context.Context, workspace Workspace) error
	Branches(ctx context.Context, workspace Workspace) ([]string, error)
	CurrentBranch(ctx context.Context, workspace Workspace) (string, error)
	Initialize(ctx context.Context, workspace Workspace) error
	SwitchBranch(ctx context.Context, workspace Workspace, branch string) error
	CreateBranch(ctx context.Context, workspace Workspace, branch string) error
}

type FileProvider interface {
	Search(ctx context.Context, workspace Workspace, query string, limit int) ([]FileMatch, error)
	Read(ctx context.Context, workspace Workspace, path string) (FileContent, error)
	ResolveReferences(ctx context.Context, workspace Workspace, text string) ([]ResolvedFileReference, error)
}

type Input struct {
	Text          string            `json:"text"`
	Mode          string            `json:"mode,omitempty"`
	AttachmentIDs []string          `json:"attachmentIds,omitempty"`
	Metadata      map[string]string `json:"metadata,omitempty"`
}

type RuntimeResult struct {
	Status SessionStatus  `json:"status"`
	Reply  *Message       `json:"reply,omitempty"`
	Events []RuntimeEvent `json:"events,omitempty"`
}

type RuntimeEvent struct {
	Type    string         `json:"type"`
	Payload map[string]any `json:"payload,omitempty"`
}

type PromptPart struct {
	Type     string         `json:"type"`
	Text     string         `json:"text,omitempty"`
	Mime     string         `json:"mime,omitempty"`
	Filename string         `json:"filename,omitempty"`
	URL      string         `json:"url,omitempty"`
	Source   map[string]any `json:"source,omitempty"`
	Metadata map[string]any `json:"metadata,omitempty"`
}

type PromptInput struct {
	Text       string       `json:"text,omitempty"`
	Parts      []PromptPart `json:"parts,omitempty"`
	ProviderID string       `json:"providerId,omitempty"`
	ModelID    string       `json:"modelId,omitempty"`
	Agent      string       `json:"agent,omitempty"`
	Variant    string       `json:"variant,omitempty"`
}

type CommandInput struct {
	Command   string       `json:"command"`
	Arguments string       `json:"arguments,omitempty"`
	Parts     []PromptPart `json:"parts,omitempty"`
	Agent     string       `json:"agent,omitempty"`
	Model     string       `json:"model,omitempty"`
	Variant   string       `json:"variant,omitempty"`
}
