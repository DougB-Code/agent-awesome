// This file tests standalone memory daemon configuration safety.
package main

import "testing"

// TestParseConfigAllowsLoopbackWithoutPublicBind verifies local defaults stay simple.
func TestParseConfigAllowsLoopbackWithoutPublicBind(t *testing.T) {
	cfg, err := parseConfig([]string{"--addr", "127.0.0.1:0"})
	if err != nil {
		t.Fatalf("parseConfig() error = %v", err)
	}
	if cfg.ListenAddress != "127.0.0.1:0" {
		t.Fatalf("ListenAddress = %q, want 127.0.0.1:0", cfg.ListenAddress)
	}
}

// TestParseConfigRejectsPublicBindWithoutEscapeHatch verifies MCP is not exposed by typo.
func TestParseConfigRejectsPublicBindWithoutEscapeHatch(t *testing.T) {
	if _, err := parseConfig([]string{"--addr", "0.0.0.0:8090"}); err == nil {
		t.Fatalf("parseConfig() error = nil, want public bind validation error")
	}
}

// TestParseConfigAllowsPublicBindWithEscapeHatch verifies public exposure is explicit.
func TestParseConfigAllowsPublicBindWithEscapeHatch(t *testing.T) {
	cfg, err := parseConfig([]string{"--addr", "0.0.0.0:8090", "--allow-public-bind"})
	if err != nil {
		t.Fatalf("parseConfig() error = %v", err)
	}
	if !cfg.AllowPublicBind {
		t.Fatalf("AllowPublicBind = false, want true")
	}
}
