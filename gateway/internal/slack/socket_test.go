// This file tests Slack Socket Mode envelope admission behavior.
package slack

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

// TestProcessSocketEnvelopeAcksEventsAfterAdmission verifies Events API payloads ack only after dispatch.
func TestProcessSocketEnvelopeAcksEventsAfterAdmission(t *testing.T) {
	adapter, dispatched := newDispatchCaptureAdapter(Config{})
	ack, err := adapter.processSocketEnvelope(socketEventBody("socket-1", slackEventBody("EvSocket", "1.0", "hello")))
	if err != nil {
		t.Fatalf("processSocketEnvelope() error = %v", err)
	}
	if !ack.Required || ack.EnvelopeID != "socket-1" {
		t.Fatalf("ack = %#v, want required socket-1", ack)
	}
	event := waitDispatch(t, dispatched)
	if event.TS != "1.0" {
		t.Fatalf("dispatch TS = %q, want 1.0", event.TS)
	}
}

// TestProcessSocketEnvelopeLeavesThrottledEventsUnacked verifies Slack can retry throttled socket deliveries.
func TestProcessSocketEnvelopeLeavesThrottledEventsUnacked(t *testing.T) {
	adapter := NewAdapter(Config{MaxConcurrentDispatches: 2})
	started := make(chan struct{}, 1)
	release := make(chan struct{})
	adapter.dispatchMessage = func(_ context.Context, _ string, _ MessageEvent) {
		started <- struct{}{}
		<-release
	}
	if _, err := adapter.AcceptEnvelope(slackEventBody("EvSocketBusy", "1.0", "first")); err != nil {
		t.Fatalf("AcceptEnvelope() first error = %v", err)
	}
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for first dispatch")
	}
	ack, err := adapter.processSocketEnvelope(socketEventBody("socket-2", slackEventBody("EvSocketRetry", "2.0", "second")))
	if !errors.Is(err, errSlackDispatchThrottled) {
		t.Fatalf("processSocketEnvelope() error = %v, want dispatch throttled", err)
	}
	if ack.Required {
		t.Fatalf("ack = %#v, want no ack for throttled event", ack)
	}
	close(release)
}

// socketEventBody builds one Socket Mode envelope around an Events API payload.
func socketEventBody(envelopeID string, payload []byte) []byte {
	return []byte(fmt.Sprintf(`{"type":"events_api","envelope_id":%q,"payload":%s}`, envelopeID, payload))
}
