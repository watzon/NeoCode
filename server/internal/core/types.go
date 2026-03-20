package core

import "time"

type ServerMode string

const (
	ServerModeEmbedded ServerMode = "embedded"
	ServerModeRemote   ServerMode = "remote"
)

type ServerInfo struct {
	Name    string        `json:"name"`
	Version string        `json:"version"`
	Mode    ServerMode    `json:"mode"`
	Time    time.Time     `json:"time"`
	Caps    CapabilitySet `json:"capabilities"`
}

type CapabilitySet struct {
	Workspaces  bool `json:"workspaces"`
	Sessions    bool `json:"sessions"`
	Git         bool `json:"git"`
	Files       bool `json:"files"`
	Attachments bool `json:"attachments"`
	Dashboard   bool `json:"dashboard"`
	Events      bool `json:"events"`
}

func DefaultCapabilities() CapabilitySet {
	return CapabilitySet{
		Workspaces:  true,
		Sessions:    true,
		Git:         true,
		Files:       true,
		Attachments: true,
		Dashboard:   true,
		Events:      true,
	}
}

type Workspace struct {
	ID            string        `json:"id"`
	Name          string        `json:"name"`
	RootURI       string        `json:"rootUri,omitempty"`
	LocalPathHint string        `json:"localPathHint,omitempty"`
	IsLocal       bool          `json:"isLocal"`
	Capabilities  CapabilitySet `json:"capabilities"`
	CreatedAt     time.Time     `json:"createdAt"`
	UpdatedAt     time.Time     `json:"updatedAt"`
}

type SessionStatus string

const (
	SessionStatusIdle       SessionStatus = "idle"
	SessionStatusRunning    SessionStatus = "running"
	SessionStatusNeedsInput SessionStatus = "needs_input"
	SessionStatusFailed     SessionStatus = "failed"
	SessionStatusRetry      SessionStatus = "retry"
)

type MessageRole string

const (
	MessageRoleSystem    MessageRole = "system"
	MessageRoleUser      MessageRole = "user"
	MessageRoleAssistant MessageRole = "assistant"
	MessageRoleTool      MessageRole = "tool"
)

type Message struct {
	ID        string            `json:"id"`
	Role      MessageRole       `json:"role"`
	Text      string            `json:"text"`
	Metadata  map[string]string `json:"metadata,omitempty"`
	Summary   map[string]any    `json:"summary,omitempty"`
	CreatedAt time.Time         `json:"createdAt"`
}

type FileChangeSummary struct {
	File      string `json:"file"`
	Before    string `json:"before,omitempty"`
	After     string `json:"after,omitempty"`
	Additions int    `json:"additions"`
	Deletions int    `json:"deletions"`
	Status    string `json:"status,omitempty"`
}

type SessionSummary struct {
	Additions int                 `json:"additions"`
	Deletions int                 `json:"deletions"`
	Files     int                 `json:"files"`
	Diffs     []FileChangeSummary `json:"diffs,omitempty"`
}

type SessionRevert struct {
	MessageID string `json:"messageId"`
	PartID    string `json:"partId,omitempty"`
	Snapshot  string `json:"snapshot,omitempty"`
	Diff      string `json:"diff,omitempty"`
}

type Session struct {
	ID          string          `json:"id"`
	WorkspaceID string          `json:"workspaceId"`
	Title       string          `json:"title"`
	ParentID    string          `json:"parentId,omitempty"`
	Status      SessionStatus   `json:"status"`
	Summary     *SessionSummary `json:"summary,omitempty"`
	Revert      *SessionRevert  `json:"revert,omitempty"`
	Messages    []Message       `json:"messages"`
	CreatedAt   time.Time       `json:"createdAt"`
	UpdatedAt   time.Time       `json:"updatedAt"`
}

type SessionEvent struct {
	ID        string         `json:"id"`
	Cursor    uint64         `json:"cursor"`
	SessionID string         `json:"sessionId"`
	Type      string         `json:"type"`
	Payload   map[string]any `json:"payload,omitempty"`
	CreatedAt time.Time      `json:"createdAt"`
}

