// This file defines contract and manifest structures for runbook composition.
package contracts

import "strings"

const (
	// ManifestSourceAA marks manifests owned by the AA runtime.
	ManifestSourceAA = "aa"
	// ManifestSourceInternal marks host-owned trusted manifests.
	ManifestSourceInternal = "internal"
	// ManifestSourceExternal marks non-AA manifests requiring trust controls.
	ManifestSourceExternal = "external"
)

const (
	// RuntimeSandboxAA executes only built-in AA action code.
	RuntimeSandboxAA = "aa-runtime"
	// RuntimeSandboxHarnessContext delegates tool calls through the harness context API.
	RuntimeSandboxHarnessContext = "harness-context"
	// RuntimeSandboxMCP delegates calls through an explicit MCP endpoint boundary.
	RuntimeSandboxMCP = "mcp"
	// RuntimeSandboxCommandDaemon delegates commands through the command service boundary.
	RuntimeSandboxCommandDaemon = "command-daemon"
	// RuntimeSandboxModel delegates model calls through the configured harness model boundary.
	RuntimeSandboxModel = "model"
	// RuntimeSandboxProcess isolates non-AA tools in a separate OS process.
	RuntimeSandboxProcess = "process"
	// RuntimeSandboxWASM isolates non-AA tools through WASM/WASI.
	RuntimeSandboxWASM = "wasm"
	// RuntimeSandboxContainer isolates non-AA tools in a container boundary.
	RuntimeSandboxContainer = "container"
)

const (
	// NetworkBoundaryConfiguredTool represents the harness-owned tool boundary.
	NetworkBoundaryConfiguredTool = "configured-tool-boundary"
)

// Carrier describes a body or artifact carrier a node accepts or produces.
type Carrier struct {
	Kind       string   `json:"kind,omitempty" yaml:"kind,omitempty"`
	MediaTypes []string `json:"media_types,omitempty" yaml:"media_types,omitempty"`
}

// Contract describes one input or output side of a node.
type Contract struct {
	Accepts        []Carrier      `json:"accepts,omitempty" yaml:"accepts,omitempty"`
	Produces       []Carrier      `json:"produces,omitempty" yaml:"produces,omitempty"`
	RequiredFacets []string       `json:"required_facets,omitempty" yaml:"required_facets,omitempty"`
	Facets         []string       `json:"facets,omitempty" yaml:"facets,omitempty"`
	Schema         map[string]any `json:"schema,omitempty" yaml:"schema,omitempty"`
	Examples       []Example      `json:"examples,omitempty" yaml:"examples,omitempty"`
}

// Example stores a named observed or curated contract example.
type Example struct {
	Name        string         `json:"name,omitempty" yaml:"name,omitempty"`
	OutputShape map[string]any `json:"output_shape,omitempty" yaml:"output_shape,omitempty"`
}

// Effects declares the capabilities a node may use.
type Effects struct {
	Filesystem       FilesystemEffects `json:"filesystem,omitempty" yaml:"filesystem,omitempty"`
	Network          NetworkEffects    `json:"network,omitempty" yaml:"network,omitempty"`
	Secrets          SecretEffects     `json:"secrets,omitempty" yaml:"secrets,omitempty"`
	UserConfirmation ConfirmationRule  `json:"user_confirmation,omitempty" yaml:"user_confirmation,omitempty"`
}

// FilesystemEffects declares filesystem read/write permissions.
type FilesystemEffects struct {
	Read  []string `json:"read,omitempty" yaml:"read,omitempty"`
	Write []string `json:"write,omitempty" yaml:"write,omitempty"`
}

// NetworkEffects declares network permission boundaries.
type NetworkEffects struct {
	AllowedHosts []string `json:"allowed_hosts,omitempty" yaml:"allowed_hosts,omitempty"`
}

// SecretEffects declares required secret names.
type SecretEffects struct {
	Required []string `json:"required,omitempty" yaml:"required,omitempty"`
}

