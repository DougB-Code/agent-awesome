// This file parses mcpd command-line configuration.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"mcp/internal/mcp"
)

// config stores mcpd process settings.
type config struct {
	ListenAddress string
	ServersJSON   string
	CheckConfig   bool
	MCP           mcp.Config
}

// parseConfig parses mcpd flags and environment defaults.
func parseConfig(args []string) (config, error) {
	cfg := config{
		ListenAddress: envString("AGENTAWESOME_MCP_ADDR", "127.0.0.1:8094"),
		ServersJSON:   envString("AGENTAWESOME_MCP_SERVERS_JSON", ""),
	}
	mcpCfg := mcp.Config{
		RequestTimeout: envDuration("AGENTAWESOME_MCP_REQUEST_TIMEOUT", 10*time.Minute),
	}
	fs := flag.NewFlagSet("mcpd", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "mcpd listen address")
	fs.StringVar(&cfg.ServersJSON, "servers-json", cfg.ServersJSON, "JSON MCP server configuration list")
	fs.DurationVar(&mcpCfg.RequestTimeout, "request-timeout", mcpCfg.RequestTimeout, "upstream MCP request timeout")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit")
	if err := fs.Parse(args); err != nil {
		return config{}, err
	}
	servers, err := parseServers(cfg.ServersJSON)
	if err != nil {
		return config{}, err
	}
	mcpCfg.Servers = servers
	cfg.MCP = mcpCfg
	return cfg, cfg.Validate()
}

// Validate reports unsafe or incomplete mcpd settings.
func (c config) Validate() error {
	if strings.TrimSpace(c.ListenAddress) == "" {
		return fmt.Errorf("listen address is required")
	}
	return nil
}

// parseServers decodes JSON MCP server configuration.
func parseServers(value string) ([]mcp.ServerConfig, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	var servers []mcp.ServerConfig
	if err := json.Unmarshal([]byte(value), &servers); err != nil {
		return nil, fmt.Errorf("decode MCP servers: %w", err)
	}
	return servers, nil
}

// envString returns a string environment value or fallback.
func envString(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// envDuration returns a duration environment value or fallback.
func envDuration(name string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}
