package opencode

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/watzon/neocode/server/internal/core"
)

type Client struct {
	baseURL  string
	username string
	password string
	http     *http.Client
}

func NewClient(baseURL, username, password string, httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 30 * time.Second}
	}
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), username: username, password: password, http: httpClient}
}

func (c *Client) Health(ctx context.Context) (bool, string, error) {
	var payload struct {
		Healthy bool   `json:"healthy"`
		Version string `json:"version"`
	}
	if err := c.request(ctx, http.MethodGet, "/global/health", nil, &payload, "application/json"); err != nil {
		return false, "", err
	}
	return payload.Healthy, payload.Version, nil
}

func (c *Client) SessionStatuses(ctx context.Context) (map[string]core.SessionActivity, error) {
	var payload map[string]struct {
		Type    string  `json:"type"`
		Attempt int     `json:"attempt"`
		Message string  `json:"message"`
		Next    float64 `json:"next"`
	}
	if err := c.request(ctx, http.MethodGet, "/session/status", nil, &payload, "application/json"); err != nil {
		return nil, err
	}
	out := make(map[string]core.SessionActivity, len(payload))
	for key, value := range payload {
		out[key] = core.SessionActivity{Type: value.Type, Attempt: value.Attempt, Message: value.Message, Next: value.Next}
	}
	return out, nil
}

func (c *Client) ListSessions(ctx context.Context) ([]core.Session, error) {
	var payload []sessionDTO
	if err := c.request(ctx, http.MethodGet, "/session", nil, &payload, "application/json"); err != nil {
		return nil, err
	}
	return toSessions(payload), nil
}

func (c *Client) CreateSession(ctx context.Context, title string) (core.Session, error) {
	var payload sessionDTO
	body := map[string]any{"title": emptyToNil(title)}
	if err := c.request(ctx, http.MethodPost, "/session", body, &payload, "application/json"); err != nil {
		return core.Session{}, err
	}
	return payload.toCore(), nil
}

func (c *Client) UpdateSession(ctx context.Context, sessionID, title string) (core.Session, error) {
	var payload sessionDTO
	if err := c.request(ctx, http.MethodPatch, "/session/"+sessionID, map[string]any{"title": title}, &payload, "application/json"); err != nil {
		return core.Session{}, err
	}
	return payload.toCore(), nil
}

func (c *Client) DeleteSession(ctx context.Context, sessionID string) (bool, error) {
	var ok bool
	err := c.request(ctx, http.MethodDelete, "/session/"+sessionID, nil, &ok, "application/json")
	return ok, err
}

func (c *Client) SummarizeSession(ctx context.Context, sessionID, providerID, modelID string, auto bool) error {
	return c.request(ctx, http.MethodPost, "/session/"+sessionID+"/summarize", map[string]any{"providerID": providerID, "modelID": modelID, "auto": auto}, nil, "application/json")
}

func (c *Client) RevertSession(ctx context.Context, sessionID, messageID, partID string) (core.Session, error) {
	var payload sessionDTO
	err := c.request(ctx, http.MethodPost, "/session/"+sessionID+"/revert", map[string]any{"messageID": messageID, "partID": emptyToNil(partID)}, &payload, "application/json")
	return payload.toCore(), err
}

func (c *Client) UnrevertSession(ctx context.Context, sessionID string) (core.Session, error) {
	var payload sessionDTO
	err := c.request(ctx, http.MethodPost, "/session/"+sessionID+"/unrevert", nil, &payload, "application/json")
	return payload.toCore(), err
}

func (c *Client) AbortSession(ctx context.Context, sessionID string) error {
	return c.request(ctx, http.MethodPost, "/session/"+sessionID+"/abort", nil, nil, "application/json")
}

func (c *Client) ListPermissions(ctx context.Context) ([]core.PermissionRequest, error) {
	var payload []core.PermissionRequest
	err := c.request(ctx, http.MethodGet, "/permission", nil, &payload, "application/json")
	return payload, err
}

func (c *Client) ReplyPermission(ctx context.Context, requestID string, reply core.PermissionReply, message string) error {
	return c.request(ctx, http.MethodPost, "/permission/"+requestID+"/reply", map[string]any{"reply": reply, "message": emptyToNil(message)}, nil, "application/json")
}

