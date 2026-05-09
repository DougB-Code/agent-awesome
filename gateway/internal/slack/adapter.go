// This file coordinates Slack events, agent turns, and Slack replies.
package slack

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/rs/zerolog/log"

	"agentgateway/internal/policy"
)

const maxSlackRequestBytes = 1 << 20

// Adapter owns the Slack channel behavior for one gateway process.
type Adapter struct {
	config          Config
	slack           *WebAPI
	agent           *AgentClient
	client          *http.Client
	deduper         *eventDeduper
	dispatchMessage func(context.Context, string, MessageEvent)
}

// NewAdapter creates a Slack adapter from gateway runtime settings.
func NewAdapter(config Config) *Adapter {
	timeout := 10 * time.Minute
	if config.RequestTimeout > 0 {
		timeout = config.RequestTimeout
	}
	client := &http.Client{Timeout: timeout}
	adapter := &Adapter{
		config: config,
		slack:  NewWebAPI(client, config.BotToken, config.AppToken),
		agent: NewAgentClientWithPolicy(
			client,
			config.HarnessBaseURL,
			config.AppName,
			config.AgentUserID,
			policy.NewInjector(policy.Config{Text: config.RuntimePolicyText}),
		),
		client:  client,
		deduper: newEventDeduper(config.EventDedupTTL),
	}
	adapter.dispatchMessage = adapter.dispatch
	return adapter
}

// Enabled reports whether Slack channel handling is configured.
func (a *Adapter) Enabled() bool {
	return a != nil && a.config.Enabled
}

// SocketModeEnabled reports whether local Slack Socket Mode should run.
func (a *Adapter) SocketModeEnabled() bool {
	return a.Enabled() && a.config.SocketMode
}

// EventsHandler receives Slack HTTP Events API requests.
func (a *Adapter) EventsHandler(w http.ResponseWriter, r *http.Request) {
	if !a.Enabled() || a.config.SigningSecret == "" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxSlackRequestBytes))
	if err != nil {
		log.Error().Err(err).Msg("slack request read failed")
		http.Error(w, "read Slack request", http.StatusBadRequest)
		return
	}
	if err := VerifySignature(a.config.SigningSecret, r.Header, body, time.Now()); err != nil {
		log.Warn().Err(err).Msg("slack signature rejected by gateway")
		http.Error(w, "invalid Slack signature", http.StatusUnauthorized)
		return
	}
	challenge, err := a.AcceptEnvelopeWithDelivery(body, deliveryInfoFromHeaders(r.Header))
	if err != nil {
		log.Warn().Err(err).Msg("slack envelope rejected by gateway")
		http.Error(w, "invalid Slack event", http.StatusBadRequest)
		return
	}
	if challenge != "" {
		w.Header().Set("Content-Type", "text/plain")
		_, _ = w.Write([]byte(challenge))
		return
	}
	w.WriteHeader(http.StatusOK)
}

// AcceptEnvelope validates and dispatches one Slack Events API envelope.
func (a *Adapter) AcceptEnvelope(body []byte) (string, error) {
	return a.AcceptEnvelopeWithDelivery(body, DeliveryInfo{})
}

// AcceptEnvelopeWithDelivery validates and dispatches one Slack delivery attempt.
func (a *Adapter) AcceptEnvelopeWithDelivery(body []byte, delivery DeliveryInfo) (string, error) {
	var envelope EventEnvelope
	if err := json.Unmarshal(body, &envelope); err != nil {
		return "", err
	}
	switch envelope.Type {
	case "url_verification":
		log.Info().Msg("slack url verification received")
		return envelope.Challenge, nil
	case "event_callback":
		log.Info().
			Str("type", envelope.Event.Type).
			Str("subtype", envelope.Event.Subtype).
			Str("channel", envelope.Event.Channel).
			Str("user", envelope.Event.User).
			Str("event_id", envelope.EventID).
			Str("retry_num", delivery.RetryNum).
			Str("retry_reason", delivery.RetryReason).
			Bool("bot", envelope.Event.BotID != "").
			Msg("slack event callback received")
		event, reason, ok := a.acceptedMessage(envelope)
		if !ok {
			log.Info().Str("reason", reason).Msg("slack event ignored")
			return "", nil
		}
		dedupeKey := eventDedupKey(envelope)
		if !a.deduper.accept(dedupeKey) {
			log.Info().
				Str("event_id", envelope.EventID).
				Str("dedupe_key", dedupeKey).
				Str("retry_num", delivery.RetryNum).
				Str("retry_reason", delivery.RetryReason).
				Msg("slack duplicate event ignored")
			return "", nil
		}
		dispatch := a.dispatchMessage
		if dispatch == nil {
			dispatch = a.dispatch
		}
		go dispatch(context.Background(), envelope.TeamID, event)
		return "", nil
	default:
		return "", nil
	}
}

