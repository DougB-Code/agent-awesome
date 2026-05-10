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

// slackAPIRequest stores one outbound Slack Web API request description.
type slackAPIRequest struct {
	method      string
	token       string
	contentType string
	body        io.Reader
	response    any
	decodeLabel string
}

// slackAPIStatus stores the common Slack Web API success envelope.
type slackAPIStatus struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

// openSocketResponse stores Slack's Socket Mode URL response.
type openSocketResponse struct {
	slackAPIStatus
	URL string `json:"url"`
}

// NewWebAPI creates a Slack Web API client.
func NewWebAPI(client *http.Client, botToken string, appToken string) *WebAPI {
	if client == nil {
		client = &http.Client{}
	}
	return &WebAPI{client: client, botToken: botToken, appToken: appToken}
}

// post sends one Slack Web API request and decodes the JSON response.
func (a *WebAPI) post(ctx context.Context, request slackAPIRequest) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, slackAPIBaseURL+"/"+request.method, request.body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+request.token)
	if request.contentType != "" {
		req.Header.Set("Content-Type", request.contentType)
	}
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if err := json.NewDecoder(resp.Body).Decode(request.response); err != nil {
		return fmt.Errorf("decode %s: %w", request.decodeLabel, err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return nil
}

// OpenSocketURL requests a temporary Socket Mode WebSocket URL from Slack.
func (a *WebAPI) OpenSocketURL(ctx context.Context) (string, error) {
	var decoded openSocketResponse
	if err := a.post(ctx, slackAPIRequest{
		method:      "apps.connections.open",
		token:       a.appToken,
		response:    &decoded,
		decodeLabel: "Slack socket response",
	}); err != nil {
		return "", err
	}
	if !decoded.OK || decoded.URL == "" {
		return "", decoded.err("open Slack socket")
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
	var decoded slackAPIStatus
	if err := a.post(ctx, slackAPIRequest{
		method:      "chat.postMessage",
		token:       a.botToken,
		contentType: "application/json",
		body:        bytes.NewReader(data),
		response:    &decoded,
		decodeLabel: "Slack post response",
	}); err != nil {
		return err
	}
	if !decoded.OK {
		return decoded.err("post Slack message")
	}
	return nil
}

// err formats one Slack Web API failure response.
func (s slackAPIStatus) err(operation string) error {
	return fmt.Errorf("%s: %s", operation, s.Error)
}
