// This file tests runtime policy injection behavior.
package policy

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestInjectAddsPolicyToTextRun verifies configured policy injection.
func TestInjectAddsPolicyToTextRun(t *testing.T) {
	injector := NewInjector(Config{Text: DefaultRuntimePolicyText})
	body := []byte(`{"sessionId":"session-1","newMessage":{"role":"user","parts":[{"text":"remember deployment at 8pm"}]}}`)

	next, changed, err := injector.Inject(body)
	if err != nil {
		t.Fatalf("Inject() error = %v", err)
	}
	if !changed {
		t.Fatalf("Inject() changed = false, want true")
	}
	var decoded map[string]any
	if err := json.Unmarshal(next, &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	message := decoded["newMessage"].(map[string]any)
	parts := message["parts"].([]any)
	part := parts[0].(map[string]any)
	text := part["text"].(string)
	if !strings.HasPrefix(text, RuntimePolicyPrefix) {
		t.Fatalf("text = %q, want runtime policy prefix", text)
	}
	if !strings.Contains(text, "agent_gateway:session-1:") {
		t.Fatalf("text = %q, want gateway idempotency prefix", text)
	}
}

// TestInjectUsesConfiguredPolicyText verifies policy text comes from config.
func TestInjectUsesConfiguredPolicyText(t *testing.T) {
	injector := NewInjector(Config{Text: "Use the configured policy only."})
	body := []byte(`{"newMessage":{"parts":[{"text":"hello"}]}}`)

	next, changed, err := injector.Inject(body)
	if err != nil {
		t.Fatalf("Inject() error = %v", err)
	}
	if !changed {
		t.Fatalf("Inject() changed = false, want true")
	}
	if text := string(next); !strings.Contains(text, "Use the configured policy only.") {
		t.Fatalf("body = %q, want configured policy text", text)
	}
}

// TestInjectSkipsAlreadyInjectedPolicy verifies idempotent injection.
func TestInjectSkipsAlreadyInjectedPolicy(t *testing.T) {
	injector := NewInjector(Config{Text: DefaultRuntimePolicyText})
	body := []byte(`{"newMessage":{"parts":[{"text":"[[AGENT_AWESOME_RUNTIME_POLICY: already here]]\n\nhello"}]}}`)

	next, changed, err := injector.Inject(body)
	if err != nil {
		t.Fatalf("Inject() error = %v", err)
	}
	if changed {
		t.Fatalf("Inject() changed = true, want false")
	}
	if string(next) != string(body) {
		t.Fatalf("Inject() body changed")
	}
}

// TestInjectLeavesConfirmationBodiesUntouched verifies non-text runs pass through.
func TestInjectLeavesConfirmationBodiesUntouched(t *testing.T) {
	injector := NewInjector(Config{Text: DefaultRuntimePolicyText})
	body := []byte(`{"newMessage":{"parts":[{"functionResponse":{"name":"adk_request_confirmation"}}]}}`)

	next, changed, err := injector.Inject(body)
	if err != nil {
		t.Fatalf("Inject() error = %v", err)
	}
	if changed {
		t.Fatalf("Inject() changed = true, want false")
	}
	if string(next) != string(body) {
		t.Fatalf("Inject() body changed")
	}
}

// TestInjectDisabledWithoutPolicyText verifies empty policy config is inert.
func TestInjectDisabledWithoutPolicyText(t *testing.T) {
	injector := NewInjector(Config{})
	body := []byte(`{"newMessage":{"parts":[{"text":"hello"}]}}`)

	next, changed, err := injector.Inject(body)
	if err != nil {
		t.Fatalf("Inject() error = %v", err)
	}
	if changed {
		t.Fatalf("Inject() changed = true, want false")
	}
	if string(next) != string(body) {
		t.Fatalf("Inject() body changed")
	}
}
