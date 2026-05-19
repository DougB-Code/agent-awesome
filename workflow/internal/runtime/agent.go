// This file implements internal workflow-to-harness agent calls.
package runtime

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"workflow/internal/actions"
)

// AgentClient calls the harness ADK API for scoped agent steps.
type AgentClient struct {
	baseURL string
	appName string
	userID  string
	client  *http.Client
}

// NewAgentClient creates an internal harness agent client.
func NewAgentClient(baseURL string, appName string, userID string, timeout time.Duration) *AgentClient {
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	return &AgentClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		appName: appName,
		userID:  userID,
		client:  &http.Client{Timeout: timeout},
	}
}

// Run executes one scoped agent step and returns structured output metadata.
func (c *AgentClient) Run(ctx context.Context, req actions.AgentRequest) (map[string]any, error) {
	if strings.TrimSpace(c.baseURL) == "" {
		return nil, fmt.Errorf("harness base URL is required for agent.run")
	}
	sessionID := "workflow:" + req.RunID + ":" + req.StepID
	if err := c.ensureSession(ctx, sessionID); err != nil {
		return nil, err
	}
	prompt, inputHash, err := agentPrompt(req)
	if err != nil {
		return nil, err
	}
	text, err := c.runText(ctx, sessionID, prompt)
	if err != nil {
		return nil, err
	}
	output := map[string]any{
		"text":       text,
		"input_hash": inputHash,
	}
	var parsed any
	if err := json.Unmarshal([]byte(text), &parsed); err == nil {
		output["json"] = parsed
		output["parse_status"] = "valid_json"
	} else {
		output["parse_status"] = "text"
	}
	output["validation_status"] = "harness_owned"
	return output, nil
}

// ensureSession creates the workflow-scoped harness session when needed.
func (c *AgentClient) ensureSession(ctx context.Context, sessionID string) error {
	body := []byte(`{"state":{}}`)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.sessionsURL(), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("create harness session: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	if resp.StatusCode == http.StatusConflict {
		return nil
	}
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	if strings.Contains(strings.ToLower(string(data)), "already") {
		return nil
	}
	return fmt.Errorf("create harness session: HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(data)))
}

// runText sends one non-streaming run_sse request and decodes final text.
func (c *AgentClient) runText(ctx context.Context, sessionID string, text string) (string, error) {
	body, err := json.Marshal(map[string]any{
		"appName":   c.appName,
		"userId":    c.userID,
		"sessionId": sessionID,
		"streaming": false,
		"newMessage": map[string]any{
			"role": "user",
			"parts": []map[string]string{
				{"text": text},
			},
		},
	})
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
		return "", fmt.Errorf("run harness agent: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return "", fmt.Errorf("run harness agent: HTTP %d %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return decodeSSEText(resp.Body)
}

// sessionsURL builds the harness session collection URL.
func (c *AgentClient) sessionsURL() string {
	return c.baseURL + "/apps/" + url.PathEscape(c.appName) + "/users/" + url.PathEscape(c.userID) + "/sessions"
}

// agentPrompt builds one workflow step prompt for harness-owned agent behavior.
func agentPrompt(req actions.AgentRequest) (string, string, error) {
	input, err := json.Marshal(req.Input)
	if err != nil {
		return "", "", fmt.Errorf("encode agent input: %w", err)
	}
	hash := sha256.Sum256(input)
	var b strings.Builder
	b.WriteString("You are executing one workflow step. Return only the requested result.\n")
	b.WriteString("Instructions:\n")
	b.WriteString(req.Instructions)
	b.WriteString("\nInput JSON:\n")
	b.Write(input)
	return b.String(), hex.EncodeToString(hash[:]), nil
}

// decodeSSEText extracts assistant text from an ADK SSE stream.
func decodeSSEText(reader io.Reader) (string, error) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	var data strings.Builder
	var texts []string
	flush := func() error {
		if data.Len() == 0 {
			return nil
		}
		text, err := textFromEvent(data.String())
		if err != nil {
			return err
		}
		if text != "" {
			texts = append(texts, text)
		}
		data.Reset()
		return nil
	}
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "data:"):
			if data.Len() > 0 {
				data.WriteByte('\n')
			}
			data.WriteString(strings.TrimLeft(strings.TrimPrefix(line, "data:"), " "))
		case line == "" && data.Len() > 0:
			if err := flush(); err != nil {
				return "", err
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if err := flush(); err != nil {
		return "", err
	}
	return strings.Join(texts, "\n"), nil
}

// textFromEvent extracts all text parts from one ADK event payload.
func textFromEvent(raw string) (string, error) {
	var event struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	}
	if err := json.Unmarshal([]byte(raw), &event); err != nil {
		return "", fmt.Errorf("decode agent SSE event: %w", err)
	}
	var parts []string
	for _, part := range event.Content.Parts {
		if part.Text != "" {
			parts = append(parts, part.Text)
		}
	}
	return strings.Join(parts, ""), nil
}
