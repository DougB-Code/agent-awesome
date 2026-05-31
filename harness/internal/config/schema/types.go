// This file defines the YAML-backed configuration schema types.
package schema

import "time"

const (
	// AppConfigDirName is the directory name used for Agent Awesome config and
	// keyring service names.
	AppConfigDirName = "agent-awesome"

	// DefaultModelFilename is the model config filename under the config
	// directory.
	DefaultModelFilename = "model.yaml"
	// DefaultAgentFilename is the agent config filename under the config
	// directory.
	DefaultAgentFilename = "agent.yaml"
	// DefaultToolFilename is the tool config filename under the config
	// directory.
	DefaultToolFilename = "tool.yaml"
	// DefaultMCPFilename is the MCP server config filename under one MCP
	// package directory.
	DefaultMCPFilename = "mcp.yaml"
	// DefaultToolConfigDirName is the package directory for installed tools.
	DefaultToolConfigDirName = "tools"
	// DefaultMCPConfigDirName is the package directory for installed MCP servers.
	DefaultMCPConfigDirName = "mcp"

	defaultLocalExecTimeout        = 10 * time.Second
	defaultLocalExecMaxOutputBytes = 65536

	// ProviderAuthRequired means provider startup requires a configured API key.
	ProviderAuthRequired = "required"
	// ProviderAuthOptional means a loopback provider may be used without a key.
	ProviderAuthOptional = "optional"
)

// ModelConfig describes provider and model selection configuration.
type ModelConfig struct {
	Default string `koanf:"default"`
	// Validations stores UI-authored model compatibility checks. Runtime model
	// selection ignores them, but accepting the metadata keeps model packages
	// loadable when the validation editor has authored cases.
	Validations []AgentValidation   `koanf:"validations"`
	Providers   map[string]Provider `koanf:"providers"`
}

// Agent describes the configured agent identity and instructions.
type Agent struct {
	Name        string            `koanf:"name"`
	Description string            `koanf:"description"`
	Instruction string            `koanf:"instruction"`
	Validations []AgentValidation `koanf:"validations"`
}

// AgentValidation describes one portable behavior check for an agent package.
type AgentValidation struct {
	ID          string                `koanf:"id"`
	Label       string                `koanf:"label"`
	Description string                `koanf:"description"`
	Mode        string                `koanf:"mode"`
	Prompt      string                `koanf:"prompt"`
	Input       map[string]any        `koanf:"input"`
	Fixtures    map[string]any        `koanf:"fixtures"`
	Mocks       map[string]any        `koanf:"mocks"`
	Expected    map[string]any        `koanf:"expected"`
	Assertions  []ValidationAssertion `koanf:"assertions"`
}

// Tools describes all configured external tool integrations.
type Tools struct {
	Name        string           `koanf:"name"`
	LocalExec   LocalExec        `koanf:"local-exec"`
	MCP         MCP              `koanf:"mcp"`
	Memory      Memory           `koanf:"memory"`
	NodePresets []NodePreset     `koanf:"node-presets"`
	Validations []ToolValidation `koanf:"validations"`
}

// MCP describes configured Model Context Protocol servers.
type MCP struct {
	Enabled bool        `koanf:"enabled"`
	Servers []MCPServer `koanf:"servers"`
}

// MCPServer describes one MCP server connection.
type MCPServer struct {
	Name                     string            `koanf:"name"`
	Transport                string            `koanf:"transport"`
	Command                  string            `koanf:"command"`
	Args                     []string          `koanf:"args"`
	Env                      map[string]string `koanf:"env"`
	Headers                  map[string]string `koanf:"headers"`
	HeadersFromEnv           map[string]string `koanf:"headers-from-env"`
	Endpoint                 string            `koanf:"endpoint"`
	URL                      string            `koanf:"url"`
	RequireConfirmation      bool              `koanf:"require-confirmation"`
	RequireConfirmationTools []string          `koanf:"require-confirmation-tools"`
	Tools                    MCPToolFilter     `koanf:"tools"`
}

// MCPToolFilter describes allowlisted MCP tool names.
type MCPToolFilter struct {
	Allow []string `koanf:"allow"`
}

// Memory describes runtime memory access across configured domains.
type Memory struct {
	Actor                string         `koanf:"actor"`
	ReadDomains          []MemoryDomain `koanf:"read-domains"`
	WriteDomains         []string       `koanf:"write-domains"`
	DefaultWriteDomain   string         `koanf:"default-write-domain"`
	AllowedSensitivities []string       `koanf:"allowed-sensitivities"`
	AllowedFlows         []MemoryFlow   `koanf:"allowed-flows"`
}

// MemoryDomain describes one memory domain endpoint available to runtime memory.
type MemoryDomain struct {
	ID             string            `koanf:"id"`
	Label          string            `koanf:"label"`
	Endpoint       string            `koanf:"endpoint"`
	HeadersFromEnv map[string]string `koanf:"headers-from-env"`
}

// MemoryFlow allows information to move from one domain into another.
type MemoryFlow struct {
	From string `koanf:"from"`
	To   string `koanf:"to"`
}

// LocalExec describes configured local command execution.
type LocalExec struct {
	Enabled               bool               `koanf:"enabled"`
	DefaultTimeout        string             `koanf:"default-timeout"`
	DefaultMaxOutputBytes int                `koanf:"default-max-output-bytes"`
	Commands              []LocalExecCommand `koanf:"commands"`
}

