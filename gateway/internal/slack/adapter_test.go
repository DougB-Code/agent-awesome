// This file tests Slack adapter request handling and event filtering.
package slack

import (
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestEventsHandlerRespondsToURLVerification verifies Slack challenge handling.
func TestEventsHandlerRespondsToURLVerification(t *testing.T) {
	adapter := NewAdapter(Config{
		Enabled:        true,
		SigningSecret:  "secret",
		BotToken:       "xoxb-test",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		AppName:        "app",
		AgentUserID:    "user",
	})
	body := []byte(`{"type":"url_verification","challenge":"abc123"}`)
	req := httptest.NewRequest(http.MethodPost, "/slack/events", strings.NewReader(string(body)))
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	req.Header.Set("X-Slack-Request-Timestamp", timestamp)
	req.Header.Set("X-Slack-Signature", SlackSignature("secret", req.Header.Get("X-Slack-Request-Timestamp"), body))
	recorder := httptest.NewRecorder()

	adapter.EventsHandler(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	if strings.TrimSpace(recorder.Body.String()) != "abc123" {
		t.Fatalf("body = %q, want challenge", recorder.Body.String())
	}
}

// TestAcceptedMessageRejectsBotMessages verifies the adapter avoids bot loops.
func TestAcceptedMessageRejectsBotMessages(t *testing.T) {
	adapter := NewAdapter(Config{Enabled: true})
	_, _, ok := adapter.acceptedMessage(EventEnvelope{
		Type:   "event_callback",
		TeamID: "T1",
		Event: MessageEvent{
			Type:    "message",
			Channel: "C1",
			User:    "U1",
			Text:    "hello",
			TS:      "1.0",
			BotID:   "B1",
		},
	})

	if ok {
		t.Fatalf("acceptedMessage() accepted bot message")
	}
}

// TestSessionIDForMessageUsesThreadRoot verifies Slack threads map to one session.
func TestSessionIDForMessageUsesThreadRoot(t *testing.T) {
	root := MessageEvent{Channel: "C1", TS: "1.0", ThreadTS: "0.5"}
	reply := MessageEvent{Channel: "C1", TS: "2.0", ThreadTS: "0.5"}

	if SessionIDForMessage("T1", root) != SessionIDForMessage("T1", reply) {
		t.Fatalf("thread replies mapped to different sessions")
	}
}
