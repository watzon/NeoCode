package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestShouldLogRequest(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		path       string
		statusCode int
		duration   time.Duration
		expectLog  bool
	}{
		{name: "successful get is quiet", method: http.MethodGet, path: "/v1/server", statusCode: http.StatusOK, duration: 100 * time.Millisecond, expectLog: false},
		{name: "mutating request logs", method: http.MethodPost, path: "/v1/workspaces", statusCode: http.StatusCreated, duration: 100 * time.Millisecond, expectLog: true},
		{name: "git request logs", method: http.MethodGet, path: "/v1/workspaces/ws_1/git/status", statusCode: http.StatusOK, duration: 100 * time.Millisecond, expectLog: true},
		{name: "slow request logs", method: http.MethodGet, path: "/v1/server", statusCode: http.StatusOK, duration: 3 * time.Second, expectLog: true},
		{name: "error request logs", method: http.MethodGet, path: "/v1/server", statusCode: http.StatusBadRequest, duration: 100 * time.Millisecond, expectLog: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := httptest.NewRequest(test.method, test.path, nil)
			if got := shouldLogRequest(req, test.statusCode, test.duration); got != test.expectLog {
				t.Fatalf("expected %t, got %t", test.expectLog, got)
			}
		})
	}
}

func TestRequestWorkspaceID(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/workspaces/ws_123/git/status", nil)
	if got := requestWorkspaceID(req); got != "ws_123" {
		t.Fatalf("expected workspace id, got %q", got)
	}

	headerReq := httptest.NewRequest(http.MethodGet, "/v1/server", nil)
	headerReq.Header.Set("X-NeoCode-Workspace-ID", "ws_header")
	if got := requestWorkspaceID(headerReq); got != "ws_header" {
		t.Fatalf("expected header workspace id, got %q", got)
	}
}

func TestCompactLogMessage(t *testing.T) {
	message := compactLogMessage("  first\n\n second   third  ")
	if message != "first second third" {
		t.Fatalf("unexpected compacted message: %q", message)
	}
}