func (c *Client) ListQuestions(ctx context.Context) ([]core.QuestionRequest, error) {
	var payload []core.QuestionRequest
	err := c.request(ctx, http.MethodGet, "/question", nil, &payload, "application/json")
	return payload, err
}

func (c *Client) ReplyQuestion(ctx context.Context, requestID string, answers []core.QuestionAnswer) error {
	return c.request(ctx, http.MethodPost, "/question/"+requestID+"/reply", map[string]any{"answers": answers}, nil, "application/json")
}

func (c *Client) RejectQuestion(ctx context.Context, requestID string) error {
	return c.request(ctx, http.MethodPost, "/question/"+requestID+"/reject", nil, nil, "application/json")
}

func (c *Client) ListProviders(ctx context.Context) (core.ProviderResponse, error) {
	var payload struct {
		Providers []core.Provider   `json:"providers"`
		Default   map[string]string `json:"default"`
	}
	err := c.request(ctx, http.MethodGet, "/config/providers", nil, &payload, "application/json")
	return core.ProviderResponse{Providers: payload.Providers, Default: payload.Default}, err
}

func (c *Client) ListAgents(ctx context.Context) ([]core.Agent, error) {
	var payload []core.Agent
	err := c.request(ctx, http.MethodGet, "/agent", nil, &payload, "application/json")
	return payload, err
}

func (c *Client) ListCommands(ctx context.Context) ([]core.Command, error) {
	var payload []commandDTO
	err := c.request(ctx, http.MethodGet, "/command", nil, &payload, "application/json")
	if err != nil {
		return nil, err
	}
	out := make([]core.Command, 0, len(payload))
	for _, item := range payload {
		out = append(out, item.toCore())
	}
	return out, nil
}

func (c *Client) ListMessages(ctx context.Context, sessionID string) ([]core.Message, error) {
	var envelopes []messageEnvelopeDTO
	err := c.request(ctx, http.MethodGet, "/session/"+sessionID+"/message", nil, &envelopes, "application/json")
	if err != nil {
		return nil, err
	}
	return toMessages(envelopes), nil
}

func (c *Client) RawMessages(ctx context.Context, sessionID string) ([]json.RawMessage, error) {
	var envelopes []json.RawMessage
	err := c.request(ctx, http.MethodGet, "/session/"+sessionID+"/message", nil, &envelopes, "application/json")
	if err != nil {
		return nil, err
	}
	return envelopes, nil
}

func (c *Client) DashboardSessionSummaries(ctx context.Context, sessions []core.Session) ([]core.DashboardSessionSummary, error) {
	out := make([]core.DashboardSessionSummary, 0, len(sessions))
	for _, session := range sessions {
		var envelopes []messageEnvelopeDTO
		if err := c.request(ctx, http.MethodGet, "/session/"+session.ID+"/message", nil, &envelopes, "application/json"); err != nil {
			return nil, err
		}
		out = append(out, summarizeDashboardSession(session, envelopes))
	}
	return out, nil
}

func (c *Client) SendPrompt(ctx context.Context, sessionID string, input core.PromptInput) error {
	body := map[string]any{"parts": promptParts(input)}
	if input.ProviderID != "" || input.ModelID != "" {
		body["model"] = map[string]any{"providerID": input.ProviderID, "modelID": input.ModelID}
	}
	if input.Agent != "" {
		body["agent"] = input.Agent
	}
	if input.Variant != "" {
		body["variant"] = input.Variant
	}
	return c.request(ctx, http.MethodPost, "/session/"+sessionID+"/prompt_async", body, nil, "application/json")
}

func (c *Client) SendCommand(ctx context.Context, sessionID string, input core.CommandInput) error {
	body := map[string]any{"command": input.Command, "arguments": input.Arguments}
	if input.Agent != "" {
		body["agent"] = input.Agent
	}
	if input.Model != "" {
		body["model"] = input.Model
	}
	if input.Variant != "" {
		body["variant"] = input.Variant
	}
	parts := promptPartsFromCommand(input)
	if len(parts) > 0 {
		body["parts"] = parts
	}
	var ignored any
	return c.request(ctx, http.MethodPost, "/session/"+sessionID+"/command", body, &ignored, "application/json")
}

