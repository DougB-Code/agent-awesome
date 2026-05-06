// This file calls the ADK REST harness on behalf of Slack messages.
package slack

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"agentgateway/internal/proxy"
)

// AgentClient forwards normalized Slack text into the harness REST API.
type AgentClient struct {
	client  *http.Client
	baseURL string
	appName string
	userID  string
}

// NewAgentClient creates an ADK REST client for one gateway harness upstream.
func NewAgentClient(client *http.Client, baseURL string, appName string, userID string) *AgentClient {
	if client == nil {
		client = &http.Client{}
	}
	return &AgentClient{
		client:  client,
		baseURL: strings.TrimRight(baseURL, "/"),
		appName: appName,
		userID:  userID,
	}
}

// EnsureSession creates a session when the Slack thread has not been seen yet.
func (c *AgentClient) EnsureSession(ctx context.Context, sessionID string) error {
	exists, err := c.sessionExists(ctx, sessionID)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	body, err := json.Marshal(map[string]any{"state": map[string]any{}})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.sessionURL(sessionID), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	exists, _ = c.sessionExists(ctx, sessionID)
	if exists {
		return nil
	}
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
	return fmt.Errorf("create agent session: HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(data)))
}

// RunText sends one message to the agent and returns final assistant text.
func (c *AgentClient) RunText(ctx context.Context, sessionID string, text string) (string, error) {
	body, err := c.runBody(sessionID, text)
	if err != nil {
		return "", err
	}
	body, _, err = proxy.InjectRuntimePolicy(body)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/run_sse", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return "", fmt.Errorf("run agent: HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return decodeAgentSSE(resp.Body)
}

// sessionExists reports whether an ADK session already exists.
func (c *AgentClient) sessionExists(ctx context.Context, sessionID string) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.sessionURL(sessionID), nil)
	if err != nil {
		return false, err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return true, nil
	}
	if resp.StatusCode == http.StatusNotFound {
		return false, nil
	}
	if resp.StatusCode == http.StatusInternalServerError {
		data, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		if strings.Contains(strings.ToLower(string(data)), "not found") {
			return false, nil
		}
		return false, fmt.Errorf("get agent session: HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return false, fmt.Errorf("get agent session: HTTP %d", resp.StatusCode)
}

// sessionURL builds the ADK REST session URL for one session id.
func (c *AgentClient) sessionURL(sessionID string) string {
	return c.baseURL + "/apps/" + url.PathEscape(c.appName) + "/users/" + url.PathEscape(c.userID) + "/sessions/" + url.PathEscape(sessionID)
}

// runBody builds the ADK REST run_sse request body.
func (c *AgentClient) runBody(sessionID string, text string) ([]byte, error) {
	return json.Marshal(map[string]any{
		"appName":   c.appName,
		"userId":    c.userID,
		"sessionId": sessionID,
		"streaming": false,
		"newMessage": map[string]any{
			"role": "user",
			"parts": []map[string]any{
				{"text": text},
			},
		},
	})
}

// decodeAgentSSE extracts final assistant text from an ADK SSE response.
func decodeAgentSSE(reader io.Reader) (string, error) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	eventType := "message"
	var data strings.Builder
	var texts []string
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "event:"):
			eventType = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
		case strings.HasPrefix(line, "data:"):
			if data.Len() > 0 {
				data.WriteByte('\n')
			}
			data.WriteString(strings.TrimLeft(strings.TrimPrefix(line, "data:"), " "))
		case line == "" && data.Len() > 0:
			text, err := decodeAgentEvent(eventType, data.String())
			if err != nil {
				return "", err
			}
			if text != "" {
				texts = append(texts, text)
			}
			eventType = "message"
			data.Reset()
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if data.Len() > 0 {
		text, err := decodeAgentEvent(eventType, data.String())
		if err != nil {
			return "", err
		}
		if text != "" {
			texts = append(texts, text)
		}
	}
	return strings.TrimSpace(strings.Join(texts, "\n")), nil
}

// decodeAgentEvent returns display text from one ADK event payload.
func decodeAgentEvent(eventType string, data string) (string, error) {
	var event struct {
		Error        any    `json:"error"`
		Author       string `json:"author"`
		Partial      bool   `json:"partial"`
		ErrorMessage string `json:"errorMessage"`
		Content      struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	}
	if err := json.Unmarshal([]byte(data), &event); err != nil {
		return "", fmt.Errorf("decode agent event: %w", err)
	}
	if eventType == "error" || event.Error != nil || event.ErrorMessage != "" {
		if event.ErrorMessage != "" {
			return "", fmt.Errorf("agent event error: %s", event.ErrorMessage)
		}
		return "", fmt.Errorf("agent event error: %v", event.Error)
	}
	if event.Partial || event.Author == "user" {
		return "", nil
	}
	var parts []string
	for _, part := range event.Content.Parts {
		if strings.TrimSpace(part.Text) != "" {
			parts = append(parts, part.Text)
		}
	}
	return strings.TrimSpace(strings.Join(parts, "\n")), nil
}
