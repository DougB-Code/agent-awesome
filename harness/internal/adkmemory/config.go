// This file selects memory MCP configuration and exposes ADK memory tools.
package adkmemory

import (
	"fmt"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcptransport"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/loadmemorytool"
	"google.golang.org/adk/tool/preloadmemorytool"
)

// NewFromToolsConfig creates an ADK memory service from configured MCP servers.
func NewFromToolsConfig(cfg *schema.Tools) (*Service, bool, error) {
	server, ok := selectMemoryServer(cfg)
	if !ok {
		return nil, false, nil
	}
	if _, err := mcptransport.New(server); err != nil {
		return nil, true, fmt.Errorf("create memory MCP transport: %w", err)
	}
	return New(server), true, nil
}

// RuntimeTools returns ADK tools that search and preload configured memory.
func RuntimeTools() []tool.Tool {
	return []tool.Tool{
		preloadmemorytool.New(),
		loadmemorytool.New(),
	}
}

// selectMemoryServer finds the MCP server intended to back ADK memory.
func selectMemoryServer(cfg *schema.Tools) (schema.MCPServer, bool) {
	if cfg == nil || !cfg.MCP.Enabled {
		return schema.MCPServer{}, false
	}
	for _, server := range cfg.MCP.Servers {
		if isMemoryServerName(server.Name) {
			return server, true
		}
	}
	for _, server := range cfg.MCP.Servers {
		if allowsMemoryTools(server.Tools.Allow) {
			return server, true
		}
	}
	return schema.MCPServer{}, false
}

// isMemoryServerName reports whether a server name explicitly names memory.
func isMemoryServerName(name string) bool {
	normalized := strings.ToLower(strings.TrimSpace(name))
	return normalized == "memory" || normalized == "agentawesome-memory"
}

// allowsMemoryTools reports whether an allowlist exposes the memory primitives.
func allowsMemoryTools(allowed []string) bool {
	names := make(map[string]struct{}, len(allowed))
	for _, name := range allowed {
		names[strings.TrimSpace(name)] = struct{}{}
	}
	_, hasSave := names[saveMemoryToolName]
	_, hasSearchMemory := names[searchMemoryToolName]
	_, hasSearchSources := names[searchSourcesToolName]
	return hasSave && (hasSearchMemory || hasSearchSources)
}

// preferredSearchTool returns the richest configured memory search tool.
func preferredSearchTool(allowed []string) string {
	if len(allowed) == 0 {
		return searchSourcesToolName
	}
	for _, name := range allowed {
		if strings.TrimSpace(name) == searchSourcesToolName {
			return searchSourcesToolName
		}
	}
	for _, name := range allowed {
		if strings.TrimSpace(name) == searchMemoryToolName {
			return searchMemoryToolName
		}
	}
	return searchSourcesToolName
}
