// This file tests configuration loading and schema validation.
package config

import (
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"testing"

	"agentawesome/internal/config/schema"
)

func TestDefaultConfigPathsUseOSConfigDir(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)

	if got, want := DefaultConfigDir(), filepath.Join(configHome, "agent-awesome"); got != want {
		t.Fatalf("DefaultConfigDir() = %q, want %q", got, want)
	}
	if got, want := DefaultModelPath(), filepath.Join(configHome, "agent-awesome", "model.yaml"); got != want {
		t.Fatalf("DefaultModelPath() = %q, want %q", got, want)
	}
	if got, want := DefaultAgentPath(), filepath.Join(configHome, "agent-awesome", "agent.yaml"); got != want {
		t.Fatalf("DefaultAgentPath() = %q, want %q", got, want)
	}
	if got, want := DefaultToolPath(), filepath.Join(configHome, "agent-awesome", "tool.yaml"); got != want {
		t.Fatalf("DefaultToolPath() = %q, want %q", got, want)
	}
}

func TestLoadModelUsesDefaultOSConfigPath(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	if err := os.MkdirAll(DefaultConfigDir(), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	writeFile(t, DefaultModelPath(), `
default: cloudflare-gateway:example
providers:
  cloudflare-gateway:
    adapter: openai
    api-key: CLOUDFLARE_API_KEY
    url: https://example.test/v1/chat/completions
    models:
      - id: example
        model: workers-ai/model
        capabilities:
          streaming: true
`)

	cfg, err := LoadModel("")
	if err != nil {
		t.Fatalf("LoadModel() error = %v", err)
	}
	if cfg.Default != "cloudflare-gateway:example" {
		t.Fatalf("Default = %q, want cloudflare-gateway:example", cfg.Default)
	}
}

func TestLoadAgentUsesDefaultOSConfigPath(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	if err := os.MkdirAll(DefaultConfigDir(), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	writeFile(t, DefaultAgentPath(), `
name: test_agent
description: Test agent.
instruction: Be helpful.
`)

	agent, err := LoadAgent("")
	if err != nil {
		t.Fatalf("LoadAgent() error = %v", err)
	}
	if got, want := agent.Name, "test_agent"; got != want {
		t.Fatalf("agent.Name = %q, want %q", got, want)
	}
}

func TestProviderSelectionAdapterUsesProviderAdapter(t *testing.T) {
	selection := schema.ProviderSelection{
		Provider: schema.Provider{Adapter: "openai"},
		Model:    schema.Model{},
	}

	if got, want := selection.Adapter(), "openai"; got != want {
		t.Fatalf("Adapter() = %q, want %q", got, want)
	}
}

func TestProviderSelectionModelNameUsesConfiguredModel(t *testing.T) {
	selection := schema.ProviderSelection{
		Model: schema.Model{
			ID:    "kimi",
			Model: "workers-ai/@cf/moonshotai/kimi-k2.6",
		},
	}

	if got, want := selection.ModelName(), "workers-ai/@cf/moonshotai/kimi-k2.6"; got != want {
		t.Fatalf("ModelName() = %q, want %q", got, want)
	}
}

func TestLoadModelConfig(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: cloudflare-gateway:example
providers:
  cloudflare-gateway:
    name: Cloudflare Gateway
    adapter: openai
    api-key: CLOUDFLARE_API_KEY
    url: https://example.test/v1/chat/completions
    models:
      - id: example
        model: workers-ai/model
        capabilities:
          streaming: true
`)

	cfg, err := LoadModel(path)
	if err != nil {
		t.Fatalf("LoadModel() error = %v", err)
	}

	selection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	if got, want := selection.Name, "cloudflare-gateway"; got != want {
		t.Fatalf("selection.Name = %q, want %q", got, want)
	}
	if got, want := selection.Provider.Name, "Cloudflare Gateway"; got != want {
		t.Fatalf("selection.Provider.Name = %q, want %q", got, want)
	}
	if got, want := selection.Provider.Adapter, "openai"; got != want {
		t.Fatalf("selection.Provider.Adapter = %q, want %q", got, want)
	}
	if got, want := selection.Provider.AuthMode(), ""; got != want {
		t.Fatalf("selection.Provider.AuthMode() = %q, want %q", got, want)
	}
	if got, want := selection.Model.ID, "example"; got != want {
		t.Fatalf("selection.Model.ID = %q, want %q", got, want)
	}
	if got, want := selection.ModelName(), "workers-ai/model"; got != want {
		t.Fatalf("selection.ModelName() = %q, want %q", got, want)
	}
	if !selection.Model.Capabilities.Streaming {
		t.Fatalf("selection.Model.Capabilities.Streaming = false, want true")
	}
}

// TestLoadModelConfigAcceptsProviderAuth verifies the auth enum is decoded.
func TestLoadModelConfigAcceptsProviderAuth(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: local:example
providers:
  local:
    adapter: openai
    auth: optional
    url: http://127.0.0.1:11434/v1/chat/completions
    models:
      - id: example
        model: local/model
`)

	cfg, err := LoadModel(path)
	if err != nil {
		t.Fatalf("LoadModel() error = %v", err)
	}
	selection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	if got, want := selection.Provider.AuthMode(), schema.ProviderAuthOptional; got != want {
		t.Fatalf("AuthMode() = %q, want %q", got, want)
	}
}

// TestLoadModelRejectsInvalidProviderAuth verifies invalid auth policy fails.
func TestLoadModelRejectsInvalidProviderAuth(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: local:example
providers:
  local:
    adapter: openai
    auth: anonymous
    url: http://127.0.0.1:11434/v1/chat/completions
    models:
      - id: example
        model: local/model
`)

	if _, err := LoadModel(path); err == nil {
		t.Fatalf("LoadModel() error = nil, want auth validation error")
	}
}

func TestLoadAgentConfig(t *testing.T) {
	path := writeTempFile(t, "agent.yaml", `
name: test_agent
description: Test agent.
instruction: Be helpful.
`)

	agent, err := LoadAgent(path)
	if err != nil {
		t.Fatalf("LoadAgent() error = %v", err)
	}
	if got, want := agent.Name, "test_agent"; got != want {
		t.Fatalf("agent.Name = %q, want %q", got, want)
	}
	if got, want := agent.Description, "Test agent."; got != want {
		t.Fatalf("agent.Description = %q, want %q", got, want)
	}
	if got, want := agent.Instruction, "Be helpful."; got != want {
		t.Fatalf("agent.Instruction = %q, want %q", got, want)
	}
}

func TestLoadToolsDefaultMissingReturnsEmptyConfig(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)

	cfg, err := LoadTools("", false)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if cfg == nil {
		t.Fatalf("LoadTools() = nil")
	}
	if cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = true, want false")
	}
}

func TestLoadToolsUsesDefaultOSConfigPath(t *testing.T) {
	configHome := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configHome)
	if err := os.MkdirAll(DefaultConfigDir(), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	writeFile(t, DefaultToolPath(), `
local-exec:
  enabled: false
`)

	cfg, err := LoadTools("", false)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = true, want false")
	}
}

func TestLoadToolsExplicitMissingFails(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing-tool.yaml")
	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want missing file error")
	}
}

func TestLoadToolsConfig(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  allow-persistent-approvals: true
  default-timeout: 10s
  default-max-output-bytes: 1024
  allowed-workdirs:
    - .
  commands:
    - name: git_status
      executable: git
      description: Show repository status.
      args:
        - status
        - --short
      timeout: 2s
      max-output-bytes: 2048
      approval:
        always-allow-within-workspace: true
        always-allow-command-starts-with:
          - git status
        always-allow: false
`)

	cfg, err := LoadTools(path, true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if !cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = false, want true")
	}
	if !cfg.LocalExec.AllowPersistentApprovals {
		t.Fatalf("AllowPersistentApprovals = false, want true")
	}
	if !cfg.LocalExec.Commands[0].Approval.AlwaysAllowWithinWorkspace {
		t.Fatalf("AlwaysAllowWithinWorkspace = false, want true")
	}
	if got, want := cfg.LocalExec.Commands[0].Approval.AlwaysAllowCommandPrefixes, []string{"git status"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("AlwaysAllowCommandPrefixes = %#v, want %#v", got, want)
	}
	if cfg.LocalExec.Commands[0].Approval.AlwaysAllow {
		t.Fatalf("AlwaysAllow = true, want false")
	}
	if got, want := cfg.LocalExec.DefaultTimeoutDuration().String(), "10s"; got != want {
		t.Fatalf("DefaultTimeoutDuration() = %q, want %q", got, want)
	}
	if got, want := cfg.LocalExec.DefaultOutputLimit(), 1024; got != want {
		t.Fatalf("DefaultOutputLimit() = %d, want %d", got, want)
	}
	if len(cfg.LocalExec.Commands) != 1 || cfg.LocalExec.Commands[0].Name != "git_status" {
		t.Fatalf("Commands = %#v, want git_status", cfg.LocalExec.Commands)
	}
	if got, want := cfg.LocalExec.Commands[0].Timeout, "2s"; got != want {
		t.Fatalf("command Timeout = %q, want %q", got, want)
	}
	if got, want := cfg.LocalExec.Commands[0].MaxOutputBytes, 2048; got != want {
		t.Fatalf("command MaxOutputBytes = %d, want %d", got, want)
	}
}

