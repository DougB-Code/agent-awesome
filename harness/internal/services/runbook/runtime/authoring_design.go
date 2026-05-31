// This file validates and persists runbook authoring design artifacts.
package runtime

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"

	"agentawesome/internal/services/runbook/contracts"
	"agentawesome/internal/services/runbook/definition"
	"agentawesome/internal/services/runbook/envelope"
	"agentawesome/internal/services/runbook/mapping"
	"agentawesome/internal/services/runbook/store"
)

// SuggestDesignArtifacts asks the design-time assistant for validated artifacts.
func (s *Service) SuggestDesignArtifacts(ctx context.Context, req DesignSuggestionRequest) (DesignSuggestionResult, error) {
	if s.cfg.DesignAssistant == nil {
		return DesignSuggestionResult{}, fmt.Errorf("runbook design assistant is not configured")
	}
	suggestions, err := s.cfg.DesignAssistant.SuggestDesignArtifacts(ctx, req)
	if err != nil {
		return DesignSuggestionResult{}, err
	}
	records := make([]store.DesignArtifactRecord, 0, len(suggestions))
	for _, suggestion := range suggestions {
		record, err := s.designArtifactRecord(suggestion)
		if err != nil {
			return DesignSuggestionResult{}, err
		}
		if err := s.store.UpsertDesignArtifact(ctx, record); err != nil {
			return DesignSuggestionResult{}, err
		}
		records = append(records, record)
	}
	return DesignSuggestionResult{Artifacts: records}, nil
}

// ListDesignArtifacts returns persisted deterministic design artifacts.
func (s *Service) ListDesignArtifacts(ctx context.Context) ([]store.DesignArtifactRecord, error) {
	return s.store.ListDesignArtifacts(ctx)
}

// designArtifactRecord validates and normalizes one proposed design artifact.
func (s *Service) designArtifactRecord(artifact DesignArtifact) (store.DesignArtifactRecord, error) {
	kind := strings.TrimSpace(artifact.Kind)
	if kind == "" {
		return store.DesignArtifactRecord{}, fmt.Errorf("design artifact kind is required")
	}
	body := cloneMap(artifact.Body)
	if len(body) == 0 {
		return store.DesignArtifactRecord{}, fmt.Errorf("design artifact body is required")
	}
	if err := s.validateDesignArtifact(kind, body); err != nil {
		return store.DesignArtifactRecord{}, err
	}
	id := strings.TrimSpace(artifact.ID)
	if id == "" {
		generated, err := designArtifactID(kind, body)
		if err != nil {
			return store.DesignArtifactRecord{}, err
		}
		id = generated
	}
	if err := validateAuthoringID(id, "design artifact id"); err != nil {
		return store.DesignArtifactRecord{}, err
	}
	name := strings.TrimSpace(artifact.Name)
	if name == "" {
		name = stringFromMap(body, "name", id)
	}
	return store.DesignArtifactRecord{
		ID:   id,
		Kind: kind,
		Name: name,
		Body: body,
	}, nil
}

// validateDesignArtifact checks deterministic artifact bodies before persistence.
func (s *Service) validateDesignArtifact(kind string, body map[string]any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("encode design artifact: %w", err)
	}
	switch strings.TrimSpace(kind) {
	case "mapping":
		var spec mapping.Spec
		if err := json.Unmarshal(encoded, &spec); err != nil {
			return fmt.Errorf("decode mapping artifact: %w", err)
		}
		if diagnostics := mapping.Validate(spec); diagnosticsHaveErrors(diagnostics) {
			return fmt.Errorf("mapping artifact is invalid: %s", diagnosticsSummary(diagnostics))
		}
	case "tool_manifest":
		var manifest contracts.ToolManifest
		if err := json.Unmarshal(encoded, &manifest); err != nil {
			return fmt.Errorf("decode tool manifest artifact: %w", err)
		}
		if err := contracts.VerifyManifest(manifest, s.cfg.TrustedSigners); err != nil {
			return fmt.Errorf("tool manifest artifact is invalid: %w", err)
		}
	case "facet_suggestion":
		var artifact FacetSuggestionArtifact
		if err := json.Unmarshal(encoded, &artifact); err != nil {
			return fmt.Errorf("decode facet suggestion artifact: %w", err)
		}
		if err := validateFacetSuggestionArtifact(artifact); err != nil {
			return err
		}
	case "runbook_explanation":
		var artifact RunbookExplanationArtifact
		if err := json.Unmarshal(encoded, &artifact); err != nil {
			return fmt.Errorf("decode runbook explanation artifact: %w", err)
		}
		if strings.TrimSpace(artifact.Summary) == "" {
			return fmt.Errorf("runbook explanation summary is required")
		}
	case "runbook":
		var def definition.Definition
		if err := json.Unmarshal(encoded, &def); err != nil {
			return fmt.Errorf("decode runbook artifact: %w", err)
		}
		if err := definition.Validate(def, s.actions); err != nil {
			return fmt.Errorf("runbook artifact is invalid: %w", err)
		}
	default:
		return fmt.Errorf("design artifact kind %q is not supported", kind)
	}
	return nil
}

// validateFacetSuggestionArtifact checks semantic facet suggestion artifacts.
func validateFacetSuggestionArtifact(artifact FacetSuggestionArtifact) error {
	if len(artifact.Facets) == 0 && len(artifact.ObservedFields) == 0 {
		return fmt.Errorf("facet suggestion requires facets or observed_fields")
	}
	for _, facet := range artifact.Facets {
		if strings.TrimSpace(facet) == "" {
			return fmt.Errorf("facet suggestion includes an empty facet")
		}
	}
	for _, field := range artifact.ObservedFields {
		if strings.TrimSpace(field.Path) == "" || strings.TrimSpace(field.Type) == "" {
			return fmt.Errorf("facet suggestion observed fields require path and type")
		}
	}
	return nil
}

// diagnosticsHaveErrors reports whether mapping diagnostics include errors.
func diagnosticsHaveErrors(diagnostics []envelope.Diagnostic) bool {
	for _, diagnostic := range diagnostics {
		if strings.EqualFold(strings.TrimSpace(diagnostic.Severity), "error") {
			return true
		}
	}
	return false
}

// diagnosticsSummary returns a compact error summary.
func diagnosticsSummary(diagnostics []envelope.Diagnostic) string {
	var messages []string
	for _, diagnostic := range diagnostics {
		if strings.EqualFold(strings.TrimSpace(diagnostic.Severity), "error") {
			messages = append(messages, diagnostic.Message)
		}
	}
	return strings.Join(messages, "; ")
}

// designArtifactID creates a deterministic id from artifact content.
func designArtifactID(kind string, body map[string]any) (string, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(encoded)
	return strings.ReplaceAll(strings.TrimSpace(kind), "-", "_") + "_" + hex.EncodeToString(sum[:8]), nil
}
