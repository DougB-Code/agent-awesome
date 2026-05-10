// This file tests ADK REST URL and request body helpers.
package adk

import (
	"encoding/json"
	"testing"
)

// TestSessionURLsEscapePathParts verifies ADK resource identifiers stay path-safe.
func TestSessionURLsEscapePathParts(t *testing.T) {
	sessionsURL := SessionsURL("http://127.0.0.1:8080/api/", "pilot app", "user/one")
	if sessionsURL != "http://127.0.0.1:8080/api/apps/pilot%20app/users/user%2Fone/sessions" {
		t.Fatalf("SessionsURL() = %q, want escaped sessions URL", sessionsURL)
	}
	sessionURL := SessionURL("http://127.0.0.1:8080/api/", "pilot app", "user/one", "slack:1")
	if sessionURL != sessionsURL+"/slack:1" {
		t.Fatalf("SessionURL() = %q, want escaped session URL", sessionURL)
	}
}

// TestRunRequestBodyBuildsNonStreamingTextRun verifies Slack-compatible ADK runs.
func TestRunRequestBodyBuildsNonStreamingTextRun(t *testing.T) {
	body, err := RunRequestBody("app", "user", "session-1", "hello")
	if err != nil {
		t.Fatalf("RunRequestBody() error = %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if decoded["streaming"] != false {
		t.Fatalf("streaming = %#v, want false", decoded["streaming"])
	}
	message := decoded["newMessage"].(map[string]any)
	parts := message["parts"].([]any)
	text := parts[0].(map[string]any)["text"]
	if text != "hello" {
		t.Fatalf("text = %#v, want request text", text)
	}
}

// TestSessionCreateBodyBuildsEmptyState verifies the ADK session bootstrap body.
func TestSessionCreateBodyBuildsEmptyState(t *testing.T) {
	body, err := SessionCreateBody()
	if err != nil {
		t.Fatalf("SessionCreateBody() error = %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	state, ok := decoded["state"].(map[string]any)
	if !ok || len(state) != 0 {
		t.Fatalf("state = %#v, want empty state object", decoded["state"])
	}
}
