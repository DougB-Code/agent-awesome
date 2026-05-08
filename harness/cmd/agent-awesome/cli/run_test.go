package cli

import (
	"context"
	"path/filepath"
	"reflect"
	"testing"

	"agentawesome/internal/app"
)

func TestRunCommandParsesAgentAwesomeFlags(t *testing.T) {
	var captured app.Options
	cmd := newRunCommandWithRunner(context.Background(), func(ctx context.Context, opts app.Options) error {
		captured = opts
		return nil
	})
	cmd.SetArgs([]string{
		"--model", "custom-model.yaml",
		"--agent", "custom-agent.yaml",
		"--tool", "custom-tool.yaml",
		"--provider", "cloudflare",
		"--model-id=kimi-k2",
		"--log-file", "/tmp/harness.log",
		"--context-api-addr", "127.0.0.1:8081",
		"--session-db", "/tmp/agent-sessions.db",
		"console",
		"--input-file", "prompt.txt",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := captured.ModelConfigPath, "custom-model.yaml"; got != want {
		t.Fatalf("ModelConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.AgentConfigPath, "custom-agent.yaml"; got != want {
		t.Fatalf("AgentConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.ToolPath, "custom-tool.yaml"; got != want {
		t.Fatalf("ToolPath = %q, want %q", got, want)
	}
	if !captured.ToolSet {
		t.Fatalf("ToolSet = false, want true")
	}
	if got, want := captured.ProviderName, "cloudflare"; got != want {
		t.Fatalf("providerName = %q, want %q", got, want)
	}
	if got, want := captured.ModelID, "kimi-k2"; got != want {
		t.Fatalf("modelID = %q, want %q", got, want)
	}
	if got, want := captured.LogFilePath, "/tmp/harness.log"; got != want {
		t.Fatalf("LogFilePath = %q, want %q", got, want)
	}
	if got, want := captured.ContextAPIAddr, "127.0.0.1:8081"; got != want {
		t.Fatalf("ContextAPIAddr = %q, want %q", got, want)
	}
	if got, want := captured.SessionDatabase, "/tmp/agent-sessions.db"; got != want {
		t.Fatalf("SessionDatabase = %q, want %q", got, want)
	}
	if want := []string{"console", "--input-file", "prompt.txt"}; !reflect.DeepEqual(captured.Args, want) {
		t.Fatalf("args = %#v, want %#v", captured.Args, want)
	}
}

func TestRunCommandUsesDoubleDashPassthrough(t *testing.T) {
	var captured app.Options
	cmd := newRunCommandWithRunner(context.Background(), func(ctx context.Context, opts app.Options) error {
		captured = opts
		return nil
	})
	cmd.SetArgs([]string{
		"--provider", "cloudflare",
		"--",
		"console",
		"--help",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if want := []string{"console", "--help"}; !reflect.DeepEqual(captured.Args, want) {
		t.Fatalf("args = %#v, want %#v", captured.Args, want)
	}
}

func TestRunCommandUsesExplicitDefaults(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	var captured app.Options
	cmd := newRunCommandWithRunner(context.Background(), func(ctx context.Context, opts app.Options) error {
		captured = opts
		return nil
	})
	cmd.SetArgs([]string{"console"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := captured.ModelConfigPath, filepath.Join(configHome, "agent-awesome", "model.yaml"); got != want {
		t.Fatalf("ModelConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.AgentConfigPath, filepath.Join(configHome, "agent-awesome", "agent.yaml"); got != want {
		t.Fatalf("AgentConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.ToolPath, filepath.Join(configHome, "agent-awesome", "tool.yaml"); got != want {
		t.Fatalf("ToolPath = %q, want %q", got, want)
	}
	if captured.ToolSet {
		t.Fatalf("ToolSet = true, want false")
	}
	if captured.ProviderName != "" {
		t.Fatalf("providerName = %q, want empty", captured.ProviderName)
	}
	if captured.ModelID != "" {
		t.Fatalf("modelID = %q, want empty", captured.ModelID)
	}
}

func TestRunCommandPassesFlagsAfterRuntimeArgsThrough(t *testing.T) {
	var captured app.Options
	cmd := newRunCommandWithRunner(context.Background(), func(ctx context.Context, opts app.Options) error {
		captured = opts
		return nil
	})
	cmd.SetArgs([]string{"console", "--provider", "cloudflare"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if captured.ProviderName != "" {
		t.Fatalf("providerName = %q, want empty", captured.ProviderName)
	}
	if want := []string{"console", "--provider", "cloudflare"}; !reflect.DeepEqual(captured.Args, want) {
		t.Fatalf("args = %#v, want %#v", captured.Args, want)
	}
}

func TestRunCommandUsesExpectedConfigPathFlags(t *testing.T) {
	var captured app.Options
	cmd := newRunCommandWithRunner(context.Background(), func(ctx context.Context, opts app.Options) error {
		captured = opts
		return nil
	})
	cmd.SetArgs([]string{
		"--model", "./harness/model.yaml",
		"--tool", "./harness/tool.yaml",
		"--agent", "./harness/agent.yaml",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := captured.ModelConfigPath, "./harness/model.yaml"; got != want {
		t.Fatalf("ModelConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.ToolPath, "./harness/tool.yaml"; got != want {
		t.Fatalf("ToolPath = %q, want %q", got, want)
	}
	if got, want := captured.AgentConfigPath, "./harness/agent.yaml"; got != want {
		t.Fatalf("AgentConfigPath = %q, want %q", got, want)
	}
}