// deliveryInfoFromHeaders extracts Slack retry headers from HTTP requests.
func deliveryInfoFromHeaders(headers http.Header) DeliveryInfo {
	return DeliveryInfo{
		RetryNum:    headers.Get("X-Slack-Retry-Num"),
		RetryReason: headers.Get("X-Slack-Retry-Reason"),
	}
}

// eventDedupKey returns the strongest available duplicate-detection key.
func eventDedupKey(envelope EventEnvelope) string {
	if strings.TrimSpace(envelope.EventID) != "" {
		return "event_id:" + strings.TrimSpace(envelope.EventID)
	}
	event := envelope.Event
	return "fallback:" + envelope.TeamID + ":" + event.Channel + ":" + event.User + ":" + event.TS
}

// acceptedMessage filters Slack events to the configured personal pilot scope.
func (a *Adapter) acceptedMessage(envelope EventEnvelope) (MessageEvent, string, bool) {
	event := envelope.Event
	if event.Type != "message" && event.Type != "app_mention" {
		return MessageEvent{}, "event type is not message or app_mention", false
	}
	if event.Subtype != "" {
		return MessageEvent{}, "message subtype is not supported", false
	}
	if event.BotID != "" {
		return MessageEvent{}, "message came from a bot", false
	}
	if strings.TrimSpace(event.Text) == "" || event.Channel == "" || event.User == "" || event.TS == "" {
		return MessageEvent{}, "message is missing required text, channel, user, or timestamp", false
	}
	if a.config.AllowedTeamID != "" && envelope.TeamID != a.config.AllowedTeamID {
		return MessageEvent{}, "team is not allow-listed", false
	}
	if a.config.AllowedUserID != "" && event.User != a.config.AllowedUserID {
		return MessageEvent{}, "user is not allow-listed", false
	}
	if a.config.AllowedChannelID != "" && event.Channel != a.config.AllowedChannelID {
		return MessageEvent{}, "channel is not allow-listed", false
	}
	return event, "", true
}

// dispatch runs the agent for one Slack message and posts a threaded reply.
func (a *Adapter) dispatch(parent context.Context, teamID string, event MessageEvent) {
	ctx, cancel := context.WithTimeout(parent, a.client.Timeout)
	defer cancel()
	sessionID := SessionIDForMessage(teamID, event)
	threadTS := ReplyThreadTS(event)
	log.Info().
		Str("channel", event.Channel).
		Str("thread", threadTS).
		Str("session", sessionID).
		Msg("slack dispatch start")
	if err := a.agent.EnsureSession(ctx, sessionID); err != nil {
		log.Error().Err(err).Msg("slack ensure session")
		a.postFailure(ctx, event)
		return
	}
	reply, err := a.agent.RunText(ctx, sessionID, event.Text)
	if err != nil {
		log.Error().Err(err).Msg("slack run agent")
		a.postFailure(ctx, event)
		return
	}
	if reply == "" {
		reply = "Done."
	}
	if err := a.slack.PostMessage(ctx, event.Channel, ReplyThreadTS(event), reply); err != nil {
		log.Error().Err(err).Msg("slack post reply")
		return
	}
	log.Info().
		Str("channel", event.Channel).
		Str("thread", threadTS).
		Str("session", sessionID).
		Msg("slack dispatch complete")
}

// postFailure posts a generic Slack failure without exposing internal details.
func (a *Adapter) postFailure(ctx context.Context, event MessageEvent) {
	if err := a.slack.PostMessage(ctx, event.Channel, ReplyThreadTS(event), "I hit an error running the agent. Check the gateway logs for details."); err != nil {
		log.Error().Err(err).Msg("slack post failure")
	}
}

// SessionIDForMessage returns a stable ADK session id for one Slack thread.
func SessionIDForMessage(teamID string, event MessageEvent) string {
	root := ReplyThreadTS(event)
	sum := sha256.Sum256([]byte(fmt.Sprintf("%s:%s:%s", teamID, event.Channel, root)))
	return "slack-" + hex.EncodeToString(sum[:])[:24]
}

// ReplyThreadTS returns the Slack thread root for replies and session grouping.
func ReplyThreadTS(event MessageEvent) string {
	if event.ThreadTS != "" {
		return event.ThreadTS
	}
	return event.TS
}
