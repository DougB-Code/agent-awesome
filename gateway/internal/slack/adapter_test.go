// This file tests Slack adapter request handling and event filtering.
package slack

import (
	"context"
	"fmt"
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

// TestAcceptedMessageAcceptsAppMentions verifies channel mentions can dispatch to the agent.
func TestAcceptedMessageAcceptsAppMentions(t *testing.T) {
	adapter := NewAdapter(Config{Enabled: true})
	event, _, ok := adapter.acceptedMessage(EventEnvelope{
		Type:   "event_callback",
		TeamID: "T1",
		Event: MessageEvent{
			Type:    "app_mention",
			Channel: "C1",
			User:    "U1",
			Text:    "<@B1> hello",
			TS:      "1.0",
		},
	})

	if !ok {
		t.Fatalf("acceptedMessage() rejected app_mention")
	}
	if event.Type != "app_mention" {
		t.Fatalf("event type = %q, want app_mention", event.Type)
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

// TestAcceptEnvelopeIgnoresDuplicateEventID verifies duplicate deliveries do not dispatch twice.
func TestAcceptEnvelopeIgnoresDuplicateEventID(t *testing.T) {
	adapter, dispatched := newDispatchCaptureAdapter(Config{})
	body := slackEventBody("EvDuplicate", "1.0", "hello")

	if _, err := adapter.AcceptEnvelope(body); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	if _, err := adapter.AcceptEnvelope(body); err != nil {
		t.Fatalf("AcceptEnvelope() duplicate error = %v", err)
	}

	event := waitDispatch(t, dispatched)
	if event.TS != "1.0" {
		t.Fatalf("dispatch TS = %q, want first event", event.TS)
	}
	assertNoDispatch(t, dispatched)
}

// TestEventsHandlerIgnoresRetryAfterFirstAcceptance verifies retry headers are deduped.
func TestEventsHandlerIgnoresRetryAfterFirstAcceptance(t *testing.T) {
	adapter, dispatched := newDispatchCaptureAdapter(Config{
		Enabled:       true,
		SigningSecret: "secret",
	})
	body := slackEventBody("EvRetry", "1.0", "hello")

	first := postSlackEvent(t, adapter, body, "", "")
	if first.Code != http.StatusOK {
		t.Fatalf("first status = %d, want 200", first.Code)
	}
	waitDispatch(t, dispatched)

	second := postSlackEvent(t, adapter, body, "1", "http_timeout")
	if second.Code != http.StatusOK {
		t.Fatalf("retry status = %d, want 200", second.Code)
	}
	assertNoDispatch(t, dispatched)
}

// TestDistinctThreadRepliesAcceptedWithoutEventID verifies fallback keys preserve replies.
func TestDistinctThreadRepliesAcceptedWithoutEventID(t *testing.T) {
	adapter, dispatched := newDispatchCaptureAdapter(Config{})

	if _, err := adapter.AcceptEnvelope(slackEventBody("", "1.0", "first")); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	if _, err := adapter.AcceptEnvelope(slackEventBody("", "2.0", "reply")); err != nil {
		t.Fatalf("AcceptEnvelope() reply error = %v", err)
	}

	first := waitDispatch(t, dispatched)
	second := waitDispatch(t, dispatched)
	if first.TS == second.TS {
		t.Fatalf("fallback dedupe collapsed distinct replies: first=%#v second=%#v", first, second)
	}
}

// newDispatchCaptureAdapter creates an adapter whose dispatches are test-visible.
func newDispatchCaptureAdapter(config Config) (*Adapter, <-chan MessageEvent) {
	adapter := NewAdapter(config)
	dispatched := make(chan MessageEvent, 4)
	adapter.dispatchMessage = func(_ context.Context, _ string, event MessageEvent) {
		dispatched <- event
	}
	return adapter, dispatched
}

// slackEventBody builds one Slack Events API message callback body.
func slackEventBody(eventID string, ts string, text string) []byte {
	eventIDField := ""
	if eventID != "" {
		eventIDField = fmt.Sprintf(`,"event_id":%q`, eventID)
	}
	return []byte(fmt.Sprintf(`{"type":"event_callback","team_id":"T1"%s,"event":{"type":"message","channel":"C1","user":"U1","text":%q,"ts":%q}}`, eventIDField, text, ts))
}

// postSlackEvent sends one signed Slack HTTP delivery to the adapter.
func postSlackEvent(t *testing.T, adapter *Adapter, body []byte, retryNum string, retryReason string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/slack/events", strings.NewReader(string(body)))
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	req.Header.Set("X-Slack-Request-Timestamp", timestamp)
	req.Header.Set("X-Slack-Signature", SlackSignature("secret", timestamp, body))
	if retryNum != "" {
		req.Header.Set("X-Slack-Retry-Num", retryNum)
		req.Header.Set("X-Slack-Retry-Reason", retryReason)
	}
	recorder := httptest.NewRecorder()
	adapter.EventsHandler(recorder, req)
	return recorder
}

// waitDispatch returns the next dispatched Slack event.
func waitDispatch(t *testing.T, dispatched <-chan MessageEvent) MessageEvent {
	t.Helper()
	select {
	case event := <-dispatched:
		return event
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for Slack dispatch")
		return MessageEvent{}
	}
}

// assertNoDispatch verifies no additional event was dispatched.
func assertNoDispatch(t *testing.T, dispatched <-chan MessageEvent) {
	t.Helper()
	select {
	case event := <-dispatched:
		t.Fatalf("unexpected Slack dispatch: %#v", event)
	case <-time.After(50 * time.Millisecond):
	}
}