func TestLoadToolsMCPConfig(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
mcp:
  enabled: true
  servers:
    - name: filesystem
      transport: stdio
      command: npx
      args:
        - -y
        - "@modelcontextprotocol/server-filesystem"
        - /tmp
      require-confirmation: true
      tools:
        allow:
          - read_file
          - list_directory
    - name: remote
      transport: http
      endpoint: https://example.test/mcp
      require-confirmation-tools:
        - delete_item
`)

	cfg, err := LoadTools(path, true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if !cfg.MCP.Enabled {
		t.Fatalf("MCP.Enabled = false, want true")
	}
	if got, want := len(cfg.MCP.Servers), 2; got != want {
		t.Fatalf("len(MCP.Servers) = %d, want %d", got, want)
	}
	if !cfg.MCP.Servers[0].RequireConfirmation {
		t.Fatalf("RequireConfirmation = false, want true")
	}
	if got, want := cfg.MCP.Servers[0].Tools.Allow, []string{"read_file", "list_directory"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("Tools.Allow = %#v, want %#v", got, want)
	}
	if got, want := cfg.MCP.Servers[1].RequireConfirmationTools, []string{"delete_item"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("RequireConfirmationTools = %#v, want %#v", got, want)
	}
}

// TestStaticGraphBackedMemoryToolConfigsMatchConfirmationPolicy keeps shipped
// tool configs aligned with the UI-generated graph-backed memory config.
func TestStaticGraphBackedMemoryToolConfigsMatchConfirmationPolicy(t *testing.T) {
	expectedAllow := []string{
		"remember",
		"save_memory_candidate",
		"search_memory",
		"search_sources",
		"load_entity_page",
		"load_timeline",
		"refresh_compiled_page",
		"repair_memory_record",
		"submit_memory_correction",
		"query_context_graph",
		"mutate_context_graph",
		"create_task",
		"get_task",
		"list_tasks",
		"task_graph_projection",
		"project_executive_summary",
		"explain_executive_summary_item",
		"update_task",
		"complete_task",
		"cancel_task",
		"delete_task",
		"link_task_memory",
		"list_task_relations",
		"traverse_task_relations",
		"upsert_task_relation",
		"delete_task_relation",
	}
	expectedConfirmations := []string{
		"remember",
		"save_memory_candidate",
		"refresh_compiled_page",
		"repair_memory_record",
		"submit_memory_correction",
		"query_context_graph",
		"mutate_context_graph",
		"create_task",
		"update_task",
		"complete_task",
		"cancel_task",
		"delete_task",
		"link_task_memory",
		"upsert_task_relation",
		"delete_task_relation",
	}
	root := repoRoot(t)
	paths := []string{
		filepath.Join(root, "harness", "tool.local.yaml"),
		filepath.Join(root, "harness", "tool.cloudflare.yaml"),
		filepath.Join(root, "deploy", "cloudflare", "config", "tool.yaml"),
		filepath.Join(root, "deploy", "cloudflare", "config", "tool.doug.yaml"),
		filepath.Join(root, "deploy", "cloudflare", "config", "tool.family.yaml"),
	}

	for _, path := range paths {
		t.Run(filepath.ToSlash(path), func(t *testing.T) {
			cfg, err := LoadTools(path, true)
			if err != nil {
				t.Fatalf("LoadTools() error = %v", err)
			}
			if cfg.LocalExec.Enabled {
				t.Fatalf("LocalExec.Enabled = true, want shipped configs disabled by default")
			}
			if cfg.LocalExec.AllowPersistentApprovals {
				t.Fatalf("AllowPersistentApprovals = true, want shipped configs disabled by default")
			}
			server, ok := memoryMCPServer(cfg.MCP.Servers)
			if !ok {
				t.Fatalf("memory MCP server not configured")
			}
			if got := server.Tools.Allow; !reflect.DeepEqual(got, expectedAllow) {
				t.Fatalf("Tools.Allow = %#v, want %#v", got, expectedAllow)
			}
			if got := server.RequireConfirmationTools; !reflect.DeepEqual(got, expectedConfirmations) {
				t.Fatalf("RequireConfirmationTools = %#v, want %#v", got, expectedConfirmations)
			}
			if allowsTool(server, "query_context_graph") && !requiresConfirmation(server, "query_context_graph") {
				t.Fatalf("query_context_graph is allowed without confirmation")
			}
			if allowsTool(server, "mutate_context_graph") && !requiresConfirmation(server, "mutate_context_graph") {
				t.Fatalf("mutate_context_graph is allowed without confirmation")
			}
		})
	}
}

// TestStaticSlackMemoryToolConfigsAreReadOnly keeps Slack from seeing writes.
func TestStaticSlackMemoryToolConfigsAreReadOnly(t *testing.T) {
	expectedAllow := []string{
		"search_memory",
		"search_sources",
		"load_entity_page",
		"load_timeline",
		"query_context_graph",
		"get_task",
		"list_tasks",
		"task_graph_projection",
		"project_executive_summary",
		"explain_executive_summary_item",
		"list_task_relations",
		"traverse_task_relations",
	}
	root := repoRoot(t)
	paths := []string{
		filepath.Join(root, "deploy", "cloudflare", "config", "tool.slack.doug.yaml"),
		filepath.Join(root, "deploy", "cloudflare", "config", "tool.slack.family.yaml"),
	}

	for _, path := range paths {
		t.Run(filepath.ToSlash(path), func(t *testing.T) {
			cfg, err := LoadTools(path, true)
			if err != nil {
				t.Fatalf("LoadTools() error = %v", err)
			}
			server, ok := memoryMCPServer(cfg.MCP.Servers)
			if !ok {
				t.Fatalf("memory MCP server not configured")
			}
			if got := server.Tools.Allow; !reflect.DeepEqual(got, expectedAllow) {
				t.Fatalf("Tools.Allow = %#v, want read-only tools %#v", got, expectedAllow)
			}
			if len(server.RequireConfirmationTools) != 0 || server.RequireConfirmation {
				t.Fatalf("Slack config requires confirmation: all=%v tools=%#v", server.RequireConfirmation, server.RequireConfirmationTools)
			}
			if len(cfg.Memory.ReadDomains) != 0 {
				t.Fatalf("Slack config enabled runtime memory capture: %#v", cfg.Memory.ReadDomains)
			}
			for _, tool := range []string{"remember", "save_memory_candidate", "create_task", "update_task", "mutate_context_graph"} {
				if allowsTool(server, tool) {
					t.Fatalf("Slack config allows write tool %q", tool)
				}
			}
		})
	}
}

func TestLoadToolsRejectsUnknownFields(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: false
unexpected: value
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want validation error")
	}
}

func TestLoadToolsRejectsMCPMissingServers(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
mcp:
  enabled: true
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want missing servers error")
	}
}

func TestLoadToolsRejectsMCPFilesystemRelativeRoot(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
mcp:
  enabled: true
  servers:
    - name: filesystem
      transport: stdio
      command: npx
      args:
        - -y
        - "@modelcontextprotocol/server-filesystem"
        - .
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want relative filesystem root error")
	}
}

func TestLoadToolsRejectsMCPInvalidHTTPURL(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
mcp:
  enabled: true
  servers:
    - name: remote
      transport: streamable-http
      endpoint: localhost:8080/mcp
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want invalid endpoint error")
	}
}

func TestLoadToolsRejectsMemoryFlowToUnwritableDomain(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
memory:
  actor: agent:test
  read-domains:
    - id: memory
      endpoint: http://127.0.0.1:8070/mcp
    - id: side_project
      endpoint: http://127.0.0.1:8071/mcp
  write-domains:
    - side_project
  default-write-domain: side_project
  allowed-sensitivities:
    - public
    - internal
    - private
  allowed-flows:
    - from: side_project
      to: memory
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want unwritable flow target error")
	}
}

func TestLoadToolsRejectsMCPConfirmationModesCombined(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
mcp:
  enabled: true
  servers:
    - name: remote
      transport: streamable-http
      endpoint: https://example.test/mcp
      require-confirmation: true
      require-confirmation-tools:
        - delete_item
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want confirmation mode error")
	}
}

func TestLoadToolsRejectsEmptyApprovalPrefix(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  commands:
    - name: git_status
      executable: git
      description: Show status.
      approval:
        always-allow-command-starts-with:
          - ""
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want empty approval prefix error")
	}
}

func TestLoadToolsRejectsDuplicateCommands(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  commands:
    - name: same
      executable: git
      description: One.
    - name: same
      executable: git
      description: Two.
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want duplicate command error")
	}
}

func TestLoadToolsRejectsInvalidDuration(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  default-timeout: forever
  commands:
    - name: git_status
      executable: git
      description: Show status.
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want invalid duration error")
	}
}

func TestLoadToolsRejectsInvalidCommandDuration(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  commands:
    - name: git_status
      executable: git
      description: Show status.
      timeout: forever
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want invalid command duration error")
	}
}

func TestLoadToolsRejectsNegativeCommandMaxOutputBytes(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  commands:
    - name: git_status
      executable: git
      description: Show status.
      max-output-bytes: -1
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want invalid command max-output-bytes error")
	}
}

func TestLoadToolsRejectsDisabledConfirmation(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  require-confirmation: false
  commands:
    - name: git_status
      executable: git
      description: Show status.
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want confirmation error")
	}
}

func TestLoadToolsRejectsRemovedWorkdirField(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  workdir: .
  commands:
    - name: git_status
      executable: git
      description: Show status.
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want unknown workdir field error")
	}
}

func TestLoadToolsRejectsEmptyAllowedWorkdir(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  allowed-workdirs:
    - ""
  commands:
    - name: git_status
      executable: git
      description: Show status.
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want empty allowed workdir error")
	}
}

func TestLoadToolsRejectsMissingCommandFields(t *testing.T) {
	path := writeTempFile(t, "tool.yaml", `
local-exec:
  enabled: true
  commands:
    - name: git_status
      description: Show status.
`)

	if _, err := LoadTools(path, true); err == nil {
		t.Fatalf("LoadTools() error = nil, want missing executable error")
	}
}

func TestResolveExplicitProviderUsesProviderDefault(t *testing.T) {
	cfg := &schema.ModelConfig{
		Default: "google:flash",
		Providers: map[string]schema.Provider{
			"google": {
				Adapter: "google",
				Models:  []schema.Model{{ID: "flash", Model: "gemini-flash"}},
			},
			"cloudflare": {
				Adapter: "openai",
				Default: "kimi",
				URL:     "https://example.test/v1/chat/completions",
				Models: []schema.Model{
					{ID: "gemma", Model: "workers-ai/gemma"},
					{ID: "kimi", Model: "workers-ai/kimi"},
				},
			},
		},
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate() error = %v", err)
	}

	selection, err := cfg.ResolveProvider("cloudflare", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	if got, want := selection.Model.ID, "kimi"; got != want {
		t.Fatalf("selection.Model.ID = %q, want %q", got, want)
	}
}

func TestResolveExplicitProviderWithoutDefaultRequiresModel(t *testing.T) {
	cfg := &schema.ModelConfig{
		Default: "google:flash",
		Providers: map[string]schema.Provider{
			"google": {
				Adapter: "google",
				Models:  []schema.Model{{ID: "flash", Model: "gemini-flash"}},
			},
			"cloudflare": {
				Adapter: "openai",
				URL:     "https://example.test/v1/chat/completions",
				Models:  []schema.Model{{ID: "kimi", Model: "workers-ai/kimi"}},
			},
		},
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("Validate() error = %v", err)
	}

	if _, err := cfg.ResolveProvider("cloudflare", ""); err == nil {
		t.Fatalf("ResolveProvider() error = nil, want model requirement error")
	}
}

func TestLoadModelRejectsDefaultWithoutModel(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: cloudflare-gateway
providers:
  cloudflare-gateway:
    adapter: openai
    models:
      - id: example
        model: workers-ai/model
`)

	if _, err := LoadModel(path); err == nil {
		t.Fatalf("LoadModel() error = nil, want validation error")
	}
}

