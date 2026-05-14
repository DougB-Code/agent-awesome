// This file tests ADK REST client behavior for Slack sessions.
package slack

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"agentgateway/internal/adk"
	"agentgateway/internal/policy"
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

// TestRunTextInjectsConfiguredRuntimePolicy verifies Slack uses gateway policy behavior.
func TestRunTextInjectsConfiguredRuntimePolicy(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != adk.RunSSEPath() {
			t.Fatalf("path = %q, want /run_sse", r.URL.Path)
		}
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode run body: %v", err)
		}
		message := decoded["newMessage"].(map[string]any)
		parts := message["parts"].([]any)
		text := parts[0].(map[string]any)["text"].(string)
		if !strings.HasPrefix(text, policy.RuntimePolicyPrefix) || !strings.Contains(text, "Configured Slack policy.") {
			t.Fatalf("text = %q, want configured runtime policy", text)
		}
		if strings.Contains(text, "idempotency_key") {
			t.Fatalf("text = %q, want no model-facing idempotency instructions", text)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"author\":\"assistant\",\"content\":{\"parts\":[{\"text\":\"ok\"}]}}\n\n"))
	}))
	defer server.Close()
	client := NewAgentClientWithPolicy(
		server.Client(),
		server.URL,
		"app",
		"user",
		policy.NewInjector(policy.Config{Text: "Configured Slack policy."}),
	)

	reply, err := client.RunText(context.Background(), "slack-1", "hello")
	if err != nil {
		t.Fatalf("RunText() error = %v", err)
	}
	if reply != "ok" {
		t.Fatalf("reply = %q, want ok", reply)
	}
}

// TestRunTextRetriesGatewayDependencyReadiness verifies Slack waits through cold start.
func TestRunTextRetriesGatewayDependencyReadiness(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		attempts++
		if attempts == 1 {
			http.Error(w, `{"error":"memory domain dependency not ready"}`, http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"author\":\"assistant\",\"content\":{\"parts\":[{\"text\":\"ready\"}]}}\n\n"))
	}))
	defer server.Close()
	client := NewAgentClient(server.Client(), server.URL, "app", "user")

	reply, err := client.RunText(t.Context(), "slack-1", "hello")
	if err != nil {
		t.Fatalf("RunText() error = %v", err)
	}
	if reply != "ready" {
		t.Fatalf("reply = %q, want ready", reply)
	}
	if attempts != 2 {
		t.Fatalf("attempts = %d, want one readiness retry", attempts)
	}
}

// TestDecodeAgentEventSuppressesLocalToolMarkup keeps leaked tool tokens out of Slack.
func TestDecodeAgentEventSuppressesLocalToolMarkup(t *testing.T) {
	text, err := decodeAgentEvent("message", `{"author":"assistant","content":{"parts":[{"text":"<|tool_call>call:tool_call{create_task{title:<|\"|>Buy Milk<|\"|>}}<tool_call|>"}]}}`)
	if err != nil {
		t.Fatalf("decodeAgentEvent() error = %v", err)
	}
	if text != "" {
		t.Fatalf("decodeAgentEvent() = %q, want empty text", text)
	}
}

// TestDecodeAgentEventRejectsConfirmationRequest verifies Slack does not report paused writes as success.
func TestDecodeAgentEventRejectsConfirmationRequest(t *testing.T) {
	_, err := decodeAgentEvent("message", `{"author":"assistant","content":{"parts":[{"functionCall":{"id":"confirm-1","name":"adk_request_confirmation","args":{"originalFunctionCall":{"id":"call-1","name":"create_task"},"toolConfirmation":{"hint":"Approve task write?"}}}}]}}`)
	if !errors.Is(err, errSlackConfirmationUnsupported) {
		t.Fatalf("decodeAgentEvent() error = %v, want unsupported confirmation", err)
	}
	if !strings.Contains(err.Error(), "create_task") {
		t.Fatalf("decodeAgentEvent() error = %v, want original tool name", err)
	}
}
