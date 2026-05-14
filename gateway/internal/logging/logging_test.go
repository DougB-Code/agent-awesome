// This file tests gateway log component naming.
package logging

import "testing"

// TestComponentNameUsesLogFile verifies cloud log files identify the binary.
func TestComponentNameUsesLogFile(t *testing.T) {
	t.Setenv(logComponentEnv, "")

	if got := componentName("/app/logs/gateway.log", "gateway"); got != "gateway" {
		t.Fatalf("componentName() = %q, want gateway", got)
	}
}

// TestComponentNameUsesEnvironmentOverride verifies explicit component naming.
func TestComponentNameUsesEnvironmentOverride(t *testing.T) {
	t.Setenv(logComponentEnv, "gateway-canary")

	if got := componentName("/app/logs/gateway.log", "gateway"); got != "gateway-canary" {
		t.Fatalf("componentName() = %q, want env override", got)
	}
}
