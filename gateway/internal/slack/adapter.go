// This file coordinates Slack events, agent turns, and Slack replies.
package slack

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"
)

const maxSlackRequestBytes = 1 << 20

// Adapter owns the Slack channel behavior for one gateway process.
type Adapter struct {
	config Config
	slack  *WebAPI
	agent  *AgentClient
	client *http.Client
}

// NewAdapter creates a Slack adapter from gateway runtime settings.
func NewAdapter(config Config) *Adapter {
	timeout := 10 * time.Minute
	if config.RequestTimeout > 0 {
		timeout = config.RequestTimeout
	}
	client := &http.Client{Timeout: timeout}
	return &Adapter{
		config: config,
		slack:  NewWebAPI(client, config.BotToken, config.AppToken),
		agent:  NewAgentClient(client, config.HarnessBaseURL, config.AppName, config.AgentUserID),
		client: client,
	}
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
		http.Error(w, "read Slack request", http.StatusBadRequest)
		return
	}
	if err := VerifySignature(a.config.SigningSecret, r.Header, body, time.Now()); err != nil {
		http.Error(w, "invalid Slack signature", http.StatusUnauthorized)
		return
	}
	challenge, err := a.AcceptEnvelope(body)
	if err != nil {
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
	var envelope EventEnvelope
	if err := json.Unmarshal(body, &envelope); err != nil {
		return "", err
	}
	switch envelope.Type {
	case "url_verification":
		log.Printf("slack url verification received")
		return envelope.Challenge, nil
	case "event_callback":
		log.Printf(
			"slack event callback type=%s subtype=%s channel=%s user=%s bot=%t",
			envelope.Event.Type,
			envelope.Event.Subtype,
			envelope.Event.Channel,
			envelope.Event.User,
			envelope.Event.BotID != "",
		)
		event, reason, ok := a.acceptedMessage(envelope)
		if !ok {
			log.Printf("slack event ignored: %s", reason)
			return "", nil
		}
		go a.dispatch(context.Background(), envelope.TeamID, event)
		return "", nil
	default:
		return "", nil
	}
}

// acceptedMessage filters Slack events to the configured personal pilot scope.
func (a *Adapter) acceptedMessage(envelope EventEnvelope) (MessageEvent, string, bool) {
	event := envelope.Event
	if event.Type != "message" {
		return MessageEvent{}, "event type is not message", false
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
	log.Printf("slack dispatch start channel=%s thread=%s session=%s", event.Channel, ReplyThreadTS(event), sessionID)
	if err := a.agent.EnsureSession(ctx, sessionID); err != nil {
		log.Printf("slack ensure session: %v", err)
		a.postFailure(ctx, event)
		return
	}
	reply, err := a.agent.RunText(ctx, sessionID, event.Text)
	if err != nil {
		log.Printf("slack run agent: %v", err)
		a.postFailure(ctx, event)
		return
	}
	if reply == "" {
		reply = "Done."
	}
	if err := a.slack.PostMessage(ctx, event.Channel, ReplyThreadTS(event), reply); err != nil {
		log.Printf("slack post reply: %v", err)
		return
	}
	log.Printf("slack dispatch complete channel=%s thread=%s session=%s", event.Channel, ReplyThreadTS(event), sessionID)
}

// postFailure posts a generic Slack failure without exposing internal details.
func (a *Adapter) postFailure(ctx context.Context, event MessageEvent) {
	if err := a.slack.PostMessage(ctx, event.Channel, ReplyThreadTS(event), "I hit an error running the agent. Check the gateway logs for details."); err != nil {
		log.Printf("slack post failure: %v", err)
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
