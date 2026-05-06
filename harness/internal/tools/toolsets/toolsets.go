// This file builds runtime tool bundles from tool configuration.
package toolsets

import (
	"fmt"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/runtime"
	"agentawesome/internal/tools/localexec"
	"agentawesome/internal/tools/mcptransport"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/mcptoolset"
)

// Build creates the complete ADK tool bundle for the runtime.
func Build(cfg *schema.Tools) (runtime.ToolsConfig, error) {
	if cfg != nil {
		if err := cfg.Validate(); err != nil {
			return runtime.ToolsConfig{}, fmt.Errorf("validate tools config: %w", err)
		}
	}

	localTools, err := localexec.NewTools(cfg)
	if err != nil {
		return runtime.ToolsConfig{}, fmt.Errorf("create local tools: %w", err)
	}

	mcpToolsets, err := buildMCPToolsets(cfg)
	if err != nil {
		return runtime.ToolsConfig{}, fmt.Errorf("create mcp toolsets: %w", err)
	}

	return runtime.ToolsConfig{
		Tools:    localTools,
		Toolsets: mcpToolsets,
	}, nil
}

// buildMCPToolsets creates all configured MCP toolsets.
func buildMCPToolsets(cfg *schema.Tools) ([]tool.Toolset, error) {
	if cfg == nil || !cfg.MCP.Enabled {
		return nil, nil
	}

	toolsets := make([]tool.Toolset, 0, len(cfg.MCP.Servers))
	for _, server := range cfg.MCP.Servers {
		ts, err := buildMCPToolset(server)
		if err != nil {
			return nil, err
		}
		toolsets = append(toolsets, ts)
	}
	return toolsets, nil
}

// buildMCPToolset creates one ADK toolset for an MCP server.
func buildMCPToolset(server schema.MCPServer) (tool.Toolset, error) {
	transport, err := buildMCPTransport(server)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", server.Name, err)
	}

	ts, err := mcptoolset.New(mcptoolset.Config{
		Transport:                   transport,
		RequireConfirmation:         server.RequireConfirmation,
		RequireConfirmationProvider: confirmationProvider(server.RequireConfirmationTools),
	})
	if err != nil {
		return nil, fmt.Errorf("%s: %w", server.Name, err)
	}

	if len(server.Tools.Allow) > 0 {
		ts = tool.FilterToolset(ts, tool.AllowedToolsPredicate(server.Tools.Allow))
	}

	return ts, nil
}

// buildMCPTransport creates the configured MCP transport.
func buildMCPTransport(server schema.MCPServer) (mcp.Transport, error) {
	return mcptransport.New(server)
}

// confirmationProvider returns a predicate that requires confirmation for the
// listed tool names.
func confirmationProvider(toolNames []string) tool.ConfirmationProvider {
	if len(toolNames) == 0 {
		return nil
	}

	require := make(map[string]struct{}, len(toolNames))
	for _, name := range toolNames {
		require[strings.TrimSpace(name)] = struct{}{}
	}

	return func(toolName string, toolInput any) bool {
		_, ok := require[toolName]
		return ok
	}
}
