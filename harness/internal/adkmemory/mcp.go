// This file calls Agent Awesome memory tools over a configured MCP transport.
package adkmemory

import (
	"context"
	"encoding/json"
	"fmt"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcpclient"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	mcpClientName    = "agentawesome-memory"
	mcpClientVersion = "v1.0.0"
)

// connect opens one MCP client session for memory launchpad.
func (s *Service) connect(ctx context.Context, server schema.MCPServer) (*mcp.ClientSession, error) {
	return mcpclient.Connect(ctx, server, mcpClientName, mcpClientVersion)
}

// callTool invokes one memory MCP tool and returns structured content.
func callTool(ctx context.Context, session *mcp.ClientSession, name string, arguments map[string]any) (any, error) {
	result, err := session.CallTool(ctx, &mcp.CallToolParams{
		Name:      name,
		Arguments: arguments,
	})
	if err != nil {
		return nil, fmt.Errorf("call %s: %w", name, err)
	}
	if result == nil {
		return nil, fmt.Errorf("call %s: empty MCP result", name)
	}
	if result.IsError {
		return nil, fmt.Errorf("%s returned an MCP tool error", name)
	}
	return result.StructuredContent, nil
}

// decodeStructured unmarshals MCP structured content into a typed value.
func decodeStructured[T any](value any) (T, error) {
	var out T
	if value == nil {
		return out, nil
	}
	raw, err := json.Marshal(value)
	if err != nil {
		return out, fmt.Errorf("marshal structured content: %w", err)
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return out, fmt.Errorf("decode structured content: %w", err)
	}
	return out, nil
}
