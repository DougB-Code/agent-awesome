// This file tests Slack HTTP request signature verification.
package slack

import (
	"net/http"
	"testing"
	"time"
)

// TestVerifySignatureAcceptsCanonicalSlackSignature verifies valid HMAC input.
func TestVerifySignatureAcceptsCanonicalSlackSignature(t *testing.T) {
	body := []byte(`{"type":"event_callback"}`)
	now := time.Unix(12345, 0)
	header := http.Header{}
	header.Set("X-Slack-Request-Timestamp", "12345")
	header.Set("X-Slack-Signature", SlackSignature("secret", "12345", body))

	if err := VerifySignature("secret", header, body, now); err != nil {
		t.Fatalf("VerifySignature() error = %v", err)
	}
}

// TestVerifySignatureRejectsStaleTimestamp verifies replay protection.
func TestVerifySignatureRejectsStaleTimestamp(t *testing.T) {
	body := []byte(`{"type":"event_callback"}`)
	header := http.Header{}
	header.Set("X-Slack-Request-Timestamp", "12345")
	header.Set("X-Slack-Signature", SlackSignature("secret", "12345", body))

	if err := VerifySignature("secret", header, body, time.Unix(12345, 0).Add(6*time.Minute)); err == nil {
		t.Fatalf("VerifySignature() error = nil, want stale timestamp")
	}
}
