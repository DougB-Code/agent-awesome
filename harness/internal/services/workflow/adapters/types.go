// This file defines deterministic edge adapter execution.
package adapters

import (
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/envelope"
	"agentawesome/internal/services/workflow/mapping"
)

const (
	// KindDirect copies the source envelope into the target input.
	KindDirect = "direct"
	// KindSelect selects a source field or artifact into the target input.
	KindSelect = "select"
	// KindMapping applies an AA Mapping Spec.
	KindMapping = "mapping"
	// KindConstant creates a target envelope from a fixed value.
	KindConstant = "constant"
	// StrategyFirstMatchingArtifact selects the first artifact matching media policy.
	StrategyFirstMatchingArtifact = "first_matching_artifact"
)

// Definition describes one deterministic edge adapter.
type Definition struct {
	Kind       string        `json:"kind,omitempty" yaml:"kind,omitempty"`
	Strategy   string        `json:"strategy,omitempty" yaml:"strategy,omitempty"`
	Operation  string        `json:"operation,omitempty" yaml:"operation,omitempty"`
	Source     string        `json:"source,omitempty" yaml:"source,omitempty"`
	Target     string        `json:"target,omitempty" yaml:"target,omitempty"`
	MediaType  string        `json:"media_type,omitempty" yaml:"media_type,omitempty"`
	MappingRef string        `json:"mappingRef,omitempty" yaml:"mappingRef,omitempty"`
	Mapping    *mapping.Spec `json:"mapping,omitempty" yaml:"mapping,omitempty"`
	Value      any           `json:"value,omitempty" yaml:"value,omitempty"`
}

// Lookup resolves mapping specs referenced by adapters.
type Lookup interface {
	Mapping(name string) (mapping.Spec, bool)
}

// Apply executes one edge adapter against a source envelope.
func Apply(def Definition, input envelope.Envelope, lookup Lookup) (envelope.Envelope, []envelope.Diagnostic) {
	input.Normalize()
	switch adapterKind(def) {
	case KindDirect:
		return input.Clone(), nil
	case KindSelect:
		return applySelect(def, input)
	case KindMapping:
		return applyMapping(def, input, lookup)
	case KindConstant:
		return envelope.New(input.Meta.WorkflowRunID, "", input.Meta.Attempt, def.Value), nil
	default:
		out := input.Clone()
		diag := envelope.Diagnostic{Severity: "error", Code: "adapter_unsupported", Message: "adapter kind " + adapterKind(def) + " is unsupported"}
		out.Diagnostics = append(out.Diagnostics, diag)
		return out, []envelope.Diagnostic{diag}
	}
}

// Declared reports whether an adapter contains deterministic work.
func Declared(def Definition) bool {
	return strings.TrimSpace(def.Kind) != "" ||
		strings.TrimSpace(def.Operation) != "" ||
		strings.TrimSpace(def.MappingRef) != "" ||
		def.Mapping != nil
}

// adapterKind returns a normalized adapter kind with direct default.
func adapterKind(def Definition) string {
	kind := strings.ToLower(strings.TrimSpace(def.Kind))
	if kind == "" {
		kind = strings.ToLower(strings.TrimSpace(def.Operation))
	}
	if kind == "" {
		return KindDirect
	}
	return kind
}

// applySelect executes selection strategies.
func applySelect(def Definition, input envelope.Envelope) (envelope.Envelope, []envelope.Diagnostic) {
	switch strings.ToLower(strings.TrimSpace(def.Strategy)) {
	case "", "path":
		return selectPath(def, input)
	case StrategyFirstMatchingArtifact:
		return selectFirstMatchingArtifact(def, input)
	default:
		diag := envelope.Diagnostic{Severity: "error", Code: "adapter_strategy_unsupported", Message: "select strategy " + def.Strategy + " is unsupported"}
		out := input.Clone()
		out.Diagnostics = append(out.Diagnostics, diag)
		return out, []envelope.Diagnostic{diag}
	}
}

