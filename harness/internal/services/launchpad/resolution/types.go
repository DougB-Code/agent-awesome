// This file defines Launch input resolution data contracts.
package resolution

// Source identifies where one resolved field value came from.
type Source string

const (
	// SourceRunRequest identifies explicit values from a start request.
	SourceRunRequest Source = "run_request"
	// SourceLaunchDefault identifies values saved on the Launch.
	SourceLaunchDefault Source = "launch_default"
	// SourceCodebaseDefault identifies values from a codebase catalog entry.
	SourceCodebaseDefault Source = "codebase_default"
	// SourceRunbookDefault identifies values from the runbook definition.
	SourceRunbookDefault Source = "runbook_default"
	// SourceGenerated identifies deterministic generated values.
	SourceGenerated Source = "generated"
	// SourceSecretReference identifies secret references without secret values.
	SourceSecretReference Source = "secret_reference"
	// SourceStepOutput identifies values produced by earlier runbook steps.
	SourceStepOutput Source = "step_output"
	// SourceAgentInference identifies explicitly permitted agent inference.
	SourceAgentInference Source = "agent_inference"
)

// Request asks the resolver to assemble complete runbook input.
type Request struct {
	RequiredFields    []string
	RunRequest        map[string]any
	LaunchDefaults map[string]any
	CodebaseDefaults  map[string]any
	RunbookDefaults  map[string]any
	GeneratedValues   map[string]any
	SecretReferences  map[string]any
	StepOutputs       map[string]any
	AgentInferences   map[string]any
	InferableFields   []string
	AllowOverrides    bool
}

// Result contains resolved input, missing requirements, and diagnostics.
type Result struct {
	Status       string                      `json:"status"`
	Input        map[string]any              `json:"input"`
	Fields       map[string]ResolvedField    `json:"fields"`
	Unresolved   []UnresolvedField           `json:"unresolved_required_fields,omitempty"`
	Diagnostics  []Diagnostic                `json:"diagnostics,omitempty"`
	SecretFields []string                    `json:"secret_fields,omitempty"`
	Candidates   map[string][]FieldCandidate `json:"candidates,omitempty"`
}

// ResolvedField describes one winning resolved value.
type ResolvedField struct {
	Name   string `json:"name"`
	Source Source `json:"source"`
	Value  any    `json:"value"`
}

// UnresolvedField describes one required value that still needs input.
type UnresolvedField struct {
	Name   string `json:"name"`
	Reason string `json:"reason"`
}

// Diagnostic stores display-safe resolution details.
type Diagnostic struct {
	Field   string `json:"field,omitempty"`
	Level   string `json:"level"`
	Message string `json:"message"`
}

// FieldCandidate stores a lower-precedence value kept for diagnosis.
type FieldCandidate struct {
	Source Source `json:"source"`
	Value  any    `json:"value"`
}