func (c *Client) StreamEvents(ctx context.Context) (<-chan core.ServerEvent, <-chan error, error) {
	req, err := c.newRequest(ctx, http.MethodGet, "/event", nil, "text/event-stream")
	if err != nil {
		return nil, nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		return nil, nil, fmt.Errorf("opencode event stream status %d: %s", resp.StatusCode, string(body))
	}
	events := make(chan core.ServerEvent)
	errCh := make(chan error, 1)
	go func() {
		defer resp.Body.Close()
		defer close(events)
		defer close(errCh)
		if err := parseSSEStream(ctx, resp.Body, events); err != nil && ctx.Err() == nil {
			errCh <- err
		}
	}()
	return events, errCh, nil
}

func (c *Client) RawEventStream(ctx context.Context) (*http.Response, error) {
	req, err := c.newRequest(ctx, http.MethodGet, "/event", nil, "text/event-stream")
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("opencode raw event stream status %d: %s", resp.StatusCode, string(body))
	}
	return resp, nil
}

func (c *Client) request(ctx context.Context, method, path string, body any, out any, accept string) error {
	req, err := c.newRequest(ctx, method, path, body, accept)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		payload, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("opencode %s %s returned %d: %s", method, path, resp.StatusCode, strings.TrimSpace(string(payload)))
	}
	if out == nil || resp.StatusCode == http.StatusNoContent {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *Client) newRequest(ctx context.Context, method, path string, body any, accept string) (*http.Request, error) {
	var reader io.Reader
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", basicAuth(c.username, c.password))
	req.Header.Set("Accept", accept)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return req, nil
}

func basicAuth(username, password string) string {
	token := base64.StdEncoding.EncodeToString([]byte(username + ":" + password))
	return "Basic " + token
}

func parseSSEStream(ctx context.Context, reader io.Reader, events chan<- core.ServerEvent) error {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 16*1024), 1024*1024)
	var eventType string
	var dataLines []string
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		line := scanner.Text()
		if line == "" {
			if len(dataLines) > 0 {
				event, err := decodeSSEEvent(eventType, strings.Join(dataLines, "\n"))
				if err != nil {
					return err
				}
				events <- event
			}
			eventType = ""
			dataLines = nil
			continue
		}
		if strings.HasPrefix(line, "event:") {
			eventType = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
			continue
		}
		if strings.HasPrefix(line, "data:") {
			dataLines = append(dataLines, strings.TrimSpace(strings.TrimPrefix(line, "data:")))
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	if len(dataLines) > 0 {
		event, err := decodeSSEEvent(eventType, strings.Join(dataLines, "\n"))
		if err != nil {
			return err
		}
		events <- event
	}
	return nil
}

func decodeSSEEvent(eventType, payload string) (core.ServerEvent, error) {
	var event core.ServerEvent
	if err := json.Unmarshal([]byte(payload), &event); err != nil {
		return core.ServerEvent{}, err
	}
	if event.Type == "" {
		event.Type = eventType
	}
	return event, nil
}

func promptParts(input core.PromptInput) []map[string]any {
	parts := make([]map[string]any, 0, len(input.Parts)+1)
	if strings.TrimSpace(input.Text) != "" {
		parts = append(parts, map[string]any{"type": "text", "text": input.Text})
	}
	for _, part := range input.Parts {
		parts = append(parts, promptPart(part))
	}
	return parts
}

func promptPartsFromCommand(input core.CommandInput) []map[string]any {
	parts := make([]map[string]any, 0, len(input.Parts))
	for _, part := range input.Parts {
		parts = append(parts, promptPart(part))
	}
	return parts
}

func promptPart(part core.PromptPart) map[string]any {
	out := map[string]any{"type": part.Type}
	if part.Text != "" {
		out["text"] = part.Text
	}
	if part.Mime != "" {
		out["mime"] = part.Mime
	}
	if part.Filename != "" {
		out["filename"] = part.Filename
	}
	if part.URL != "" {
		out["url"] = part.URL
	}
	if len(part.Source) > 0 {
		out["source"] = part.Source
	}
	return out
}

func emptyToNil(value string) any {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return value
}

