// This file resolves codebase records through the memory MCP catalog tools.
package operations

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
)

// MemoryCodebaseClient calls memory MCP codebase tools.
type MemoryCodebaseClient struct {
	endpoint string
	client   *http.Client
	nextID   atomic.Int64
}

// NewMemoryCodebaseClient creates a memory-backed codebase catalog client.
func NewMemoryCodebaseClient(endpoint string, timeout time.Duration) *MemoryCodebaseClient {
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	return &MemoryCodebaseClient{endpoint: strings.TrimSpace(endpoint), client: &http.Client{Timeout: timeout}}
}

// GetCodebase loads one codebase through memory MCP.
func (c *MemoryCodebaseClient) GetCodebase(ctx context.Context, id string) (Codebase, error) {
	var out Codebase
	if strings.TrimSpace(id) == "" {
		return out, fmt.Errorf("codebase id is required")
	}
	result, err := c.call(ctx, "get_codebase", map[string]any{"id": id})
	if err != nil {
		return out, err
	}
	if err := decodeStructured(result, &out); err != nil {
		return out, err
	}
	return out, nil
}

// ResolveCodebase resolves one codebase through memory MCP.
func (c *MemoryCodebaseClient) ResolveCodebase(ctx context.Context, query string) (CodebaseResolution, error) {
	var out CodebaseResolution
	if strings.TrimSpace(query) == "" {
		return out, fmt.Errorf("query is required")
	}
	result, err := c.call(ctx, "resolve_codebase", map[string]any{"query": query})
	if err != nil {
		return out, err
	}
	if err := decodeStructured(result, &out); err != nil {
		return out, err
	}
	return out, nil
}

// call invokes one memory MCP tool and returns structured content.
func (c *MemoryCodebaseClient) call(ctx context.Context, tool string, args map[string]any) (map[string]any, error) {
	if c == nil || c.endpoint == "" {
		return nil, fmt.Errorf("memory codebase endpoint is not configured")
	}
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      c.nextID.Add(1),
		"method":  "tools/call",
		"params": map[string]any{
			"name":      tool,
			"arguments": args,
		},
	})
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := c.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("call memory MCP: %w", err)
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("read memory MCP response: %w", err)
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return nil, fmt.Errorf("memory MCP HTTP %d: %s", response.StatusCode, strings.TrimSpace(string(data)))
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		return nil, fmt.Errorf("decode memory MCP response: %w", err)
	}
	if rpcErr, ok := decoded["error"].(map[string]any); ok {
		return nil, fmt.Errorf("memory MCP error: %v", rpcErr["message"])
	}
	result, _ := decoded["result"].(map[string]any)
	if isError, _ := result["isError"].(bool); isError {
		return nil, fmt.Errorf("memory MCP tool %s failed: %v", tool, result["structuredContent"])
	}
	structured, _ := result["structuredContent"].(map[string]any)
	return structured, nil
}

// decodeStructured decodes structured MCP content into a target DTO.
func decodeStructured(value any, target any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, target)
}
