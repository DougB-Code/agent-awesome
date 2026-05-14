// This file tests Slack adapter request handling and event filtering.
package slack

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"agentgateway/internal/adk"
)

// TestEventsHandlerRespondsToURLVerification verifies Slack challenge handling.
func TestEventsHandlerRespondsToURLVerification(t *testing.T) {
	adapter := NewAdapter(Config{
		Enabled:        true,
		SigningSecret:  "secret",
		BotToken:       "xoxb-test",
		GatewayBaseURL: "http://127.0.0.1:1/api",
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

// TestAcceptedMessageEnforcesAllowLists verifies beta Slack scope stays explicit.
func TestAcceptedMessageEnforcesAllowLists(t *testing.T) {
	adapter := NewAdapter(Config{
		Enabled:          true,
		AllowedTeamID:    "T1",
		AllowedUserID:    "U1",
		AllowedChannelID: "C1",
	})
	base := EventEnvelope{
		Type:   "event_callback",
		TeamID: "T1",
		Event: MessageEvent{
			Type:    "message",
			Channel: "C1",
			User:    "U1",
			Text:    "hello",
			TS:      "1.0",
		},
	}
	if _, _, ok := adapter.acceptedMessage(base); !ok {
		t.Fatalf("acceptedMessage() rejected allow-listed event")
	}
	disallowedUser := base
	disallowedUser.Event.User = "U2"
	if _, reason, ok := adapter.acceptedMessage(disallowedUser); ok || !strings.Contains(reason, "user") {
		t.Fatalf("disallowed user ok=%v reason=%q, want user rejection", ok, reason)
	}
	disallowedChannel := base
	disallowedChannel.Event.Channel = "C2"
	if _, reason, ok := adapter.acceptedMessage(disallowedChannel); ok || !strings.Contains(reason, "channel") {
		t.Fatalf("disallowed channel ok=%v reason=%q, want channel rejection", ok, reason)
	}
}

// TestAcceptedMessageMapsProfileBindings verifies Slack scopes select profiles.
func TestAcceptedMessageMapsProfileBindings(t *testing.T) {
	adapter := NewAdapter(Config{
		Enabled: true,
		ProfileBindings: []ProfileBinding{
			{
				ProfileID:      "doug",
				AppName:        "app",
				AgentUserID:    "doug",
				TeamID:         "T1",
				ChannelID:      "C1",
				AllowedUserIDs: []string{"U1"},
			},
			{
				ProfileID:      "family",
				AppName:        "app",
				AgentUserID:    "family",
				TeamID:         "T1",
				ChannelID:      "C2",
				AllowedUserIDs: []string{"U1", "U2"},
			},
		},
	})
	event, _, ok := adapter.acceptedMessage(EventEnvelope{
		Type:   "event_callback",
		TeamID: "T1",
		Event: MessageEvent{
			Type:    "message",
			Channel: "C2",
			User:    "U2",
			Text:    "hello",
			TS:      "1.0",
		},
	})

	if !ok {
		t.Fatalf("acceptedMessage() rejected bound event")
	}
	if event.ProfileID != "family" {
		t.Fatalf("ProfileID = %q, want family", event.ProfileID)
	}

	disallowed := EventEnvelope{
		Type:   "event_callback",
		TeamID: "T1",
		Event: MessageEvent{
			Type:    "message",
			Channel: "C2",
			User:    "U3",
			Text:    "hello",
			TS:      "2.0",
		},
	}
	if _, reason, ok := adapter.acceptedMessage(disallowed); ok || !strings.Contains(reason, "profile") {
		t.Fatalf("disallowed binding ok=%v reason=%q, want profile rejection", ok, reason)
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

// TestAcceptEnvelopeThrottlesConcurrentUserChannelDispatch verifies per-sender limits.
func TestAcceptEnvelopeThrottlesConcurrentUserChannelDispatch(t *testing.T) {
	adapter := NewAdapter(Config{MaxConcurrentDispatches: 2})
	started := make(chan struct{}, 1)
	release := make(chan struct{})
	adapter.dispatchMessage = func(_ context.Context, _ string, _ MessageEvent) {
		started <- struct{}{}
		<-release
	}
	if _, err := adapter.AcceptEnvelope(slackEventBody("EvThrottleFirst", "1.0", "first")); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	<-started
	if _, err := adapter.AcceptEnvelope(slackEventBody("EvThrottleSecond", "2.0", "second")); !errors.Is(err, errSlackDispatchThrottled) {
		t.Fatalf("AcceptEnvelope() second error = %v, want dispatch throttled", err)
	}
	close(release)
}

// TestAcceptEnvelopeDoesNotDeduplicateThrottledAttempt verifies Slack retries can dispatch after capacity frees.
func TestAcceptEnvelopeDoesNotDeduplicateThrottledAttempt(t *testing.T) {
	adapter := NewAdapter(Config{MaxConcurrentDispatches: 2})
	started := make(chan string, 2)
	releaseFirst := make(chan struct{})
	adapter.dispatchMessage = func(_ context.Context, _ string, event MessageEvent) {
		started <- event.TS
		if event.TS == "1.0" {
			<-releaseFirst
		}
	}
	if _, err := adapter.AcceptEnvelope(slackEventBody("EvBusy", "1.0", "first")); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	if ts := waitStartedTS(t, started); ts != "1.0" {
		t.Fatalf("first dispatch TS = %q, want 1.0", ts)
	}
	throttledBody := slackEventBody("EvRetryAfterThrottle", "2.0", "second")
	if _, err := adapter.AcceptEnvelope(throttledBody); !errors.Is(err, errSlackDispatchThrottled) {
		t.Fatalf("AcceptEnvelope() throttled error = %v, want dispatch throttled", err)
	}
	close(releaseFirst)
	waitAcceptedEnvelope(t, adapter, throttledBody)
	if ts := waitStartedTS(t, started); ts != "2.0" {
		t.Fatalf("retry dispatch TS = %q, want 2.0", ts)
	}
}

// TestAcceptEnvelopeThrottlesGlobalConcurrentDispatch verifies fan-out stays bounded.
func TestAcceptEnvelopeThrottlesGlobalConcurrentDispatch(t *testing.T) {
	adapter := NewAdapter(Config{MaxConcurrentDispatches: 1})
	started := make(chan struct{}, 1)
	release := make(chan struct{})
	adapter.dispatchMessage = func(_ context.Context, _ string, _ MessageEvent) {
		started <- struct{}{}
		<-release
	}
	if _, err := adapter.AcceptEnvelope(slackEventBody("EvGlobalFirst", "1.0", "first")); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	<-started
	if _, err := adapter.AcceptEnvelope(slackEventBodyWithSender("EvGlobalSecond", "2.0", "C2", "U2", "second")); !errors.Is(err, errSlackDispatchThrottled) {
		t.Fatalf("AcceptEnvelope() second error = %v, want dispatch throttled", err)
	}
	close(release)
}

// TestDistinctThreadRepliesAcceptedWithoutEventID verifies fallback keys preserve replies.
func TestDistinctThreadRepliesAcceptedWithoutEventID(t *testing.T) {
	adapter, dispatched := newDispatchCaptureAdapter(Config{})

	if _, err := adapter.AcceptEnvelope(slackEventBody("", "1.0", "first")); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	first := waitDispatch(t, dispatched)
	if _, err := adapter.AcceptEnvelope(slackEventBody("", "2.0", "reply")); err != nil {
		t.Fatalf("AcceptEnvelope() reply error = %v", err)
	}

	second := waitDispatch(t, dispatched)
	if first.TS == second.TS {
		t.Fatalf("fallback dedupe collapsed distinct replies: first=%#v second=%#v", first, second)
	}
}

// TestDispatchPostsFailureWithFreshContextAfterAgentTimeout verifies timeout errors still reach Slack.
func TestDispatchPostsFailureWithFreshContextAfterAgentTimeout(t *testing.T) {
	transport := &dispatchFailureTransport{postContextErrors: make(chan error, 1)}
	adapter := NewAdapter(Config{
		BotToken:       "xoxb-test",
		GatewayBaseURL: "http://gateway.test/api",
		AppName:        "app",
		AgentUserID:    "user",
		RequestTimeout: 20 * time.Millisecond,
	})
	adapter.client.Transport = transport

	adapter.dispatch(context.Background(), "T1", MessageEvent{
		Channel: "C1",
		User:    "U1",
		Text:    "hello",
		TS:      "1.0",
	})

	select {
	case err := <-transport.postContextErrors:
		if err != nil {
			t.Fatalf("failure post context error = %v, want fresh active context", err)
		}
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for Slack failure post")
	}
}

// TestNewAdapterRoutesAgentTurnsThroughGateway verifies Slack never targets harness directly.
func TestNewAdapterRoutesAgentTurnsThroughGateway(t *testing.T) {
	adapter := NewAdapter(Config{
		GatewayBaseURL:   "http://gateway.test/api",
		GatewayAuthToken: "secret",
		AppName:          "app",
		AgentUserID:      "user",
	})

	if adapter.agent.baseURL != "http://gateway.test/api" {
		t.Fatalf("agent baseURL = %q, want gateway API URL", adapter.agent.baseURL)
	}
	if adapter.agent.headers["Authorization"] != "Bearer secret" {
		t.Fatalf("Authorization = %q, want gateway bearer", adapter.agent.headers["Authorization"])
	}
}

// TestNewAdapterRoutesLegacySlackThroughDefaultProfile verifies single-channel Slack still selects a gateway profile.
func TestNewAdapterRoutesLegacySlackThroughDefaultProfile(t *testing.T) {
	adapter := NewAdapter(Config{
		GatewayBaseURL:   "http://gateway.test/api",
		GatewayAuthToken: "secret",
		DefaultProfileID: "doug",
		AppName:          "app",
		AgentUserID:      "doug",
	})

	if adapter.agent.headers["X-Agent-Awesome-Profile"] != "doug" {
		t.Fatalf("profile header = %q, want doug", adapter.agent.headers["X-Agent-Awesome-Profile"])
	}
	if !adapter.agent.policy.Enabled() {
		t.Fatalf("Slack runtime policy is disabled")
	}
}

// TestNewAdapterCombinesOperatorAndSlackPolicy verifies channel safety rules.
func TestNewAdapterCombinesOperatorAndSlackPolicy(t *testing.T) {
	adapter := NewAdapter(Config{
		GatewayBaseURL:    "http://gateway.test/api",
		AppName:           "app",
		AgentUserID:       "user",
		RuntimePolicyText: "Use the operator policy.",
	})
	body, err := adapter.agent.runBody("slack-1", "hello")
	if err != nil {
		t.Fatalf("runBody() error = %v", err)
	}

	next, changed, err := adapter.agent.policy.Inject(body)
	if err != nil {
		t.Fatalf("Inject() error = %v", err)
	}
	if !changed {
		t.Fatalf("Inject() changed = false, want true")
	}
	text := string(next)
	if !strings.Contains(text, "Use the operator policy.") || !strings.Contains(text, "Slack can use the configured memory tools") {
		t.Fatalf("policy body = %q, want operator and Slack policy text", text)
	}
}

// TestNewAdapterCreatesProfileAgentClients verifies profile headers reach gateway.
func TestNewAdapterCreatesProfileAgentClients(t *testing.T) {
	adapter := NewAdapter(Config{
		GatewayBaseURL:   "http://gateway.test/api",
		GatewayAuthToken: "secret",
		ProfileBindings: []ProfileBinding{
			{
				ProfileID:      "family",
				AppName:        "app",
				AgentUserID:    "family",
				TeamID:         "T1",
				ChannelID:      "C1",
				AllowedUserIDs: []string{"U1"},
			},
		},
	})

	agent := adapter.agentForEvent(MessageEvent{ProfileID: "family"})
	if agent == nil {
		t.Fatalf("agentForEvent() = nil, want profile agent")
	}
	if agent.headers["Authorization"] != "Bearer secret" {
		t.Fatalf("Authorization = %q, want gateway bearer", agent.headers["Authorization"])
	}
	if agent.headers["X-Agent-Awesome-Profile"] != "family" {
		t.Fatalf("profile header = %q, want family", agent.headers["X-Agent-Awesome-Profile"])
	}
	if agent.userID != "family" {
		t.Fatalf("agent user = %q, want family", agent.userID)
	}
	if !agent.policy.Enabled() {
		t.Fatalf("profile Slack runtime policy is disabled")
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
	return slackEventBodyWithSender(eventID, ts, "C1", "U1", text)
}

// slackEventBodyWithSender builds one Slack message callback for a sender.
func slackEventBodyWithSender(eventID string, ts string, channel string, user string, text string) []byte {
	eventIDField := ""
	if eventID != "" {
		eventIDField = fmt.Sprintf(`,"event_id":%q`, eventID)
	}
	return []byte(fmt.Sprintf(`{"type":"event_callback","team_id":"T1"%s,"event":{"type":"message","channel":%q,"user":%q,"text":%q,"ts":%q}}`, eventIDField, channel, user, text, ts))
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

// waitAcceptedEnvelope retries admission until the active dispatch releases.
func waitAcceptedEnvelope(t *testing.T, adapter *Adapter, body []byte) {
	t.Helper()
	deadline := time.After(time.Second)
	for {
		if _, err := adapter.AcceptEnvelope(body); err == nil {
			return
		} else if !errors.Is(err, errSlackDispatchThrottled) {
			t.Fatalf("AcceptEnvelope() retry error = %v, want nil or throttled", err)
		}
		select {
		case <-deadline:
			t.Fatalf("timed out waiting for Slack retry admission")
		case <-time.After(10 * time.Millisecond):
		}
	}
}

// waitStartedTS returns the next dispatch timestamp from a blocking test double.
func waitStartedTS(t *testing.T, started <-chan string) string {
	t.Helper()
	select {
	case ts := <-started:
		return ts
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for Slack dispatch start")
		return ""
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

// dispatchFailureTransport simulates an agent timeout and records Slack failure posts.
type dispatchFailureTransport struct {
	postContextErrors chan error
}

// RoundTrip responds to agent session checks, times out runs, and records Slack posts.
func (t *dispatchFailureTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	switch req.URL.Host {
	case "gateway.test":
		if req.URL.Path == "/api"+adk.RunSSEPath() {
			<-req.Context().Done()
			return nil, req.Context().Err()
		}
		return testHTTPResponse(http.StatusOK, `{}`), nil
	case "slack.com":
		t.postContextErrors <- req.Context().Err()
		return testHTTPResponse(http.StatusOK, `{"ok":true}`), nil
	default:
		return testHTTPResponse(http.StatusNotFound, `{"ok":false}`), nil
	}
}

// testHTTPResponse creates a minimal HTTP response for fake transports.
func testHTTPResponse(status int, body string) *http.Response {
	return &http.Response{
		StatusCode: status,
		Header:     make(http.Header),
		Body:       io.NopCloser(strings.NewReader(body)),
	}
}
