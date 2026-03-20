package opencode

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/watzon/neocode/server/internal/core"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func newTestClient(fn roundTripFunc) *Client {
	return NewClient("http://example.com", "user", "pass", &http.Client{Transport: fn})
}

func response(status int, body string, contentType string) *http.Response {
	if contentType == "" {
		contentType = "application/json"
	}
	return &http.Response{StatusCode: status, Header: http.Header{"Content-Type": []string{contentType}}, Body: io.NopCloser(strings.NewReader(body))}
}

func TestClientListSessions(t *testing.T) {
	client := newTestClient(func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/session" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		return response(200, `[{"id":"s1","title":"Chat","time":{"created":"2024-01-01T00:00:00Z","updated":"2024-01-01T00:00:01Z"}}]`, "application/json"), nil
	})
	sessions, err := client.ListSessions(context.Background())
	if err != nil {
		t.Fatalf("list sessions: %v", err)
	}
	if len(sessions) != 1 || sessions[0].ID != "s1" {
		t.Fatalf("unexpected sessions: %#v", sessions)
	}
}

func TestClientSendPrompt(t *testing.T) {
	client := newTestClient(func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/session/s1/prompt_async" || r.Method != http.MethodPost {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		return response(204, ``, "application/json"), nil
	})
	err := client.SendPrompt(context.Background(), "s1", core.PromptInput{Text: "hello", ProviderID: "p", ModelID: "m"})
	if err != nil {
		t.Fatalf("send prompt: %v", err)
	}
}

func TestParseSSEStream(t *testing.T) {
	reader := strings.NewReader("event: message.updated\ndata: {\"id\":\"e1\",\"cursor\":1,\"sessionId\":\"s1\",\"type\":\"message.updated\",\"payload\":{\"text\":\"hi\"},\"createdAt\":\"2024-01-01T00:00:00Z\"}\n\n")
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	events := make(chan core.ServerEvent, 1)
	if err := parseSSEStream(ctx, reader, events); err != nil {
		t.Fatalf("parse sse: %v", err)
	}
	close(events)
	event := <-events
	if event.ID != "e1" || event.Type != "message.updated" {
		t.Fatalf("unexpected event: %#v", event)
	}
}
