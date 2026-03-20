package store

import (
	"errors"
	"sort"
	"sync"

	"github.com/watzon/neocode/server/internal/core"
)

var ErrNotFound = errors.New("not found")

type MemoryStore struct {
	mu           sync.RWMutex
	workspaces   map[string]core.Workspace
	sessions     map[string]core.Session
	attachments  map[string]core.AttachmentRecord
	events       map[string][]core.SessionEvent
	cursors      map[string]uint64
	serverEvents []core.ServerEvent
	serverCursor uint64
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		workspaces:   map[string]core.Workspace{},
		sessions:     map[string]core.Session{},
		attachments:  map[string]core.AttachmentRecord{},
		events:       map[string][]core.SessionEvent{},
		cursors:      map[string]uint64{},
		serverEvents: []core.ServerEvent{},
	}
}

func (s *MemoryStore) PutWorkspace(workspace core.Workspace) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.workspaces[workspace.ID] = workspace
}

func (s *MemoryStore) Workspace(id string) (core.Workspace, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	workspace, ok := s.workspaces[id]
	if !ok {
		return core.Workspace{}, ErrNotFound
	}
	return workspace, nil
}

func (s *MemoryStore) Workspaces() []core.Workspace {
	s.mu.RLock()
	defer s.mu.RUnlock()
	items := make([]core.Workspace, 0, len(s.workspaces))
	for _, item := range s.workspaces {
		items = append(items, item)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].CreatedAt.Before(items[j].CreatedAt) })
	return items
}

func (s *MemoryStore) PutSession(session core.Session) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[session.ID] = session
}

func (s *MemoryStore) Session(id string) (core.Session, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	session, ok := s.sessions[id]
	if !ok {
		return core.Session{}, ErrNotFound
	}
	return session, nil
}

func (s *MemoryStore) DeleteSession(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, id)
	delete(s.events, id)
	delete(s.cursors, id)
}

func (s *MemoryStore) SessionsByWorkspace(workspaceID string) []core.Session {
	s.mu.RLock()
	defer s.mu.RUnlock()
	items := make([]core.Session, 0)
	for _, item := range s.sessions {
		if item.WorkspaceID == workspaceID {
			items = append(items, item)
		}
	}
	sort.Slice(items, func(i, j int) bool { return items[i].CreatedAt.Before(items[j].CreatedAt) })
	return items
}

func (s *MemoryStore) PutAttachment(record core.AttachmentRecord) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.attachments[record.ID] = record
}

func (s *MemoryStore) Attachment(id string) (core.AttachmentRecord, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	record, ok := s.attachments[id]
	if !ok {
		return core.AttachmentRecord{}, ErrNotFound
	}
	return record, nil
}

func (s *MemoryStore) AppendEvent(event core.SessionEvent) core.SessionEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cursors[event.SessionID]++
	event.Cursor = s.cursors[event.SessionID]
	s.events[event.SessionID] = append(s.events[event.SessionID], event)
	s.serverCursor++
	s.serverEvents = append(s.serverEvents, core.ServerEvent{
		ID:        event.ID,
		Cursor:    s.serverCursor,
		SessionID: event.SessionID,
		Type:      event.Type,
		Payload:   event.Payload,
		CreatedAt: event.CreatedAt,
	})
	return event
}

func (s *MemoryStore) EventsAfter(sessionID string, after uint64) []core.SessionEvent {
	s.mu.RLock()
	defer s.mu.RUnlock()
	items := s.events[sessionID]
	if len(items) == 0 {
		return nil
	}
	out := make([]core.SessionEvent, 0, len(items))
	for _, item := range items {
		if item.Cursor > after {
			out = append(out, item)
		}
	}
	return out
}

func (s *MemoryStore) AppendServerEvent(event core.ServerEvent) core.ServerEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.serverCursor++
	event.Cursor = s.serverCursor
	s.serverEvents = append(s.serverEvents, event)
	return event
}

func (s *MemoryStore) ServerEventsAfter(after uint64) []core.ServerEvent {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if len(s.serverEvents) == 0 {
		return nil
	}
	out := make([]core.ServerEvent, 0, len(s.serverEvents))
	for _, event := range s.serverEvents {
		if event.Cursor > after {
			out = append(out, event)
		}
	}
	return out
}