type Attachment struct {
	ID        string    `json:"id"`
	Filename  string    `json:"filename"`
	MimeType  string    `json:"mimeType"`
	SizeBytes int64     `json:"sizeBytes"`
	CreatedAt time.Time `json:"createdAt"`
}

type AttachmentRecord struct {
	Attachment
	Content []byte `json:"-"`
}

type GitFileChange struct {
	Path       string `json:"path"`
	Status     string `json:"status"`
	Additions  int    `json:"additions"`
	Deletions  int    `json:"deletions"`
	IsTracked  bool   `json:"isTracked"`
	IsStaged   bool   `json:"isStaged"`
	IsUnstaged bool   `json:"isUnstaged"`
}

type GitStatus struct {
	Branch      string          `json:"branch"`
	AheadCount  int             `json:"aheadCount"`
	BehindCount int             `json:"behindCount"`
	HasRemote   bool            `json:"hasRemote"`
	HasChanges  bool            `json:"hasChanges"`
	Changes     []GitFileChange `json:"changes"`
}

type GitDiff struct {
	Patch     string          `json:"patch"`
	FileCount int             `json:"fileCount"`
	Changes   []GitFileChange `json:"changes"`
}

type GitCommitPreview struct {
	Branch            string          `json:"branch"`
	ChangedFiles      []GitFileChange `json:"changedFiles"`
	StagedAdditions   int             `json:"stagedAdditions"`
	StagedDeletions   int             `json:"stagedDeletions"`
	UnstagedAdditions int             `json:"unstagedAdditions"`
	UnstagedDeletions int             `json:"unstagedDeletions"`
	TotalAdditions    int             `json:"totalAdditions"`
	TotalDeletions    int             `json:"totalDeletions"`
}

type FileMatch struct {
	Path      string `json:"path"`
	Name      string `json:"name"`
	Directory string `json:"directory,omitempty"`
}

type FileContent struct {
	Path     string `json:"path"`
	Content  string `json:"content"`
	Encoding string `json:"encoding"`
}

type ResolvedFileReference struct {
	Path    string `json:"path"`
	Source  string `json:"source"`
	Start   int    `json:"start"`
	End     int    `json:"end"`
	Content string `json:"content,omitempty"`
}

type DashboardSummary struct {
	WorkspaceID       string    `json:"workspaceId"`
	SessionCount      int       `json:"sessionCount"`
	MessageCount      int       `json:"messageCount"`
	UserMessageCount  int       `json:"userMessageCount"`
	AssistantMsgCount int       `json:"assistantMessageCount"`
	LastActivityAt    time.Time `json:"lastActivityAt"`
}

type DashboardTokenTotals struct {
	Input      int `json:"input"`
	Output     int `json:"output"`
	Reasoning  int `json:"reasoning"`
	CacheRead  int `json:"cacheRead"`
	CacheWrite int `json:"cacheWrite"`
}

type DashboardModelUsage struct {
	ID           string               `json:"id"`
	ProviderID   string               `json:"providerID"`
	ModelID      string               `json:"modelID"`
	MessageCount int                  `json:"messageCount"`
	SessionCount int                  `json:"sessionCount"`
	TotalCost    float64              `json:"totalCost"`
	Tokens       DashboardTokenTotals `json:"tokens"`
	LastUsedAt   time.Time            `json:"lastUsedAt,omitempty"`
}

type DashboardToolUsage struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	CallCount    int       `json:"callCount"`
	SessionCount int       `json:"sessionCount"`
	LastUsedAt   time.Time `json:"lastUsedAt,omitempty"`
}

type DashboardSessionStats struct {
	TotalMessages     int                   `json:"totalMessages"`
	UserMessages      int                   `json:"userMessages"`
	AssistantMessages int                   `json:"assistantMessages"`
	ToolCalls         int                   `json:"toolCalls"`
	TotalCost         float64               `json:"totalCost"`
	Tokens            DashboardTokenTotals  `json:"tokens"`
	Models            []DashboardModelUsage `json:"models"`
	Tools             []DashboardToolUsage  `json:"tools"`
	FirstActivityAt   time.Time             `json:"firstActivityAt,omitempty"`
	LastActivityAt    time.Time             `json:"lastActivityAt,omitempty"`
}