func TestLoadModelAllowsAdapterSpecificValidationElsewhere(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: example:model
providers:
  example:
    adapter: imaginary
    models:
      - id: model
        model: provider/model
`)

	if _, err := LoadModel(path); err != nil {
		t.Fatalf("LoadModel() error = %v", err)
	}
}

func TestLoadModelRejectsDuplicateModelIDs(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: example:model
providers:
  example:
    adapter: google
    models:
      - id: model
        model: provider/model-a
      - id: model
        model: provider/model-b
`)

	if _, err := LoadModel(path); err == nil {
		t.Fatalf("LoadModel() error = nil, want validation error")
	}
}

func TestLoadModelRejectsUnknownFields(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: example:model
providers:
  example:
    adapter: google
    unexpected: value
    models:
      - id: model
        model: provider/model
`)

	if _, err := LoadModel(path); err == nil {
		t.Fatalf("LoadModel() error = nil, want validation error")
	}
}

func TestLoadModelRejectsAgentFields(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
agent:
  name: test_agent
default: example:model
providers:
  example:
    adapter: google
    models:
      - id: model
        model: provider/model
`)

	if _, err := LoadModel(path); err == nil {
		t.Fatalf("LoadModel() error = nil, want validation error")
	}
}

func TestLoadAgentRejectsModelFields(t *testing.T) {
	path := writeTempFile(t, "agent.yaml", `
name: test_agent
instruction: Be helpful.
default: example:model
providers: {}
`)

	if _, err := LoadAgent(path); err == nil {
		t.Fatalf("LoadAgent() error = nil, want validation error")
	}
}

