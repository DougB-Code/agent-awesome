package config

import "testing"

// TestFromFlagsDerivesDefaultHealthURLs verifies local dependency health defaults.
func TestFromFlagsDerivesDefaultHealthURLs(t *testing.T) {
	cfg, err := FromFlags([]string{
		"--harness-base-url", "http://127.0.0.1:8080/api",
		"--memory-mcp-url", "http://127.0.0.1:8090/mcp",
		"--app-name", "pilot",
		"--user-id", "doug",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.HarnessService.HealthURL != "http://127.0.0.1:8080/api/apps/pilot/users/doug/sessions" {
		t.Fatalf("harness health = %q", cfg.HarnessService.HealthURL)
	}
	if cfg.MemoryService.HealthURL != "http://127.0.0.1:8090/healthz" {
		t.Fatalf("memory health = %q", cfg.MemoryService.HealthURL)
	}
}

// TestValidateRequiresAutoStartCommand verifies auto-start cannot be commandless.
func TestValidateRequiresAutoStartCommand(t *testing.T) {
	_, err := FromFlags([]string{"--harness-auto-start"})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want command validation error")
	}
}
