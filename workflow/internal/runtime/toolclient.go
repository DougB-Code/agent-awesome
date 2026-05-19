// This file implements harness context tool calls for workflow actions.
package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"workflow/internal/actions"
)

// ToolClient calls the harness-owned context tool API.
type ToolClient struct {
	baseURL string
	client  *http.Client
}

// NewToolClient creates a context API client for workflow tool.call actions.
func NewToolClient(baseURL string, timeout time.Duration) *ToolClient {
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	return &ToolClient{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		client:  &http.Client{Timeout: timeout},
	}
}

// List returns harness-exposed tool names for authoring diagnostics.
func (c *ToolClient) List(ctx context.Context) ([]string, error) {
	endpoint, err := c.endpoint("/tools/list")
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("list context tools: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("read context tool list: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("context tools/list HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var decoded struct {
		Tools []string `json:"tools"`
	}
	if err := json.Unmarshal(body, &decoded); err != nil {
		return nil, fmt.Errorf("decode context tool list: %w", err)
	}
	return decoded.Tools, nil
}

// Call invokes one harness-exposed context tool.
func (c *ToolClient) Call(ctx context.Context, req actions.ToolRequest) (map[string]any, error) {
	if strings.TrimSpace(req.Name) == "" {
		return nil, fmt.Errorf("tool.call name is required")
	}
	endpoint, err := c.endpoint("/tools/call")
	if err != nil {
		return nil, err
	}
	payload, err := json.Marshal(map[string]any{
		"name":      strings.TrimSpace(req.Name),
		"domain_id": strings.TrimSpace(req.DomainID),
		"arguments": nilMap(req.Arguments),
	})
	if err != nil {
		return nil, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("call context tool: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("read context tool response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("context tools/call HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		return nil, fmt.Errorf("decode context tool response: %w", err)
	}
	if errorValue, ok := decoded["error"]; ok && errorValue != nil {
		return nil, fmt.Errorf("context tool error: %v", errorValue)
	}
	if structured, ok := decoded["structuredContent"]; ok {
		if structuredMap, ok := structured.(map[string]any); ok {
			return structuredMap, nil
		}
		return map[string]any{"value": structured}, nil
	}
	return decoded, nil
}

// endpoint resolves context API routes from either an API or /api/context base URL.
func (c *ToolClient) endpoint(path string) (string, error) {
	if c.baseURL == "" {
		return "", fmt.Errorf("harness context base URL is required for tool.call")
	}
	base := c.baseURL
	switch {
	case strings.HasSuffix(base, "/api/context"):
	case strings.HasSuffix(base, "/api"):
		base += "/context"
	default:
		base = strings.TrimRight(base, "/") + "/api/context"
	}
	return base + path, nil
}

// nilMap returns an empty map for nil tool arguments.
func nilMap(value map[string]any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	return value
}
