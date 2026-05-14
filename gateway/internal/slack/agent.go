// This file calls the gateway assistant API on behalf of Slack messages.
package slack

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"agentgateway/internal/adk"
	"agentgateway/internal/policy"
)

const confirmationFunctionName = "adk_request_confirmation"
const agentSessionErrorBodyLimit int64 = 1024
const agentRunErrorBodyLimit int64 = 2048
const agentDependencyRetryDelay = 500 * time.Millisecond

var errSlackConfirmationUnsupported = errors.New("slack tool confirmation is unsupported")
var errAgentDependencyNotReady = errors.New("agent dependency not ready")

// AgentClient forwards normalized Slack text into the gateway REST API.
type AgentClient struct {
	client  *http.Client
	baseURL string
	appName string
	userID  string
	headers map[string]string
	policy  *policy.Injector
}

// NewAgentClient creates an assistant client without local policy injection.
func NewAgentClient(client *http.Client, baseURL string, appName string, userID string) *AgentClient {
	return NewAgentClientWithPolicy(
		client,
		baseURL,
		appName,
		userID,
		policy.NewInjector(policy.Config{}),
	)
}

// NewAgentClientWithPolicy creates an assistant client with configured policy.
func NewAgentClientWithPolicy(client *http.Client, baseURL string, appName string, userID string, injector *policy.Injector) *AgentClient {
	return NewAgentClientWithPolicyAndHeaders(
		client,
		baseURL,
		appName,
		userID,
		injector,
		nil,
	)
}

// NewAgentClientWithPolicyAndHeaders creates a gateway API client.
func NewAgentClientWithPolicyAndHeaders(client *http.Client, baseURL string, appName string, userID string, injector *policy.Injector, headers map[string]string) *AgentClient {
	if client == nil {
		client = &http.Client{}
	}
	if injector == nil {
		injector = policy.NewInjector(policy.Config{})
	}
	copiedHeaders := make(map[string]string, len(headers))
	for key, value := range headers {
		if strings.TrimSpace(key) != "" && strings.TrimSpace(value) != "" {
			copiedHeaders[key] = value
		}
	}
	return &AgentClient{
		client:  client,
		baseURL: strings.TrimRight(baseURL, "/"),
		appName: appName,
		userID:  userID,
		headers: copiedHeaders,
		policy:  injector,
	}
}

// EnsureSession creates a session when the Slack thread has not been seen yet.
func (c *AgentClient) EnsureSession(ctx context.Context, sessionID string) error {
	return retryAgentDependency(ctx, func() error {
		return c.ensureSessionOnce(ctx, sessionID)
	})
}

// ensureSessionOnce performs one session lookup/create attempt.
func (c *AgentClient) ensureSessionOnce(ctx context.Context, sessionID string) error {
	exists, err := c.sessionExists(ctx, sessionID)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	body, err := adk.SessionCreateBody()
	if err != nil {
		return err
	}
	req, err := c.newJSONRequest(ctx, c.sessionURL(sessionID), body)
	if err != nil {
		return err
	}
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
	return agentResponseError("create agent session", resp, agentSessionErrorBodyLimit)
}

// RunText sends one message to the agent and returns final assistant text.
func (c *AgentClient) RunText(ctx context.Context, sessionID string, text string) (string, error) {
	var reply string
	err := retryAgentDependency(ctx, func() error {
		var err error
		reply, err = c.runTextOnce(ctx, sessionID, text)
		return err
	})
	return reply, err
}

// runTextOnce sends one agent turn without retrying gateway readiness.
func (c *AgentClient) runTextOnce(ctx context.Context, sessionID string, text string) (string, error) {
	body, err := c.runBody(sessionID, text)
	if err != nil {
		return "", err
	}
	body, _, err = c.policy.Inject(body)
	if err != nil {
		return "", err
	}
	req, err := c.newJSONRequest(ctx, adk.RunSSEURL(c.baseURL), body)
	if err != nil {
		return "", err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", agentResponseError("run agent", resp, agentRunErrorBodyLimit)
	}
	return decodeAgentSSE(resp.Body)
}

// sessionExists reports whether an ADK session already exists.
func (c *AgentClient) sessionExists(ctx context.Context, sessionID string) (bool, error) {
	req, err := c.newRequest(ctx, http.MethodGet, c.sessionURL(sessionID), nil)
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
		data, _ := io.ReadAll(io.LimitReader(resp.Body, agentSessionErrorBodyLimit))
		if strings.Contains(strings.ToLower(string(data)), "not found") {
			return false, nil
		}
		return false, agentStatusError("get agent session", resp.StatusCode, string(data))
	}
	if resp.StatusCode == http.StatusServiceUnavailable {
		data, _ := io.ReadAll(io.LimitReader(resp.Body, agentSessionErrorBodyLimit))
		return false, agentStatusError("get agent session", resp.StatusCode, string(data))
	}
	return false, fmt.Errorf("get agent session: HTTP %d", resp.StatusCode)
}

// sessionURL builds the ADK REST session URL for one session id.
func (c *AgentClient) sessionURL(sessionID string) string {
	return adk.SessionURL(c.baseURL, c.appName, c.userID, sessionID)
}

// runBody builds the ADK REST run_sse request body.
func (c *AgentClient) runBody(sessionID string, text string) ([]byte, error) {
	return adk.RunRequestBody(c.appName, c.userID, sessionID, text)
}