// selectPath selects a simple top-level envelope path into a new envelope.
func selectPath(def Definition, input envelope.Envelope) (envelope.Envelope, []envelope.Diagnostic) {
	value, ok := selectEnvelopePath(input, def.Source)
	if !ok {
		diag := envelope.Diagnostic{Severity: "error", Code: "adapter_source_missing", Path: def.Source, Message: "adapter source was not found"}
		out := input.Clone()
		out.Diagnostics = append(out.Diagnostics, diag)
		return out, []envelope.Diagnostic{diag}
	}
	out := envelope.New(input.Meta.WorkflowRunID, "", input.Meta.Attempt, value)
	out.Control = input.Control
	out.Facets = cloneFacets(input.Facets)
	out.Artifacts = append([]envelope.ArtifactRef(nil), input.Artifacts...)
	out.AddProvenance(input.Meta.NodeRunID, strings.TrimSpace(def.Target), value)
	return out, nil
}

// selectFirstMatchingArtifact selects the first artifact with the configured media type.
func selectFirstMatchingArtifact(def Definition, input envelope.Envelope) (envelope.Envelope, []envelope.Diagnostic) {
	mediaType := strings.TrimSpace(def.MediaType)
	for _, artifact := range input.Artifacts {
		if mediaType != "" && strings.TrimSpace(artifact.MediaType) != mediaType {
			continue
		}
		out := envelope.New(input.Meta.WorkflowRunID, "", input.Meta.Attempt, map[string]any{
			"id":         artifact.ID,
			"media_type": artifact.MediaType,
			"name":       artifact.Name,
			"size":       artifact.Size,
			"uri":        artifact.URI,
			"digest":     artifact.Digest,
		})
		out.Body.Kind = envelope.BodyKindFile
		out.Artifacts = []envelope.ArtifactRef{artifact}
		out.Control = input.Control
		out.AddProvenance(input.Meta.NodeRunID, strings.TrimSpace(def.Target), artifact)
		return out, nil
	}
	diag := envelope.Diagnostic{Severity: "error", Code: "adapter_artifact_missing", Message: fmt.Sprintf("no artifact matched media type %q", mediaType)}
	out := input.Clone()
	out.Diagnostics = append(out.Diagnostics, diag)
	return out, []envelope.Diagnostic{diag}
}

// applyMapping executes an inline or referenced mapping spec.
func applyMapping(def Definition, input envelope.Envelope, lookup Lookup) (envelope.Envelope, []envelope.Diagnostic) {
	spec := mapping.Spec{}
	if def.Mapping != nil {
		spec = *def.Mapping
	} else if strings.TrimSpace(def.MappingRef) != "" && lookup != nil {
		var ok bool
		spec, ok = lookup.Mapping(def.MappingRef)
		if !ok {
			diag := envelope.Diagnostic{Severity: "error", Code: "adapter_mapping_missing", Message: "mapping " + def.MappingRef + " was not found"}
			out := input.Clone()
			out.Diagnostics = append(out.Diagnostics, diag)
			return out, []envelope.Diagnostic{diag}
		}
	} else {
		diag := envelope.Diagnostic{Severity: "error", Code: "adapter_mapping_required", Message: "mapping adapter requires mapping or mappingRef"}
		out := input.Clone()
		out.Diagnostics = append(out.Diagnostics, diag)
		return out, []envelope.Diagnostic{diag}
	}
	return mapping.Apply(spec, input)
}

// selectEnvelopePath resolves a small set of envelope paths.
func selectEnvelopePath(input envelope.Envelope, path string) (any, bool) {
	trimmed := strings.TrimSpace(path)
	switch {
	case trimmed == "", trimmed == "$", trimmed == "input":
		return input.ToMap(), true
	case trimmed == "$.body", trimmed == "body":
		return input.Body.Value, true
	case strings.HasPrefix(trimmed, "$.facets."):
		key := strings.TrimPrefix(trimmed, "$.facets.")
		value, ok := input.Facets[key]
		return value, ok
	case strings.HasPrefix(trimmed, "facets."):
		key := strings.TrimPrefix(trimmed, "facets.")
		value, ok := input.Facets[key]
		return value, ok
	default:
		return nil, false
	}
}

// cloneFacets copies a facet map for an adapted envelope.
func cloneFacets(values map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range values {
		out[key] = value
	}
	return out
}
