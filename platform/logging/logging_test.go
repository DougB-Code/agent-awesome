// This file tests shared log configuration helpers.
package logging

import "testing"

// TestComponentNameUsesLogFile verifies log files identify service instances.
func TestComponentNameUsesLogFile(t *testing.T) {
	t.Setenv(logComponentEnv, "")

	if got := componentName("/app/logs/harness-doug.log", "harness"); got != "harness-doug" {
		t.Fatalf("componentName() = %q, want harness-doug", got)
	}
}

// TestComponentNameUsesEnvironmentOverride verifies explicit component naming.
func TestComponentNameUsesEnvironmentOverride(t *testing.T) {
	t.Setenv(logComponentEnv, "memory-canary")

	if got := componentName("/app/logs/memory-family.log", "memory"); got != "memory-canary" {
		t.Fatalf("componentName() = %q, want env override", got)
	}
}

// TestSelectedFormatKeepsServiceDefault verifies unknown values use defaults.
func TestSelectedFormatKeepsServiceDefault(t *testing.T) {
	t.Setenv(logFormatEnv, "unexpected")

	if got := selectedFormat(Options{DefaultFormat: FormatText}); got != FormatText {
		t.Fatalf("selectedFormat() = %q, want text", got)
	}
	if got := selectedFormat(Options{DefaultFormat: FormatJSON}); got != FormatJSON {
		t.Fatalf("selectedFormat() = %q, want json", got)
	}
}
