// This file tests ADK REST client behavior for Slack sessions.
package slack

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestEnsureSessionCreatesAfterADKMissingSession500 verifies ADK missing-session behavior.
func TestEnsureSessionCreatesAfterADKMissingSession500(t *testing.T) {
	created := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			http.Error(w, "session slack-1 not found", http.StatusInternalServerError)
		case http.MethodPost:
			created = true
			w.WriteHeader(http.StatusOK)
		default:
			t.Fatalf("method = %s, want GET or POST", r.Method)
		}
	}))
	defer server.Close()
	client := NewAgentClient(server.Client(), server.URL, "app", "user")

	if err := client.EnsureSession(t.Context(), "slack-1"); err != nil {
		t.Fatalf("EnsureSession() error = %v", err)
	}
	if !created {
		t.Fatalf("EnsureSession() did not create missing session")
	}
}

// TestRunBodyDisablesModelStreaming verifies Slack never asks non-streaming
// model adapters for streaming responses.
func TestRunBodyDisablesModelStreaming(t *testing.T) {
	client := NewAgentClient(nil, "http://127.0.0.1:8080", "app", "user")

	body, err := client.runBody("slack-1", "hello")
	if err != nil {
		t.Fatalf("runBody() error = %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if got, ok := decoded["streaming"].(bool); !ok || got {
		t.Fatalf("streaming = %#v, want false", decoded["streaming"])
	}
}