type DashboardSessionSummary struct {
	ID        string                `json:"id"`
	Title     string                `json:"title"`
	CreatedAt time.Time             `json:"createdAt"`
	UpdatedAt time.Time             `json:"updatedAt"`
	Stats     DashboardSessionStats `json:"stats"`
}

type ProviderModelLimits struct {
	Context int `json:"context"`
	Input   int `json:"input,omitempty"`
	Output  int `json:"output"`
}

type ProviderModel struct {
	ID         string               `json:"id"`
	ProviderID string               `json:"providerId"`
	Name       string               `json:"name"`
	Limits     *ProviderModelLimits `json:"limits,omitempty"`
	Variants   map[string]any       `json:"variants,omitempty"`
}

type Provider struct {
	ID     string                   `json:"id"`
	Name   string                   `json:"name"`
	Models map[string]ProviderModel `json:"models"`
}

type ProviderResponse struct {
	Providers []Provider        `json:"providers"`
	Default   map[string]string `json:"default,omitempty"`
}

type AgentModel struct {
	ProviderID string `json:"providerId"`
	ModelID    string `json:"modelId"`
}

type Agent struct {
	Name        string      `json:"name"`
	Description string      `json:"description,omitempty"`
	Hidden      bool        `json:"hidden,omitempty"`
	Mode        string      `json:"mode,omitempty"`
	Model       *AgentModel `json:"model,omitempty"`
}

type Command struct {
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	Agent       string   `json:"agent,omitempty"`
	Model       string   `json:"model,omitempty"`
	Source      string   `json:"source,omitempty"`
	Template    string   `json:"template,omitempty"`
	Subtask     bool     `json:"subtask,omitempty"`
	Hints       []string `json:"hints,omitempty"`
}

type PermissionReply string

const (
	PermissionReplyOnce   PermissionReply = "once"
	PermissionReplyAlways PermissionReply = "always"
	PermissionReplyReject PermissionReply = "reject"
)

type ToolReference struct {
	MessageID string `json:"messageId"`
	CallID    string `json:"callId"`
}

type PermissionRequest struct {
	ID         string         `json:"id"`
	SessionID  string         `json:"sessionId"`
	Permission string         `json:"permission"`
	Patterns   []string       `json:"patterns,omitempty"`
	Metadata   map[string]any `json:"metadata,omitempty"`
	Always     []string       `json:"always,omitempty"`
	Tool       *ToolReference `json:"tool,omitempty"`
}

type PermissionReplyEvent struct {
	SessionID string          `json:"sessionId"`
	RequestID string          `json:"requestId"`
	Reply     PermissionReply `json:"reply"`
	Message   string          `json:"message,omitempty"`
}

type QuestionOption struct {
	Label       string `json:"label"`
	Description string `json:"description"`
}

type QuestionInfo struct {
	Question string           `json:"question"`
	Header   string           `json:"header"`
	Options  []QuestionOption `json:"options"`
	Multiple bool             `json:"multiple,omitempty"`
	Custom   bool             `json:"custom,omitempty"`
}

type QuestionAnswer []string

type QuestionRequest struct {
	ID        string         `json:"id"`
	SessionID string         `json:"sessionId"`
	Questions []QuestionInfo `json:"questions"`
	Tool      *ToolReference `json:"tool,omitempty"`
}

type QuestionReplyEvent struct {
	SessionID string           `json:"sessionId"`
	RequestID string           `json:"requestId"`
	Answers   []QuestionAnswer `json:"answers"`
}

type SessionActivity struct {
	Type    string  `json:"type"`
	Attempt int     `json:"attempt,omitempty"`
	Message string  `json:"message,omitempty"`
	Next    float64 `json:"next,omitempty"`
}

type ServerEvent struct {
	ID          string         `json:"id"`
	Cursor      uint64         `json:"cursor"`
	WorkspaceID string         `json:"workspaceId,omitempty"`
	SessionID   string         `json:"sessionId,omitempty"`
	Type        string         `json:"type"`
	Payload     map[string]any `json:"payload,omitempty"`
	CreatedAt   time.Time      `json:"createdAt"`
}
