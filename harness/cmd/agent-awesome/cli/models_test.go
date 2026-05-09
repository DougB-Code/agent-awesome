// This file tests model validation CLI command parsing.
package cli

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"agentawesome/internal/app"
)

// TestModelsCheckCommandParsesFlagsAndReportsSuccess verifies CLI wiring.
func TestModelsCheckCommandParsesFlagsAndReportsSuccess(t *testing.T) {
	var captured app.ModelCheckOptions
	var stdout bytes.Buffer
	cmd := newModelsCommandWithChecker(context.Background(), &stdout, func(_ context.Context, opts app.ModelCheckOptions) (app.ModelCheckResult, error) {
		captured = opts
		return app.ModelCheckResult{
			ProviderName: "local",
			ModelID:      "mock",
			ModelName:    "mock-model",
			ResponseText: "ok",
		}, nil
	})
	cmd.SetArgs([]string{
		"check",
		"--model", "model.yaml",
		"--provider", "local",
		"--model-id", "mock",
		"--prompt", "ping",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if captured.ModelConfigPath != "model.yaml" || captured.ProviderName != "local" || captured.ModelID != "mock" || captured.Prompt != "ping" {
		t.Fatalf("captured options = %#v, want parsed model check flags", captured)
	}
	if !strings.Contains(stdout.String(), "Model check passed") {
		t.Fatalf("stdout = %q, want success message", stdout.String())
	}
}
