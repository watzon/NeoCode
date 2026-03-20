package store

import (
	"testing"
	"time"

	"github.com/watzon/neocode/server/internal/core"
)

func TestMemoryStoreWorkspaceAndSessionLifecycle(t *testing.T) {
	s := NewMemoryStore()
	now := time.Unix(100, 0).UTC()
	workspace := core.Workspace{ID: "ws_1", Name: "App", CreatedAt: now}
	s.PutWorkspace(workspace)

	gotWorkspace, err := s.Workspace("ws_1")
	if err != nil {
		t.Fatalf("workspace: %v", err)
	}
	if gotWorkspace.Name != "App" {
		t.Fatalf("unexpected workspace name: %s", gotWorkspace.Name)
	}

	session := core.Session{ID: "sess_1", WorkspaceID: workspace.ID, Title: "New", CreatedAt: now}
	s.PutSession(session)
	gotSession, err := s.Session("sess_1")
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	if gotSession.WorkspaceID != workspace.ID {
		t.Fatalf("unexpected workspace id: %s", gotSession.WorkspaceID)
	}

	list := s.SessionsByWorkspace(workspace.ID)
	if len(list) != 1 {
		t.Fatalf("expected 1 session, got %d", len(list))
	}
}

func TestMemoryStoreEventsAfter(t *testing.T) {
	s := NewMemoryStore()
	first := s.AppendEvent(core.SessionEvent{ID: "evt_1", SessionID: "sess_1", Type: "one"})
	second := s.AppendEvent(core.SessionEvent{ID: "evt_2", SessionID: "sess_1", Type: "two"})

	if first.Cursor != 1 || second.Cursor != 2 {
		t.Fatalf("unexpected cursors: %d %d", first.Cursor, second.Cursor)
	}

	events := s.EventsAfter("sess_1", 1)
	if len(events) != 1 || events[0].Type != "two" {
		t.Fatalf("unexpected events: %#v", events)
	}
}
