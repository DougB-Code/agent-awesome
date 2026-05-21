// This file implements minimal MCP client calls for workflow actions.
package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"agentawesome/internal/services/workflow/actions"
)

// MCPClient sends JSON-RPC tools/call requests to MCP endpoints.
type MCPClient struct {
	client *http.Client
	nextID atomic.Int64
}

// NewMCPClient creates a JSON-RPC MCP client.
func NewMCPClient(timeout time.Duration) *MCPClient {
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	return &MCPClient{client: &http.Client{Timeout: timeout}}
}

// Call invokes one MCP tool and returns structured content when present.
func (c *MCPClient) Call(ctx context.Context, req actions.MCPRequest) (map[string]any, error) {
	endpoint := strings.TrimSpace(req.Endpoint)
	if endpoint == "" {
		return nil, fmt.Errorf("mcp.call endpoint is required")
	}
	if strings.TrimSpace(req.Tool) == "" {
		return nil, fmt.Errorf("mcp.call tool is required")
	}
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      c.nextID.Add(1),
		"method":  "tools/call",
		"params": map[string]any{
			"name":      req.Tool,
			"arguments": req.Arguments,
		},
	})
	if err != nil {
		return nil, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("call MCP endpoint: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("read MCP response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("MCP HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		return nil, fmt.Errorf("decode MCP response: %w", err)
	}
	if rpcErr, ok := decoded["error"].(map[string]any); ok {
		return nil, fmt.Errorf("MCP error: %v", rpcErr["message"])
	}
	result, _ := decoded["result"].(map[string]any)
	if err := mcpToolResultError(req.Tool, result); err != nil {
		return nil, err
	}
	if structured, ok := result["structuredContent"].(map[string]any); ok {
		return structured, nil
	}
	return result, nil
}

// mcpToolResultError converts MCP isError tool results into action failures.
func mcpToolResultError(toolName string, result map[string]any) error {
	isError, _ := result["isError"].(bool)
	if !isError {
		return nil
	}
	return fmt.Errorf("MCP tool %s failed: %s", strings.TrimSpace(toolName), mcpToolErrorText(result))
}

// mcpToolErrorText extracts the most useful message from an MCP error result.
func mcpToolErrorText(result map[string]any) string {
	if structured, ok := result["structuredContent"].(map[string]any); ok {
		if message, ok := structured["error"].(string); ok && strings.TrimSpace(message) != "" {
			return strings.TrimSpace(message)
		}
		if data, err := json.Marshal(structured); err == nil && len(data) > 0 {
			return string(data)
		}
	}
	if content, ok := result["content"].([]any); ok {
		for _, item := range content {
			itemMap, _ := item.(map[string]any)
			text, _ := itemMap["text"].(string)
			if strings.TrimSpace(text) != "" {
				return strings.TrimSpace(text)
			}
		}
	}
	return "tool returned isError=true"
}
