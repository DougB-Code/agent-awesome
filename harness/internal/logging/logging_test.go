// This file tests harness log component naming.
package logging

import "testing"

// TestComponentNameUsesLogFile verifies cloud log files identify each harness.
func TestComponentNameUsesLogFile(t *testing.T) {
	t.Setenv(logComponentEnv, "")

	if got := componentName("/app/logs/harness-doug.log", "harness"); got != "harness-doug" {
		t.Fatalf("componentName() = %q, want harness-doug", got)
	}
}

// TestComponentNameUsesEnvironmentOverride verifies explicit component naming.
func TestComponentNameUsesEnvironmentOverride(t *testing.T) {
	t.Setenv(logComponentEnv, "harness-canary")

	if got := componentName("/app/logs/harness-doug.log", "harness"); got != "harness-canary" {
		t.Fatalf("componentName() = %q, want env override", got)
	}
}