func TestLoadAgentRejectsMissingName(t *testing.T) {
	path := writeTempFile(t, "agent.yaml", `
instruction: Be helpful.
`)

	if _, err := LoadAgent(path); err == nil {
		t.Fatalf("LoadAgent() error = nil, want validation error")
	}
}

func TestLoadAgentRejectsMissingInstruction(t *testing.T) {
	path := writeTempFile(t, "agent.yaml", `
name: test_agent
`)

	if _, err := LoadAgent(path); err == nil {
		t.Fatalf("LoadAgent() error = nil, want validation error")
	}
}

func TestLoadModelRejectsDefaultUnknownModel(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: cloudflare-gateway:missing
providers:
  cloudflare-gateway:
    adapter: openai
    models:
      - id: example
        model: workers-ai/model
`)

	if _, err := LoadModel(path); err == nil {
		t.Fatalf("LoadModel() error = nil, want validation error")
	}
}

func writeTempFile(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	writeFile(t, path, content)
	return path
}

// repoRoot returns the repository root for static fixture tests.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller() failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", ".."))
}

// memoryMCPServer returns the memory MCP server from a config server list.
func memoryMCPServer(servers []schema.MCPServer) (schema.MCPServer, bool) {
	for _, server := range servers {
		if server.Name == "memory" {
			return server, true
		}
	}
	return schema.MCPServer{}, false
}

// allowsTool reports whether an MCP server allowlist includes a tool.
func allowsTool(server schema.MCPServer, tool string) bool {
	return containsString(server.Tools.Allow, tool)
}

// requiresConfirmation reports whether an MCP server confirmation list includes a tool.
func requiresConfirmation(server schema.MCPServer, tool string) bool {
	return containsString(server.RequireConfirmationTools, tool)
}

// containsString reports whether values contains target.
func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
