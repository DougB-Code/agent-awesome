package proxy

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestInjectRuntimePolicyAddsPolicyToTextRun verifies server-side policy injection.
func TestInjectRuntimePolicyAddsPolicyToTextRun(t *testing.T) {
	body := []byte(`{"sessionId":"session-1","newMessage":{"role":"user","parts":[{"text":"remember deployment at 8pm"}]}}`)

	next, changed, err := InjectRuntimePolicy(body)
	if err != nil {
		t.Fatalf("InjectRuntimePolicy() error = %v", err)
	}
	if !changed {
		t.Fatalf("InjectRuntimePolicy() changed = false, want true")
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

// TestInjectRuntimePolicySkipsAlreadyInjectedPolicy verifies idempotent injection.
func TestInjectRuntimePolicySkipsAlreadyInjectedPolicy(t *testing.T) {
	body := []byte(`{"newMessage":{"parts":[{"text":"[[AURORA_RUNTIME_POLICY: already here]]\n\nhello"}]}}`)

	next, changed, err := InjectRuntimePolicy(body)
	if err != nil {
		t.Fatalf("InjectRuntimePolicy() error = %v", err)
	}
	if changed {
		t.Fatalf("InjectRuntimePolicy() changed = true, want false")
	}
	if string(next) != string(body) {
		t.Fatalf("InjectRuntimePolicy() body changed")
	}
}

// TestInjectRuntimePolicyLeavesConfirmationBodiesUntouched verifies non-text runs pass through.
func TestInjectRuntimePolicyLeavesConfirmationBodiesUntouched(t *testing.T) {
	body := []byte(`{"newMessage":{"parts":[{"functionResponse":{"name":"adk_request_confirmation"}}]}}`)

	next, changed, err := InjectRuntimePolicy(body)
	if err != nil {
		t.Fatalf("InjectRuntimePolicy() error = %v", err)
	}
	if changed {
		t.Fatalf("InjectRuntimePolicy() changed = true, want false")
	}
	if string(next) != string(body) {
		t.Fatalf("InjectRuntimePolicy() body changed")
	}
}
