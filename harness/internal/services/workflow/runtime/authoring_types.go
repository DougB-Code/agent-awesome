// This file defines DTOs used by workflow authoring APIs.
package runtime

import (
	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/mapping"
	"agentawesome/internal/services/workflow/store"
)

// ActionType describes one action node the authoring UI can place in a draft.
type ActionType struct {
	Name            string         `json:"name"`
	Label           string         `json:"label"`
	Description     string         `json:"description"`
	Risk            string         `json:"risk"`
	Available       bool           `json:"available"`
	InputSchema     map[string]any `json:"input_schema"`
	OutputSchema    map[string]any `json:"output_schema,omitempty"`
	InputContracts  []string       `json:"input_contracts,omitempty"`
	OutputContracts []string       `json:"output_contracts,omitempty"`
}

// DraftRequest carries a workflow draft create or update payload.
type DraftRequest struct {
	ID          string         `json:"id"`
	Kind        string         `json:"kind"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Body        map[string]any `json:"body"`
}

// ValidationDiagnostic describes one draft validation message.
type ValidationDiagnostic struct {
	Severity string `json:"severity"`
	Path     string `json:"path"`
	Message  string `json:"message"`
}

// ValidationResult reports syntax validity and publication readiness.
type ValidationResult struct {
	Valid       bool                   `json:"valid"`
	Publishable bool                   `json:"publishable"`
	Diagnostics []ValidationDiagnostic `json:"diagnostics"`
	Definition  map[string]any         `json:"definition,omitempty"`
}

// CompileResult contains a compiled workflow definition and YAML body.
type CompileResult struct {
	Definition definition.Definition `json:"definition"`
	YAML       string                `json:"yaml"`
	Validation ValidationResult      `json:"validation"`
}

// EdgeCompatibilityRequest selects a prospective edge in an editable draft.
type EdgeCompatibilityRequest struct {
	SourceNodeID string              `json:"source_node_id"`
	TargetNodeID string              `json:"target_node_id"`
	Adapter      adapters.Definition `json:"adapter,omitempty"`
}

// EdgeCompatibilityResult reports whether two workflow nodes can be connected.
type EdgeCompatibilityResult struct {
	SourceNodeID     string                  `json:"source_node_id"`
	TargetNodeID     string                  `json:"target_node_id"`
	Source           contracts.ToolManifest  `json:"source"`
	Target           contracts.ToolManifest  `json:"target"`
	Compatibility    contracts.Compatibility `json:"compatibility"`
	SuggestedAdapter adapters.Definition     `json:"suggested_adapter,omitempty"`
}

// MappingPreviewRequest carries a mapping and sample input for deterministic preview.
type MappingPreviewRequest struct {
	Mapping  mapping.Spec   `json:"mapping"`
	Input    map[string]any `json:"input,omitempty"`
	Envelope map[string]any `json:"envelope,omitempty"`
}

// DesignSuggestionRequest asks a design-time assistant for deterministic artifacts.
type DesignSuggestionRequest struct {
	Prompt   string         `json:"prompt"`
	Context  map[string]any `json:"context,omitempty"`
	Manifest map[string]any `json:"manifest,omitempty"`
}

// DesignArtifact stores one deterministic artifact proposed at design time.
type DesignArtifact struct {
	ID   string         `json:"id,omitempty"`
	Kind string         `json:"kind"`
	Name string         `json:"name,omitempty"`
	Body map[string]any `json:"body"`
}

// DesignSuggestionResult returns validated and persisted design artifacts.
type DesignSuggestionResult struct {
	Artifacts []store.DesignArtifactRecord `json:"artifacts"`
}

// AdapterChoiceRequest stores a user-confirmed adapter decision for a draft edge.
type AdapterChoiceRequest struct {
	ID           string              `json:"id,omitempty"`
	Name         string              `json:"name,omitempty"`
	DraftID      string              `json:"draft_id"`
	SourceNodeID string              `json:"source_node_id"`
	TargetNodeID string              `json:"target_node_id"`
	ChoiceIDs    []string            `json:"choice_ids,omitempty"`
	Adapter      adapters.Definition `json:"adapter,omitempty"`
}

// AdapterChoiceResult returns the persisted adapter artifact and selected adapter.
type AdapterChoiceResult struct {
	Artifact      store.DesignArtifactRecord `json:"artifact"`
	Adapter       adapters.Definition        `json:"adapter"`
	Compatibility contracts.Compatibility    `json:"compatibility"`
}

// AdapterArtifact stores a reusable deterministic edge adapter.
type AdapterArtifact struct {
	SourceTool   string              `json:"source_tool"`
	TargetTool   string              `json:"target_tool"`
	SourceNodeID string              `json:"source_node_id,omitempty"`
	TargetNodeID string              `json:"target_node_id,omitempty"`
	ChoiceIDs    []string            `json:"choice_ids,omitempty"`
	Adapter      adapters.Definition `json:"adapter"`
}

// FacetSuggestionArtifact stores deterministic semantic facet suggestions.
type FacetSuggestionArtifact struct {
	ToolID         string                    `json:"tool_id,omitempty"`
	ContractSide   string                    `json:"contract_side,omitempty"`
	Facets         []string                  `json:"facets,omitempty"`
	ObservedFields []contracts.ObservedField `json:"observed_fields,omitempty"`
	Explanation    string                    `json:"explanation,omitempty"`
}

// WorkflowExplanationArtifact stores a concise deterministic design explanation.
type WorkflowExplanationArtifact struct {
	WorkflowID string   `json:"workflow_id,omitempty"`
	Summary    string   `json:"summary"`
	Decisions  []string `json:"decisions,omitempty"`
	Risks      []string `json:"risks,omitempty"`
}

// PackageImportRequest carries one package record to install.
type PackageImportRequest struct {
	Package store.PackageRecord `json:"package"`
}

// RunSetupRequest carries a reusable workflow run setup create or update payload.
type RunSetupRequest struct {
	ID           string         `json:"id"`
	DefinitionID string         `json:"definition_id"`
	Name         string         `json:"name"`
	Description  string         `json:"description"`
	Input        map[string]any `json:"input"`
}

// loadedDefinitionDraftSource carries a disk-loaded definition into authoring.
type loadedDefinitionDraftSource struct {
	definition definition.Definition
	body       map[string]any
}

// RunQuery selects workflow runs for the operations screen.
type RunQuery struct {
	Status       string
	DefinitionID string
	Limit        int
}

// RunSetupQuery selects reusable workflow run setups for operations.
type RunSetupQuery struct {
	DefinitionID string
}
