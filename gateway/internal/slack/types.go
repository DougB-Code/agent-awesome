// This file defines Slack event data models used by the channel adapter.
package slack

import "time"

// Config stores the dependencies and policy needed by the Slack adapter.
type Config struct {
	Enabled          bool
	SocketMode       bool
	SigningSecret    string
	BotToken         string
	AppToken         string
	AllowedTeamID    string
	AllowedUserID    string
	AllowedChannelID string
	HarnessBaseURL   string
	AppName          string
	AgentUserID      string
	RequestTimeout   time.Duration
}

// EventEnvelope is the outer Slack Events API payload.
type EventEnvelope struct {
	Type      string       `json:"type"`
	Challenge string       `json:"challenge"`
	TeamID    string       `json:"team_id"`
	Event     MessageEvent `json:"event"`
}

// MessageEvent is the Slack message event subset Agent Awesome accepts.
type MessageEvent struct {
	Type     string `json:"type"`
	Subtype  string `json:"subtype"`
	Channel  string `json:"channel"`
	User     string `json:"user"`
	Text     string `json:"text"`
	TS       string `json:"ts"`
	ThreadTS string `json:"thread_ts"`
	BotID    string `json:"bot_id"`
}