type sessionDTO struct {
	ID       string                  `json:"id"`
	Title    string                  `json:"title"`
	ParentID string                  `json:"parentID"`
	Summary  *core.SessionSummary    `json:"summary"`
	Revert   *core.SessionRevert     `json:"revert"`
	Time     map[string]flexibleTime `json:"time"`
}

func (s sessionDTO) toCore() core.Session {
	created := s.Time["created"].Time
	updated := s.Time["updated"].Time
	if updated.IsZero() {
		updated = created
	}
	return core.Session{ID: s.ID, Title: s.Title, ParentID: s.ParentID, Summary: s.Summary, Revert: s.Revert, CreatedAt: created, UpdatedAt: updated}
}

func toSessions(in []sessionDTO) []core.Session {
	out := make([]core.Session, 0, len(in))
	for _, item := range in {
		out = append(out, item.toCore())
	}
	return out
}

type messageEnvelopeDTO struct {
	Info struct {
		ID         string                  `json:"id"`
		SessionID  string                  `json:"sessionID"`
		Role       string                  `json:"role"`
		Summary    map[string]any          `json:"summary"`
		ProviderID string                  `json:"providerID"`
		ModelID    string                  `json:"modelID"`
		Cost       float64                 `json:"cost"`
		Tokens     *tokenUsageDTO          `json:"tokens"`
		Time       map[string]flexibleTime `json:"time"`
	} `json:"info"`
	Parts []struct {
		Type string                  `json:"type"`
		Text flexibleText            `json:"text"`
		Tool string                  `json:"tool"`
		Time map[string]flexibleTime `json:"time"`
	} `json:"parts"`
}

func toMessages(in []messageEnvelopeDTO) []core.Message {
	out := make([]core.Message, 0, len(in))
	for _, env := range in {
		textParts := make([]string, 0, len(env.Parts))
		for _, part := range env.Parts {
			if part.Type == "text" && strings.TrimSpace(part.Text.Value) != "" {
				textParts = append(textParts, part.Text.Value)
			}
		}
		createdAt := env.Info.Time["created"].Time
		if createdAt.IsZero() {
			createdAt = env.Info.Time["completed"].Time
		}
		out = append(out, core.Message{ID: env.Info.ID, Role: core.MessageRole(env.Info.Role), Text: strings.Join(textParts, "\n"), Summary: env.Info.Summary, CreatedAt: createdAt})
	}
	return out
}

type flexibleText struct{ Value string }

func (f *flexibleText) UnmarshalJSON(data []byte) error {
	var stringValue string
	if err := json.Unmarshal(data, &stringValue); err == nil {
		f.Value = stringValue
		return nil
	}
	var objectValue struct {
		Value string `json:"value"`
	}
	if err := json.Unmarshal(data, &objectValue); err != nil {
		return err
	}
	f.Value = objectValue.Value
	return nil
}

type tokenUsageDTO struct {
	Input     int `json:"input"`
	Output    int `json:"output"`
	Reasoning int `json:"reasoning"`
	Cache     *struct {
		Read  int `json:"read"`
		Write int `json:"write"`
	} `json:"cache"`
}

