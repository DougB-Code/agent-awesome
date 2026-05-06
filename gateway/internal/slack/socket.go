// This file runs Slack Socket Mode for local development.
package slack

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"nhooyr.io/websocket"
)

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
		log.Printf("slack socket disconnected: %v", err)
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
	log.Printf("slack socket connected")
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

// acceptSocketMessage acknowledges and dispatches one Socket Mode envelope.
func (a *Adapter) acceptSocketMessage(ctx context.Context, conn *websocket.Conn, data []byte) error {
	var envelope struct {
		Type       string          `json:"type"`
		EnvelopeID string          `json:"envelope_id"`
		Payload    json.RawMessage `json:"payload"`
		Reason     string          `json:"reason"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return err
	}
	if envelope.EnvelopeID != "" {
		ack, err := json.Marshal(map[string]string{"envelope_id": envelope.EnvelopeID})
		if err != nil {
			return err
		}
		if err := conn.Write(ctx, websocket.MessageText, ack); err != nil {
			return err
		}
	}
	switch envelope.Type {
	case "hello":
		log.Printf("slack socket hello")
		return nil
	case "disconnect":
		return fmt.Errorf("Slack requested disconnect: %s", envelope.Reason)
	case "events_api":
		log.Printf("slack socket events_api envelope received")
		_, err := a.AcceptEnvelope(envelope.Payload)
		return err
	default:
		return nil
	}
}
