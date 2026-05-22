package cli

import (
	"context"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

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
		"--context-api-token", "context-secret",
		"--session-db", "/tmp/agent-sessions.db",
		"--workflow-api-addr", "127.0.0.1:8092",
		"--workflow-definitions", "/tmp/workflows",
		"--workflow-db", "/tmp/workflow.db",
		"--command-data-dir", "/tmp/command-data",
		"--command-allow-workdir", "/work/a",
		"--command-allow-workdir", "/work/b",
		"--command-allow-env", "PATH",
		"--command-allow-env", "HOME",
		"--command-templates-json", `[{"id":"status","executable":"git","args":["status"]}]`,
		"--command-parser-dir", "/tmp/parsers",
		"--command-timeout", "7s",
		"--command-max-output-bytes", "2048",
		"web",
		"--port", "9090",
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
	if got, want := captured.ContextAPIToken, "context-secret"; got != want {
		t.Fatalf("ContextAPIToken = %q, want %q", got, want)
	}
	if got, want := captured.SessionDatabase, "/tmp/agent-sessions.db"; got != want {
		t.Fatalf("SessionDatabase = %q, want %q", got, want)
	}
	if got, want := captured.WorkflowAPIAddr, "127.0.0.1:8092"; got != want {
		t.Fatalf("WorkflowAPIAddr = %q, want %q", got, want)
	}
	if got, want := captured.WorkflowDefinitionsDir, "/tmp/workflows"; got != want {
		t.Fatalf("WorkflowDefinitionsDir = %q, want %q", got, want)
	}
	if got, want := captured.WorkflowDatabasePath, "/tmp/workflow.db"; got != want {
		t.Fatalf("WorkflowDatabasePath = %q, want %q", got, want)
	}
	if got, want := captured.CommandDataDir, "/tmp/command-data"; got != want {
		t.Fatalf("CommandDataDir = %q, want %q", got, want)
	}
	if want := []string{"/work/a", "/work/b"}; !reflect.DeepEqual(captured.CommandAllowedWorkdirs, want) {
		t.Fatalf("CommandAllowedWorkdirs = %#v, want %#v", captured.CommandAllowedWorkdirs, want)
	}
	if want := []string{"PATH", "HOME"}; !reflect.DeepEqual(captured.CommandAllowedEnv, want) {
		t.Fatalf("CommandAllowedEnv = %#v, want %#v", captured.CommandAllowedEnv, want)
	}
	if got, want := captured.CommandTemplatesJSON, `[{"id":"status","executable":"git","args":["status"]}]`; got != want {
		t.Fatalf("CommandTemplatesJSON = %q, want %q", got, want)
	}
	if got, want := captured.CommandParserDir, "/tmp/parsers"; got != want {
		t.Fatalf("CommandParserDir = %q, want %q", got, want)
	}
	if got, want := captured.CommandDefaultTimeout, 7*time.Second; got != want {
		t.Fatalf("CommandDefaultTimeout = %s, want %s", got, want)
	}
	if got, want := captured.CommandMaxOutputBytes, int64(2048); got != want {
		t.Fatalf("CommandMaxOutputBytes = %d, want %d", got, want)
	}
	if want := []string{"web", "--port", "9090"}; !reflect.DeepEqual(captured.Args, want) {
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
		"web",
		"--help",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if want := []string{"web", "--help"}; !reflect.DeepEqual(captured.Args, want) {
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
	cmd.SetArgs([]string{"web"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got, want := captured.ModelConfigPath, filepath.Join(configHome, "agent-awesome", "model.yaml"); got != want {
		t.Fatalf("ModelConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.AgentConfigPath, filepath.Join(configHome, "agent-awesome", "agent.yaml"); got != want {
		t.Fatalf("AgentConfigPath = %q, want %q", got, want)
	}
	if got, want := captured.ToolPath, filepath.Join(configHome, "agent-awesome", "tools", "default", "tool.yaml"); got != want {
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
	cmd.SetArgs([]string{"web", "--provider", "cloudflare"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if captured.ProviderName != "" {
		t.Fatalf("providerName = %q, want empty", captured.ProviderName)
	}
	if want := []string{"web", "--provider", "cloudflare"}; !reflect.DeepEqual(captured.Args, want) {
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

func TestRuntimeSyntaxUsesADKRuntimeModes(t *testing.T) {
	syntax := runtimeSyntax()
	for _, want := range []string{
		"web - starts web server",
	} {
		if !strings.Contains(syntax, want) {
			t.Fatalf("runtimeSyntax() = %q, want substring %q", syntax, want)
		}
	}
	for _, unwanted := range []string{
		"Agent Awesome console:",
		"console - runs an agent in Agent Awesome console mode.",
		"-streaming_mode",
	} {
		if strings.Contains(syntax, unwanted) {
			t.Fatalf("runtimeSyntax() = %q, want no substring %q", syntax, unwanted)
		}
	}
}