func summarizeDashboardSession(session core.Session, envelopes []messageEnvelopeDTO) core.DashboardSessionSummary {
	stats := core.DashboardSessionStats{Models: []core.DashboardModelUsage{}, Tools: []core.DashboardToolUsage{}}
	modelIndex := map[string]int{}
	toolIndex := map[string]int{}
	firstActivityAt := session.CreatedAt
	lastActivityAt := session.UpdatedAt

	for _, envelope := range envelopes {
		stats.TotalMessages++
		messageTime := envelope.Info.Time["completed"].Time
		if messageTime.IsZero() {
			messageTime = envelope.Info.Time["updated"].Time
		}
		if messageTime.IsZero() {
			messageTime = envelope.Info.Time["created"].Time
		}
		if firstActivityAt.IsZero() || (!messageTime.IsZero() && messageTime.Before(firstActivityAt)) {
			firstActivityAt = messageTime
		}
		if messageTime.After(lastActivityAt) {
			lastActivityAt = messageTime
		}

		switch envelope.Info.Role {
		case "user":
			stats.UserMessages++
		case "assistant":
			stats.AssistantMessages++
			stats.TotalCost += envelope.Info.Cost
			if envelope.Info.Tokens != nil {
				stats.Tokens.Input += envelope.Info.Tokens.Input
				stats.Tokens.Output += envelope.Info.Tokens.Output
				stats.Tokens.Reasoning += envelope.Info.Tokens.Reasoning
				if envelope.Info.Tokens.Cache != nil {
					stats.Tokens.CacheRead += envelope.Info.Tokens.Cache.Read
					stats.Tokens.CacheWrite += envelope.Info.Tokens.Cache.Write
				}
			}
			if envelope.Info.ProviderID != "" && envelope.Info.ModelID != "" {
				key := envelope.Info.ProviderID + "/" + envelope.Info.ModelID
				if index, ok := modelIndex[key]; ok {
					stats.Models[index].MessageCount += 1
					stats.Models[index].SessionCount = 1
					stats.Models[index].TotalCost += envelope.Info.Cost
				} else {
					modelIndex[key] = len(stats.Models)
					stats.Models = append(stats.Models, core.DashboardModelUsage{ID: key, ProviderID: envelope.Info.ProviderID, ModelID: envelope.Info.ModelID, MessageCount: 1, SessionCount: 1, TotalCost: envelope.Info.Cost})
				}
			}
		}

		for _, part := range envelope.Parts {
			if part.Type != "tool" || strings.TrimSpace(part.Tool) == "" {
				continue
			}
			stats.ToolCalls += 1
			if index, ok := toolIndex[part.Tool]; ok {
				stats.Tools[index].CallCount += 1
				stats.Tools[index].SessionCount = 1
			} else {
				toolIndex[part.Tool] = len(stats.Tools)
				stats.Tools = append(stats.Tools, core.DashboardToolUsage{ID: part.Tool, Name: part.Tool, CallCount: 1, SessionCount: 1})
			}
		}
	}

	stats.FirstActivityAt = firstActivityAt
	stats.LastActivityAt = lastActivityAt
	return core.DashboardSessionSummary{ID: session.ID, Title: session.Title, CreatedAt: session.CreatedAt, UpdatedAt: session.UpdatedAt, Stats: stats}
}

type flexibleTime struct{ time.Time }

func (f *flexibleTime) UnmarshalJSON(data []byte) error {
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" || trimmed == "null" || trimmed == `""` {
		f.Time = time.Time{}
		return nil
	}
	if strings.HasPrefix(trimmed, `"`) {
		var value string
		if err := json.Unmarshal(data, &value); err != nil {
			return err
		}
		if value == "" {
			f.Time = time.Time{}
			return nil
		}
		if parsed, err := time.Parse(time.RFC3339Nano, value); err == nil {
			f.Time = parsed
			return nil
		}
		if parsed, err := strconv.ParseFloat(value, 64); err == nil {
			f.Time = unixishTime(parsed)
			return nil
		}
		return fmt.Errorf("unsupported time string %q", value)
	}
	parsed, err := strconv.ParseFloat(trimmed, 64)
	if err != nil {
		return err
	}
	f.Time = unixishTime(parsed)
	return nil
}

func unixishTime(value float64) time.Time {
	if value > 10_000_000_000 {
		value /= 1000
	}
	seconds := int64(value)
	nanos := int64((value - float64(seconds)) * float64(time.Second))
	return time.Unix(seconds, nanos).UTC()
}

type commandDTO struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Agent       string          `json:"agent"`
	Model       string          `json:"model"`
	Source      string          `json:"source"`
	Template    json.RawMessage `json:"template"`
	Subtask     bool            `json:"subtask"`
	Hints       []string        `json:"hints"`
}

func (c commandDTO) toCore() core.Command {
	template := ""
	if len(c.Template) > 0 && string(c.Template) != "null" {
		_ = json.Unmarshal(c.Template, &template)
	}
	return core.Command{
		Name:        c.Name,
		Description: c.Description,
		Agent:       c.Agent,
		Model:       c.Model,
		Source:      c.Source,
		Template:    template,
		Subtask:     c.Subtask,
		Hints:       c.Hints,
	}
}