// LocalExecCommand describes one allowlisted local CLI surface.
type LocalExecCommand struct {
	Name           string             `koanf:"name"`
	Executable     string             `koanf:"executable"`
	Description    string             `koanf:"description"`
	Args           []string           `koanf:"args"`
	Env            map[string]string  `koanf:"env"`
	Timeout        string             `koanf:"timeout"`
	MaxOutputBytes int                `koanf:"max-output-bytes"`
	Installation   ToolInstallation   `koanf:"installation"`
	Surface        CommandSurface     `koanf:"surface"`
	Operations     []CommandOperation `koanf:"operations"`
}

// ToolInstallation records an environment-specific executable availability check.
type ToolInstallation struct {
	Verified   bool   `koanf:"verified"`
	CheckedAt  string `koanf:"checked-at"`
	Executable string `koanf:"executable"`
	Path       string `koanf:"path"`
	Version    string `koanf:"version"`
	Error      string `koanf:"error"`
}

// CommandSurface documents subcommands and flags for one CLI.
type CommandSurface struct {
	GlobalFlags []CommandFlag       `koanf:"global-flags"`
	Subcommands []CommandSubcommand `koanf:"subcommands"`
}

// CommandFlag documents one CLI flag.
type CommandFlag struct {
	Name        string `koanf:"name"`
	Description string `koanf:"description"`
}

// CommandSubcommand documents one CLI subcommand.
type CommandSubcommand struct {
	Name        string              `koanf:"name"`
	Description string              `koanf:"description"`
	Flags       []CommandFlag       `koanf:"flags"`
	Subcommands []CommandSubcommand `koanf:"subcommands"`
}

// CommandOperation describes one deterministic runbook-callable CLI call.
type CommandOperation struct {
	Name             string            `koanf:"name"`
	Description      string            `koanf:"description"`
	Args             []string          `koanf:"args"`
	Timeout          string            `koanf:"timeout"`
	MaxOutputBytes   int               `koanf:"max-output-bytes"`
	InputSchema      map[string]any    `koanf:"input-schema"`
	Output           CommandOutput     `koanf:"output"`
	OutputSchema     map[string]any    `koanf:"output-schema"`
	ParserID         string            `koanf:"parser-id"`
	OutputSource     string            `koanf:"output-source"`
	ArtifactGlobs    []string          `koanf:"artifact-globs"`
	Annotations      map[string]any    `koanf:"annotations"`
	Env              map[string]string `koanf:"env"`
	WorkingDir       string            `koanf:"working-dir"`
	WorkingDirPolicy string            `koanf:"working-directory-policy"`
}

// CommandOutput describes raw output parsing for one CLI operation.
type CommandOutput struct {
	Format string `koanf:"format"`
	Source string `koanf:"source"`
}

// NodePreset describes reusable runbook-node metadata for authoring tools.
type NodePreset struct {
	ID          string         `koanf:"id"`
	Label       string         `koanf:"label"`
	Surface     string         `koanf:"surface"`
	Action      string         `koanf:"action"`
	Description string         `koanf:"description"`
	Arguments   map[string]any `koanf:"arguments"`
	InputSchema map[string]any `koanf:"input-schema"`
}

// ToolValidation describes one portable test case for an agent-facing tool.
type ToolValidation struct {
	ID          string                `koanf:"id"`
	Label       string                `koanf:"label"`
	Description string                `koanf:"description"`
	Mode        string                `koanf:"mode"`
	Target      ToolValidationTarget  `koanf:"target"`
	Prompt      string                `koanf:"prompt"`
	Input       map[string]any        `koanf:"input"`
	Fixtures    map[string]any        `koanf:"fixtures"`
	Mocks       map[string]any        `koanf:"mocks"`
	Expected    map[string]any        `koanf:"expected"`
	Assertions  []ValidationAssertion `koanf:"assertions"`
}

// ToolValidationTarget identifies the invocation surface under test.
type ToolValidationTarget struct {
	Type      string `koanf:"type"`
	PresetID  string `koanf:"preset-id"`
	Command   string `koanf:"command"`
	Operation string `koanf:"operation"`
	MCPServer string `koanf:"mcp-server"`
	MCPTool   string `koanf:"mcp-tool"`
}

// ValidationAssertion describes one generic result expectation.
type ValidationAssertion struct {
	Type     string         `koanf:"type"`
	Path     string         `koanf:"path"`
	Equals   any            `koanf:"equals"`
	Contains string         `koanf:"contains"`
	Matches  string         `koanf:"matches"`
	Schema   map[string]any `koanf:"schema"`
	Message  string         `koanf:"message"`
}

// Provider describes one model provider configuration.
type Provider struct {
	Name    string `koanf:"name"`
	Adapter string `koanf:"adapter"`
	Auth    string `koanf:"auth"`
	// Runtime stores UI-owned local model runtime metadata ignored by adapters.
	Runtime    string `koanf:"runtime"`
	APIKeyEnv  string `koanf:"api-key"`
	Default    string `koanf:"default"`
	URL        string `koanf:"url"`
	Executable string `koanf:"executable"`
	// HFRepo stores UI-owned local model source metadata ignored by adapters.
	HFRepo string  `koanf:"hf-repo"`
	Models []Model `koanf:"models"`
}

// Model describes one selectable model for a provider.
type Model struct {
	ID           string            `koanf:"id"`
	Model        string            `koanf:"model"`
	Path         string            `koanf:"path"`
	Capabilities ModelCapabilities `koanf:"capabilities"`
}

// ModelCapabilities declares optional capabilities supported by a model.
type ModelCapabilities struct {
	Streaming bool `koanf:"streaming"`
}

// ProviderSelection is the resolved provider/model pair used to create an LLM.
type ProviderSelection struct {
	Name     string
	Provider Provider
	Model    Model
}
