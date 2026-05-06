// This file wraps the Slack Web API calls needed by the adapter.
package slack

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const slackAPIBaseURL = "https://slack.com/api"

// WebAPI calls Slack methods used for Socket Mode and message replies.
type WebAPI struct {
	client   *http.Client
	botToken string
	appToken string
}

// NewWebAPI creates a Slack Web API client.
func NewWebAPI(client *http.Client, botToken string, appToken string) *WebAPI {
	if client == nil {
		client = &http.Client{}
	}
	return &WebAPI{client: client, botToken: botToken, appToken: appToken}
}

// OpenSocketURL requests a temporary Socket Mode WebSocket URL from Slack.
func (a *WebAPI) OpenSocketURL(ctx context.Context) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, slackAPIBaseURL+"/apps.connections.open", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+a.appToken)
	resp, err := a.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var decoded struct {
		OK    bool   `json:"ok"`
		URL   string `json:"url"`
		Error string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return "", fmt.Errorf("decode Slack socket response: %w", err)
	}
	if !decoded.OK || decoded.URL == "" {
		return "", fmt.Errorf("open Slack socket: %s", decoded.Error)
	}
	return decoded.URL, nil
}

// PostMessage sends one Slack reply to a channel or thread.
func (a *WebAPI) PostMessage(ctx context.Context, channel string, threadTS string, text string) error {
	body := map[string]string{
		"channel": channel,
		"text":    text,
	}
	if threadTS != "" {
		body["thread_ts"] = threadTS
	}
	data, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, slackAPIBaseURL+"/chat.postMessage", bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+a.botToken)
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var decoded struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return fmt.Errorf("decode Slack post response: %w", err)
	}
	if !decoded.OK {
		return fmt.Errorf("post Slack message: %s", decoded.Error)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return nil
}
