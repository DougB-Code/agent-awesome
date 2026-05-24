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
	if got, want := DefaultToolPath(), filepath.Join(configHome, "agent-awesome", "tools", "default", "tool.yaml"); got != want {
		t.Fatalf("DefaultToolPath() = %q, want %q", got, want)
	}
	if got, want := DefaultMCPConfigDir(), filepath.Join(configHome, "agent-awesome", "mcp"); got != want {
		t.Fatalf("DefaultMCPConfigDir() = %q, want %q", got, want)
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

// TestLoadModelConfigAcceptsLocalRuntimeMetadata verifies UI-owned local model metadata is ignored by harness adapters.
func TestLoadModelConfigAcceptsLocalRuntimeMetadata(t *testing.T) {
	path := writeTempFile(t, "model.yaml", `
default: litert-lm:gemma-4-e2b-it
providers:
  litert-lm:
    name: LiteRT-LM
    adapter: openai
    auth: optional
    runtime: litert-lm
    url: http://127.0.0.1:11666/v1/chat/completions
    default: gemma-4-e2b-it
    executable: /tmp/litert-lm
    hf-repo: google/gemma
    models:
      - id: gemma-4-e2b-it
        model: gemma-4-E2B-it
        path: /tmp/gemma-4-E2B-it.litertlm
`)

	cfg, err := LoadModel(path)
	if err != nil {
		t.Fatalf("LoadModel() error = %v", err)
	}
	selection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	if got, want := selection.Provider.Runtime, "litert-lm"; got != want {
		t.Fatalf("Runtime = %q, want %q", got, want)
	}
	if got, want := selection.Provider.HFRepo, "google/gemma"; got != want {
		t.Fatalf("HFRepo = %q, want %q", got, want)
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
	if err := os.MkdirAll(filepath.Dir(DefaultToolPath()), 0o700); err != nil {
		t.Fatalf("MkdirAll(tool package) error = %v", err)
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

func TestLoadToolsMergesMCPPackageConfigs(t *testing.T) {
	root := t.TempDir()
	toolPath := filepath.Join(root, "tools", "agent-awesome", "tool.yaml")
	mcpPath := filepath.Join(root, "mcp", "memory", "mcp.yaml")
	if err := os.MkdirAll(filepath.Dir(toolPath), 0o700); err != nil {
		t.Fatalf("MkdirAll(tool package) error = %v", err)
	}
	if err := os.MkdirAll(filepath.Dir(mcpPath), 0o700); err != nil {
		t.Fatalf("MkdirAll(mcp package) error = %v", err)
	}
	writeFile(t, toolPath, `
local-exec:
  enabled: false
`)
	writeFile(t, mcpPath, `
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
`)

	cfg, err := LoadTools(toolPath, true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if !cfg.MCP.Enabled {
		t.Fatalf("MCP.Enabled = false, want true")
	}
	if got, want := len(cfg.MCP.Servers), 1; got != want {
		t.Fatalf("len(MCP.Servers) = %d, want %d", got, want)
	}
	if got, want := cfg.MCP.Servers[0].Name, "memory"; got != want {
		t.Fatalf("MCP server name = %q, want %q", got, want)
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
`)

	cfg, err := LoadTools(path, true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if !cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = false, want true")
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
		"upsert_codebase",
		"get_codebase",
		"list_codebases",
		"resolve_codebase",
		"delete_codebase",
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
		"upsert_codebase",
		"complete_task",
		"cancel_task",
		"delete_task",
		"delete_codebase",
		"link_task_memory",
		"upsert_task_relation",
		"delete_task_relation",
	}
	root := repoRoot(t)
	paths := []string{
		filepath.Join(root, "harness", "tool.local.yaml"),
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

// TestBrowserPilotToolConfigConstrainsAgentBrowser verifies the opt-in browser
// pilot keeps local execution reviewed and domain-scoped.
func TestBrowserPilotToolConfigConstrainsAgentBrowser(t *testing.T) {
	cfg, err := LoadTools(filepath.Join(repoRoot(t), "harness", "tool.browser-pilot.yaml"), true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if !cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = false, want browser pilot enabled")
	}

	var browserCommand schema.LocalExecCommand
	for _, command := range cfg.LocalExec.Commands {
		if command.Name == "agent_browser_example_research" {
			browserCommand = command
			break
		}
	}
	if browserCommand.Name == "" {
		t.Fatalf("agent_browser_example_research command not configured")
	}
	if browserCommand.Executable != "/usr/bin/env" {
		t.Fatalf("Executable = %q, want /usr/bin/env", browserCommand.Executable)
	}
	expectedArgs := []string{
		"HOME=/home/doug/dev/agentawesome/agent/build/agent-browser/home",
		"AGENT_BROWSER_SESSION=aaex",
		"/home/doug/dev/agentawesome/tools/bin/agent-browser",
		"--allowed-domains",
		"example.com",
		"--max-output",
		"20000",
		"batch",
		"--json",
		"--bail",
	}
	if !reflect.DeepEqual(browserCommand.Args, expectedArgs) {
		t.Fatalf("Args = %#v, want %#v", browserCommand.Args, expectedArgs)
	}

	var techCrunchCommand schema.LocalExecCommand
	for _, command := range cfg.LocalExec.Commands {
		if command.Name == "agent_browser_techcrunch_research" {
			techCrunchCommand = command
			break
		}
	}
	if techCrunchCommand.Name == "" {
		t.Fatalf("agent_browser_techcrunch_research command not configured")
	}
	expectedTechCrunchArgs := []string{
		"HOME=/home/doug/dev/agentawesome/agent/build/agent-browser/home",
		"AGENT_BROWSER_SESSION=aatc",
		"/home/doug/dev/agentawesome/tools/bin/agent-browser",
		"--allowed-domains",
		"techcrunch.com,*.techcrunch.com",
		"--max-output",
		"30000",
		"batch",
		"--json",
		"--bail",
	}
	if !reflect.DeepEqual(techCrunchCommand.Args, expectedTechCrunchArgs) {
		t.Fatalf("TechCrunch Args = %#v, want %#v", techCrunchCommand.Args, expectedTechCrunchArgs)
	}
}

// TestWorkflowToolConfigExposesWorkflowMCP verifies the workflow MCP server is opt-in.
func TestWorkflowToolConfigExposesWorkflowMCP(t *testing.T) {
	cfg, err := LoadTools(filepath.Join(repoRoot(t), "harness", "tool.workflow.yaml"), true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	server, ok := mcpServerByName(cfg.MCP.Servers, "workflow")
	if !ok {
		t.Fatalf("workflow MCP server not configured")
	}
	if server.Endpoint != "http://127.0.0.1:8092/mcp" {
		t.Fatalf("workflow endpoint = %q, want local workflow MCP", server.Endpoint)
	}
	expectedTools := []string{
		"workflow_list",
		"workflow_describe",
		"workflow_start",
		"workflow_status",
		"workflow_signal",
		"workflow_cancel",
		"workflow_history",
		"workflow_action_types",
		"workflow_draft_create",
		"workflow_draft_update",
		"workflow_draft_validate",
		"workflow_draft_publish",
	}
	if !reflect.DeepEqual(server.Tools.Allow, expectedTools) {
		t.Fatalf("workflow Tools.Allow = %#v, want %#v", server.Tools.Allow, expectedTools)
	}
	if cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = true, want workflow control through MCP only")
	}
	if len(cfg.LocalExec.Commands) != 0 {
		t.Fatalf("LocalExec.Commands = %#v, want workflow profile to expose no direct commands", cfg.LocalExec.Commands)
	}
}

func TestGoToolPackageConfigProvidesVerificationPresets(t *testing.T) {
	cfg, err := LoadTools(filepath.Join(repoRoot(t), "harness", "tool.go.yaml"), true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	if !cfg.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = false, want Go package commands enabled")
	}
	if got, want := len(cfg.LocalExec.Commands), 4; got != want {
		t.Fatalf("LocalExec.Commands length = %d, want %d", got, want)
	}
	expectedCommands := []string{"go_build_all", "go_test_all", "go_build_binary", "binary_execute_two_args"}
	for index, name := range expectedCommands {
		if cfg.LocalExec.Commands[index].Name != name {
			t.Fatalf("Go command preset %d = %q, want %q", index, cfg.LocalExec.Commands[index].Name, name)
		}
	}
	if got, want := len(cfg.NodePresets), 4; got != want {
		t.Fatalf("NodePresets length = %d, want %d", got, want)
	}
	if cfg.NodePresets[0].Action != "command.execute" {
		t.Fatalf("NodePresets[0].Action = %q, want command.execute", cfg.NodePresets[0].Action)
	}
}

func TestProfessionalCodingToolPackageConfigProvidesPilotBoundary(t *testing.T) {
	t.Setenv("SOURCECONTROL_MCP_URL", "http://127.0.0.1:8095/mcp")
	cfg, err := LoadTools(filepath.Join(repoRoot(t), "harness", "tool.professional-coding.yaml"), true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}
	commands := map[string]schema.LocalExecCommand{}
	for _, command := range cfg.LocalExec.Commands {
		commands[command.Name] = command
	}
	for _, name := range []string{"codex_implement", "go_build_all", "go_test_all", "go_build_binary", "binary_execute_two_args"} {
		if _, ok := commands[name]; !ok {
			t.Fatalf("command %q is not configured", name)
		}
	}
	if got, want := cfg.MCP.Servers[0].Name, "sourcecontrol"; got != want {
		t.Fatalf("MCP server = %q, want %q", got, want)
	}
	if got, want := len(cfg.NodePresets), 9; got != want {
		t.Fatalf("NodePresets length = %d, want %d", got, want)
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
	return mcpServerByName(servers, "memory")
}

// mcpServerByName returns one named MCP server from a config server list.
func mcpServerByName(servers []schema.MCPServer, name string) (schema.MCPServer, bool) {
	for _, server := range servers {
		if server.Name == name {
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
