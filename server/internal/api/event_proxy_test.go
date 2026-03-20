package api

import "testing"

func TestShouldSuppressEventProxyPayloadFiltersUserMessageFrames(t *testing.T) {
	state := &eventProxyFilterState{userMessageIDs: map[string]struct{}{}}

	if !shouldSuppressEventProxyPayload(`{"type":"message.updated","properties":{"info":{"id":"msg_1","role":"user"}}}`, state) {
		t.Fatal("expected user message.updated to be suppressed")
	}
	if _, ok := state.userMessageIDs["msg_1"]; !ok {
		t.Fatal("expected user message ID to be tracked")
	}
	if !shouldSuppressEventProxyPayload(`{"type":"message.part.updated","properties":{"part":{"messageID":"msg_1"}}}`, state) {
		t.Fatal("expected user message.part.updated to be suppressed")
	}
	if !shouldSuppressEventProxyPayload(`{"type":"message.part.delta","properties":{"messageID":"msg_1"}}`, state) {
		t.Fatal("expected user message.part.delta to be suppressed")
	}
	if shouldSuppressEventProxyPayload(`{"type":"message.updated","properties":{"info":{"id":"msg_2","role":"assistant"}}}`, state) {
		t.Fatal("did not expect assistant message.updated to be suppressed")
	}
}
