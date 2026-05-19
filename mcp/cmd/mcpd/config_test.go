// This file tests mcpd configuration parsing.
package main

import "testing"

// TestParseConfigReadsServers verifies JSON server configuration loads.
func TestParseConfigReadsServers(t *testing.T) {
	cfg, err := parseConfig([]string{
		"-servers-json", `[{"id":"local","endpoint":"http://127.0.0.1:9090/mcp","auto_start":true}]`,
	})
	if err != nil {
		t.Fatalf("parseConfig() error = %v", err)
	}

	if len(cfg.MCP.Servers) != 1 || cfg.MCP.Servers[0].ID != "local" {
		t.Fatalf("servers = %#v, want local server", cfg.MCP.Servers)
	}
}
