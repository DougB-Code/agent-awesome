// This file runs Slack Socket Mode for local development.
package slack

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/rs/zerolog/log"
	"nhooyr.io/websocket"
)

// socketEnvelope is the Slack Socket Mode wrapper around Events API payloads.
type socketEnvelope struct {
	Type       string          `json:"type"`
	EnvelopeID string          `json:"envelope_id"`
	Payload    json.RawMessage `json:"payload"`
	Reason     string          `json:"reason"`
}

// socketAck describes an acknowledgement that should be written to Slack.
type socketAck struct {
	EnvelopeID string
	Required   bool
}

// RunSocketMode connects to Slack and receives Events API envelopes over WebSocket.
func (a *Adapter) RunSocketMode(ctx context.Context) error {
	if !a.SocketModeEnabled() {
		return nil
	}
	backoff := time.Second
	for {
		err := a.runSocketOnce(ctx)
		if ctx.Err() != nil {
			return ctx.Err()
		}
		log.Error().Err(err).Msg("slack socket disconnected")
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(backoff):
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
}

// runSocketOnce holds one Slack Socket Mode connection until it closes.
func (a *Adapter) runSocketOnce(ctx context.Context) error {
	socketURL, err := a.slack.OpenSocketURL(ctx)
	if err != nil {
		return err
	}
	conn, _, err := websocket.Dial(ctx, socketURL, nil)
	if err != nil {
		return err
	}
	defer conn.Close(websocket.StatusNormalClosure, "agent gateway shutting down")
	log.Info().Msg("slack socket connected")
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return err
		}
		if err := a.acceptSocketMessage(ctx, conn, data); err != nil {
			return err
		}
	}
}

// acceptSocketMessage dispatches one Socket Mode envelope and acknowledges it.
func (a *Adapter) acceptSocketMessage(ctx context.Context, conn *websocket.Conn, data []byte) error {
	ack, err := a.processSocketEnvelope(data)
	if err != nil {
		return err
	}
	if !ack.Required {
		return nil
	}
	return writeSocketAck(ctx, conn, ack.EnvelopeID)
}

// processSocketEnvelope validates dispatch admission before requiring an ack.
func (a *Adapter) processSocketEnvelope(data []byte) (socketAck, error) {
	var envelope socketEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		return socketAck{}, err
	}
	switch envelope.Type {
	case "hello":
		log.Info().Msg("slack socket hello")
		return socketAck{}, nil
	case "disconnect":
		return socketAck{}, fmt.Errorf("Slack requested disconnect: %s", envelope.Reason)
	case "events_api":
		log.Info().Msg("slack socket events_api envelope received")
		if _, err := a.AcceptEnvelope(envelope.Payload); err != nil {
			return socketAck{}, err
		}
		return socketAckFor(envelope.EnvelopeID), nil
	default:
		return socketAckFor(envelope.EnvelopeID), nil
	}
}

// socketAckFor returns a Socket Mode ack descriptor for non-empty ids.
func socketAckFor(envelopeID string) socketAck {
	return socketAck{EnvelopeID: envelopeID, Required: envelopeID != ""}
}

// writeSocketAck sends one Socket Mode acknowledgement to Slack.
func writeSocketAck(ctx context.Context, conn *websocket.Conn, envelopeID string) error {
	ack, err := json.Marshal(map[string]string{"envelope_id": envelopeID})
	if err != nil {
		return err
	}
	return conn.Write(ctx, websocket.MessageText, ack)
}