// newRequest builds one gateway API request with configured channel headers.
func (c *AgentClient) newRequest(ctx context.Context, method string, targetURL string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, targetURL, body)
	if err != nil {
		return nil, err
	}
	for key, value := range c.headers {
		req.Header.Set(key, value)
	}
	return req, nil
}

// newJSONRequest builds one gateway API POST request with a JSON body.
func (c *AgentClient) newJSONRequest(ctx context.Context, targetURL string, body []byte) (*http.Request, error) {
	req, err := c.newRequest(ctx, http.MethodPost, targetURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	return req, nil
}

// decodeAgentSSE extracts final assistant text from an ADK SSE response.
func decodeAgentSSE(reader io.Reader) (string, error) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	eventType := "message"
	var data strings.Builder
	var texts []string
	flushEvent := func() error {
		if data.Len() == 0 {
			return nil
		}
		text, err := decodeAgentEvent(eventType, data.String())
		if err != nil {
			return err
		}
		if text != "" {
			texts = append(texts, text)
		}
		eventType = "message"
		data.Reset()
		return nil
	}
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
			if err := flushEvent(); err != nil {
				return "", err
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if err := flushEvent(); err != nil {
		return "", err
	}
	return strings.TrimSpace(strings.Join(texts, "\n")), nil
}

// agentResponseError formats one non-success assistant HTTP response with a body sample.
func agentResponseError(operation string, resp *http.Response, limit int64) error {
	data, _ := io.ReadAll(io.LimitReader(resp.Body, limit))
	return agentStatusError(operation, resp.StatusCode, string(data))
}

// agentStatusError formats one assistant HTTP status without leaking unlimited body data.
func agentStatusError(operation string, statusCode int, body string) error {
	detail := strings.TrimSpace(body)
	if statusCode == http.StatusServiceUnavailable && isAgentDependencyNotReadyBody(detail) {
		if detail == "" {
			return fmt.Errorf("%s: %w: HTTP %d", operation, errAgentDependencyNotReady, statusCode)
		}
		return fmt.Errorf("%s: %w: HTTP %d %s", operation, errAgentDependencyNotReady, statusCode, detail)
	}
	if detail == "" {
		return fmt.Errorf("%s: HTTP %d", operation, statusCode)
	}
	return fmt.Errorf("%s: HTTP %d %s", operation, statusCode, detail)
}

// isAgentDependencyNotReadyBody recognizes gateway readiness responses.
func isAgentDependencyNotReadyBody(body string) bool {
	body = strings.ToLower(body)
	return strings.Contains(body, "dependency not ready")
}

// retryAgentDependency waits through transient gateway dependency startup.
func retryAgentDependency(ctx context.Context, operation func() error) error {
	for {
		err := operation()
		if !errors.Is(err, errAgentDependencyNotReady) {
			return err
		}
		timer := time.NewTimer(agentDependencyRetryDelay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
}

// decodeAgentEvent returns display text from one assistant event payload.
func decodeAgentEvent(eventType string, data string) (string, error) {
	var event agentSSEEvent
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
	if call := firstAgentConfirmationCall(event.Content.Parts); call != nil {
		toolName := confirmationToolName(call)
		if toolName == "" {
			return "", errSlackConfirmationUnsupported
		}
		return "", fmt.Errorf("%w for %s", errSlackConfirmationUnsupported, toolName)
	}
	var parts []string
	for _, part := range event.Content.Parts {
		text := strings.TrimSpace(part.Text)
		if text == "" || looksLikeLocalToolMarkup(text) {
			continue
		}
		parts = append(parts, part.Text)
	}
	return strings.TrimSpace(strings.Join(parts, "\n")), nil
}

// agentSSEEvent stores the assistant SSE fields Slack needs to decode.
type agentSSEEvent struct {
	Error        any    `json:"error"`
	Author       string `json:"author"`
	Partial      bool   `json:"partial"`
	ErrorMessage string `json:"errorMessage"`
	Content      struct {
		Parts []agentSSEPart `json:"parts"`
	} `json:"content"`
}

// agentSSEPart stores one displayable or control part from an assistant event.
type agentSSEPart struct {
	Text         string             `json:"text"`
	FunctionCall *agentFunctionCall `json:"functionCall"`
}

// agentFunctionCall stores the function-call fields needed by Slack.
type agentFunctionCall struct {
	Name string         `json:"name"`
	Args map[string]any `json:"args"`
}

// firstAgentConfirmationCall finds the runtime confirmation request, if present.
func firstAgentConfirmationCall(parts []agentSSEPart) *agentFunctionCall {
	for _, part := range parts {
		if part.FunctionCall != nil && part.FunctionCall.Name == confirmationFunctionName {
			return part.FunctionCall
		}
	}
	return nil
}

// confirmationToolName returns the original tool that requested confirmation.
func confirmationToolName(call *agentFunctionCall) string {
	if call == nil {
		return ""
	}
	original, ok := call.Args["originalFunctionCall"].(map[string]any)
	if !ok {
		return ""
	}
	name, _ := original["name"].(string)
	return strings.TrimSpace(name)
}

// looksLikeLocalToolMarkup reports whether text contains local model control tokens.
func looksLikeLocalToolMarkup(text string) bool {
	trimmed := strings.TrimSpace(text)
	return strings.HasPrefix(trimmed, "<|tool_call>") ||
		strings.Contains(trimmed, "<|tool_call>call:") ||
		strings.Contains(trimmed, "<tool_call|>")
}
