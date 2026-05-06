// This file tests ADK REST client behavior for Slack sessions.
package slack

import (
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