// ConfirmationRule declares operation names that require user confirmation.
type ConfirmationRule struct {
	RequiredFor []string `json:"required_for,omitempty" yaml:"required_for,omitempty"`
}

// Runtime declares deterministic execution policy for a node or tool.
type Runtime struct {
	TimeoutMS          int64  `json:"timeout_ms,omitempty" yaml:"timeout_ms,omitempty"`
	MaxInputBytes      int64  `json:"max_input_bytes,omitempty" yaml:"max_input_bytes,omitempty"`
	MaxArtifactBytes   int64  `json:"max_artifact_bytes,omitempty" yaml:"max_artifact_bytes,omitempty"`
	RateLimitPerMinute int    `json:"rate_limit_per_minute,omitempty" yaml:"rate_limit_per_minute,omitempty"`
	Idempotent         bool   `json:"idempotent,omitempty" yaml:"idempotent,omitempty"`
	Retryable          bool   `json:"retryable,omitempty" yaml:"retryable,omitempty"`
	Sandbox            string `json:"sandbox,omitempty" yaml:"sandbox,omitempty"`
}

// ToolManifest stores the AA-owned callable tool contract.
type ToolManifest struct {
	ID          string   `json:"id" yaml:"id"`
	Version     string   `json:"version,omitempty" yaml:"version,omitempty"`
	Title       string   `json:"title,omitempty" yaml:"title,omitempty"`
	Description string   `json:"description,omitempty" yaml:"description,omitempty"`
	Input       Contract `json:"input,omitempty" yaml:"input,omitempty"`
	Output      Contract `json:"output,omitempty" yaml:"output,omitempty"`
	Effects     Effects  `json:"effects,omitempty" yaml:"effects,omitempty"`
	Runtime     Runtime  `json:"runtime,omitempty" yaml:"runtime,omitempty"`
	Signing     Signing  `json:"signing,omitempty" yaml:"signing,omitempty"`
	Source      string   `json:"source,omitempty" yaml:"source,omitempty"`
}

// Signing declares marketplace signing and verification metadata.
type Signing struct {
	SignerID  string `json:"signer_id,omitempty" yaml:"signer_id,omitempty"`
	Algorithm string `json:"algorithm,omitempty" yaml:"algorithm,omitempty"`
	Digest    string `json:"digest,omitempty" yaml:"digest,omitempty"`
	Signature string `json:"signature,omitempty" yaml:"signature,omitempty"`
}

// TrustedSigner stores one public key trusted for external manifests.
type TrustedSigner struct {
	ID        string `json:"id" yaml:"id"`
	Algorithm string `json:"algorithm" yaml:"algorithm"`
	PublicKey string `json:"public_key" yaml:"public_key"`
}

// ObservedField describes a field inferred from example output.
type ObservedField struct {
	Path       string `json:"path" yaml:"path"`
	Type       string `json:"type" yaml:"type"`
	Facet      string `json:"facet,omitempty" yaml:"facet,omitempty"`
	Confidence string `json:"confidence,omitempty" yaml:"confidence,omitempty"`
}

// Registry stores manifests by tool id.
type Registry struct {
	manifests map[string]ToolManifest
}

// NewRegistry creates an empty manifest registry.
func NewRegistry() *Registry {
	return &Registry{manifests: map[string]ToolManifest{}}
}

// Register installs or replaces one manifest.
func (r *Registry) Register(manifest ToolManifest) {
	if r.manifests == nil {
		r.manifests = map[string]ToolManifest{}
	}
	r.manifests[strings.TrimSpace(manifest.ID)] = manifest
}

// Get returns one registered manifest.
func (r *Registry) Get(id string) (ToolManifest, bool) {
	if r == nil {
		return ToolManifest{}, false
	}
	manifest, ok := r.manifests[strings.TrimSpace(id)]
	return manifest, ok
}
