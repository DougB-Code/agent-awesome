// This file tests memory service log component naming.
package logging

import "testing"

// TestComponentNameUsesLogFile verifies cloud log files identify each memoryd.
func TestComponentNameUsesLogFile(t *testing.T) {
	t.Setenv(logComponentEnv, "")

	if got := componentName("/app/logs/memory-family.log", "memory"); got != "memory-family" {
		t.Fatalf("componentName() = %q, want memory-family", got)
	}
}

// TestComponentNameUsesEnvironmentOverride verifies explicit component naming.
func TestComponentNameUsesEnvironmentOverride(t *testing.T) {
	t.Setenv(logComponentEnv, "memory-canary")

	if got := componentName("/app/logs/memory-family.log", "memory"); got != "memory-canary" {
		t.Fatalf("componentName() = %q, want env override", got)
	}
}
