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
	Default   string              `koanf:"default"`
	Providers map[string]Provider `koanf:"providers"`
}

// Agent describes the configured agent identity and instructions.
type Agent struct {
	Name        string `koanf:"name"`
	Description string `koanf:"description"`
	Instruction string `koanf:"instruction"`
}

// Tools describes all configured external tool integrations.
type Tools struct {
	LocalExec LocalExec `koanf:"local-exec"`
	MCP       MCP       `koanf:"mcp"`
	Memory    Memory    `koanf:"memory"`
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
	AllowedWorkdirs       []string           `koanf:"allowed-workdirs"`
	Commands              []LocalExecCommand `koanf:"commands"`
}

// LocalExecCommand describes one allowlisted local command alias.
type LocalExecCommand struct {
	Name           string   `koanf:"name"`
	Executable     string   `koanf:"executable"`
	Description    string   `koanf:"description"`
	Args           []string `koanf:"args"`
	Timeout        string   `koanf:"timeout"`
	MaxOutputBytes int      `koanf:"max-output-bytes"`
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
