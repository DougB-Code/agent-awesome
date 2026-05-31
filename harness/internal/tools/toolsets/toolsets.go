// This file builds runtime tool bundles from tool configuration.
package toolsets

import (
	"fmt"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcptransport"
	"agentawesome/internal/tools/toolbundle"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/rs/zerolog/log"
	"google.golang.org/adk/agent"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/mcptoolset"
)

// Build creates the complete ADK tool bundle for the runtime.
func Build(cfg *schema.Tools) (toolbundle.Bundle, error) {
	if cfg != nil {
		if err := cfg.Validate(); err != nil {
			return toolbundle.Bundle{}, fmt.Errorf("validate tools config: %w", err)
		}
	}

	mcpToolsets, err := buildMCPToolsets(cfg)
	if err != nil {
		return toolbundle.Bundle{}, fmt.Errorf("create mcp toolsets: %w", err)
	}

	return toolbundle.Bundle{
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
		if !hasConfiguredModelVisibleTools(server, cfg) {
			continue
		}
		ts, err := buildMCPToolset(server, cfg)
		if err != nil {
			return nil, err
		}
		toolsets = append(toolsets, ts)
	}
	return toolsets, nil
}

// buildMCPToolset creates one ADK toolset for an MCP server.
func buildMCPToolset(server schema.MCPServer, cfg *schema.Tools) (tool.Toolset, error) {
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

	if predicate := modelVisibleToolPredicate(server, cfg); predicate != nil {
		ts = tool.FilterToolset(ts, predicate)
	}

	return ts, nil
}

// hasConfiguredModelVisibleTools reports whether an explicit allow list leaves
// any tools after runtime-only tools are removed.
func hasConfiguredModelVisibleTools(server schema.MCPServer, cfg *schema.Tools) bool {
	if len(server.Tools.Allow) == 0 {
		return true
	}
	blocked := blockedModelVisibleTools(cfg)
	for _, name := range server.Tools.Allow {
		if _, ok := blocked[strings.TrimSpace(name)]; !ok {
			return true
		}
	}
	return false
}

// modelVisibleToolPredicate combines configured allow lists with AA runtime
// tools that should not be exposed as ordinary LLM-callable MCP tools.
func modelVisibleToolPredicate(server schema.MCPServer, cfg *schema.Tools) tool.Predicate {
	allowed := stringSet(server.Tools.Allow)
	blocked := blockedModelVisibleTools(cfg)
	if len(allowed) == 0 && len(blocked) == 0 {
		return nil
	}
	return func(_ agent.ReadonlyContext, candidate tool.Tool) bool {
		name := strings.TrimSpace(candidate.Name())
		if _, ok := blocked[name]; ok {
			return false
		}
		if len(allowed) == 0 {
			return true
		}
		_, ok := allowed[name]
		return ok
	}
}

// blockedModelVisibleTools returns MCP tool names kept behind ADK memory
// boundaries instead of being exposed directly to the model.
func blockedModelVisibleTools(cfg *schema.Tools) map[string]struct{} {
	blocked := map[string]struct{}{}
	if memoryRuntimeEnabled(cfg) {
		for name := range stringSet([]string{
			"remember",
			"save_memory_candidate",
			"search_memory",
			"search_sources",
			"organize_memory",
			"load_entity_page",
			"load_timeline",
			"refresh_compiled_page",
			"repair_memory_record",
			"submit_memory_correction",
		}) {
			blocked[name] = struct{}{}
		}
	}
	return blocked
}

// memoryRuntimeEnabled reports whether ADK memory tools should own memory access.
func memoryRuntimeEnabled(cfg *schema.Tools) bool {
	return cfg != nil && len(cfg.Memory.ReadDomains) > 0
}

// stringSet builds a trimmed lookup table.
func stringSet(values []string) map[string]struct{} {
	set := make(map[string]struct{}, len(values))
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			set[trimmed] = struct{}{}
		}
	}
	return set
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
		log.Info().
			Str("tool", toolName).
			Bool("require_confirmation", ok).
			Msg("mcp tool confirmation decision")
		return ok
	}
}
