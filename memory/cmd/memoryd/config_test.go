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

// TestParseConfigRequiresSnapshotURLAndTokenTogether verifies snapshot auth is explicit.
func TestParseConfigRequiresSnapshotURLAndTokenTogether(t *testing.T) {
	if _, err := parseConfig([]string{"--snapshot-url", "https://example.test/snapshot"}); err == nil {
		t.Fatalf("parseConfig() error = nil, want missing token validation error")
	}
	if _, err := parseConfig([]string{"--snapshot-token", "secret"}); err == nil {
		t.Fatalf("parseConfig() error = nil, want missing URL validation error")
	}
}

// TestParseConfigAcceptsCheckConfig verifies preflight mode parses safely.
func TestParseConfigAcceptsCheckConfig(t *testing.T) {
	cfg, err := parseConfig([]string{"--check-config"})
	if err != nil {
		t.Fatalf("parseConfig() error = %v", err)
	}
	if !cfg.CheckConfig {
		t.Fatalf("CheckConfig = false, want true")
	}
}
