package api

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

func (h *Handler) handleWorkspaceEventStream(w http.ResponseWriter, r *http.Request, workspaceID string) {
	resp, err := h.app.RawRuntimeEventStream(r.Context(), workspaceID)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)

	state := eventProxyFilterState{userMessageIDs: map[string]struct{}{}}
	current := resp
	defer func() {
		if current != nil && current.Body != nil {
			current.Body.Close()
		}
	}()

	for {
		if err := writeSyntheticEventProxyFrame(w, "server.connected", []byte(`{"type":"server.connected","properties":{}}`)); err != nil {
			return
		}

		if err := streamEventProxyFrames(r.Context(), w, current.Body, &state); err != nil {
			return
		}
		current.Body.Close()

		select {
		case <-r.Context().Done():
			return
		case <-time.After(250 * time.Millisecond):
		}

		next, err := h.app.RawRuntimeEventStream(r.Context(), workspaceID)
		if err != nil {
			select {
			case <-r.Context().Done():
				return
			case <-time.After(500 * time.Millisecond):
			}
			continue
		}
		current = next
	}
}

type eventProxyFilterState struct {
	userMessageIDs map[string]struct{}
}

func streamEventProxyFrames(ctx context.Context, w http.ResponseWriter, body io.Reader, state *eventProxyFilterState) error {
	flusher, _ := w.(http.Flusher)
	scanner := bufio.NewScanner(body)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	dataLines := make([]string, 0, 1)
	flushFrame := func() error {
		if len(dataLines) == 0 {
			return nil
		}

		payload := strings.Join(dataLines, "\n")
		dataLines = dataLines[:0]
		if shouldSuppressEventProxyPayload(payload, state) {
			return nil
		}

		if _, err := fmt.Fprintf(w, "data: %s\n\n", payload); err != nil {
			return err
		}
		if flusher != nil {
			flusher.Flush()
		}
		return nil
	}

	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		line := scanner.Text()
		if line == "" {
			if err := flushFrame(); err != nil {
				return err
			}
			continue
		}

		if strings.HasPrefix(line, "data:") {
			dataLines = append(dataLines, strings.TrimSpace(strings.TrimPrefix(line, "data:")))
		}
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	return flushFrame()
}

func writeSyntheticEventProxyFrame(w http.ResponseWriter, event string, payload []byte) error {
	if _, err := fmt.Fprintf(w, "event: %s\n", event); err != nil {
		return err
	}
	if _, err := fmt.Fprintf(w, "data: %s\n\n", payload); err != nil {
		return err
	}
	if flusher, ok := w.(http.Flusher); ok {
		flusher.Flush()
	}
	return nil
}

func shouldSuppressEventProxyPayload(payload string, state *eventProxyFilterState) bool {
	var envelope struct {
		Type       string          `json:"type"`
		Properties json.RawMessage `json:"properties"`
	}
	if err := json.Unmarshal([]byte(payload), &envelope); err != nil {
		return false
	}

	switch envelope.Type {
	case "message.updated":
		var message struct {
			Info struct {
				ID   string `json:"id"`
				Role string `json:"role"`
			} `json:"info"`
		}
		if err := json.Unmarshal(envelope.Properties, &message); err != nil {
			return false
		}
		if message.Info.Role == "user" {
			state.userMessageIDs[message.Info.ID] = struct{}{}
			return true
		}
	case "message.part.updated":
		var part struct {
			Part struct {
				MessageID string `json:"messageID"`
			} `json:"part"`
		}
		if err := json.Unmarshal(envelope.Properties, &part); err != nil {
			return false
		}
		_, suppressed := state.userMessageIDs[part.Part.MessageID]
		return suppressed
	case "message.part.delta":
		var delta struct {
			MessageID string `json:"messageID"`
		}
		if err := json.Unmarshal(envelope.Properties, &delta); err != nil {
			return false
		}
		_, suppressed := state.userMessageIDs[delta.MessageID]
		return suppressed
	}

	return false
}
