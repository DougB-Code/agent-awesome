// This file decodes MCP manager server configuration.
package config

import (
	"encoding/json"
	"fmt"
	"strings"

	"agentawesome/internal/services/mcp/mcp"
)

// ParseServersJSON decodes JSON MCP server configuration.
func ParseServersJSON(value string) ([]mcp.ServerConfig, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	var servers []mcp.ServerConfig
	if err := json.Unmarshal([]byte(value), &servers); err != nil {
		return nil, fmt.Errorf("decode MCP servers: %w", err)
	}
	return servers, nil
}
