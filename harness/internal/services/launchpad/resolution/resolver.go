// This file implements deterministic Launch input resolution.
package resolution

import (
	"context"
	"strings"
)

// Resolver resolves run input from strict precedence-ordered sources.
type Resolver struct{}

// NewResolver creates an Launch input resolver.
func NewResolver() Resolver {
	return Resolver{}
}

// Resolve applies source precedence and records provenance for every field.
func (r Resolver) Resolve(ctx context.Context, req Request) (Result, error) {
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	result := Result{
		Status:     "resolved",
		Input:      map[string]any{},
		Fields:     map[string]ResolvedField{},
		Candidates: map[string][]FieldCandidate{},
	}
	inferable := stringSet(req.InferableFields)
	r.applySource(&result, SourceRunRequest, req.RunRequest, true)
	r.applySource(&result, SourceLaunchDefault, req.LaunchDefaults, req.AllowOverrides)
	r.applySource(&result, SourceCodebaseDefault, req.CodebaseDefaults, req.AllowOverrides)
	r.applySource(&result, SourceRunbookDefault, req.RunbookDefaults, req.AllowOverrides)
	r.applySource(&result, SourceGenerated, req.GeneratedValues, req.AllowOverrides)
	r.applySource(&result, SourceSecretReference, redactSecretReferences(req.SecretReferences), req.AllowOverrides)
	r.applySource(&result, SourceStepOutput, req.StepOutputs, req.AllowOverrides)
	for key, value := range req.AgentInferences {
		if _, ok := inferable[key]; !ok {
			result.Diagnostics = append(result.Diagnostics, Diagnostic{Field: key, Level: "info", Message: "agent inference ignored because the field is not marked inferable"})
			continue
		}
		r.applyField(&result, SourceAgentInference, key, value, req.AllowOverrides)
	}
	for _, field := range normalizedFieldList(req.RequiredFields) {
		if !hasConcreteValue(result.Input[field]) {
			result.Unresolved = append(result.Unresolved, UnresolvedField{Name: field, Reason: "required field was not resolved"})
		}
	}
	for key := range req.SecretReferences {
		if strings.TrimSpace(key) != "" {
			result.SecretFields = append(result.SecretFields, strings.TrimSpace(key))
		}
	}
	if len(result.Unresolved) > 0 {
		result.Status = "needs_input"
	}
	if len(result.Candidates) == 0 {
		result.Candidates = nil
	}
	return result, nil
}

// applySource applies all fields from one source.
func (r Resolver) applySource(result *Result, source Source, values map[string]any, allowOverride bool) {
	for key, value := range values {
		r.applyField(result, source, key, value, allowOverride)
	}
}

// applyField applies one field while preserving winner and candidate data.
func (r Resolver) applyField(result *Result, source Source, key string, value any, allowOverride bool) {
	name := strings.TrimSpace(key)
	if name == "" || !hasConcreteValue(value) {
		return
	}
	if _, exists := result.Fields[name]; exists && !allowOverride {
		result.Candidates[name] = append(result.Candidates[name], FieldCandidate{Source: source, Value: value})
		return
	}
	result.Input[name] = value
	result.Fields[name] = ResolvedField{Name: name, Source: source, Value: value}
}

// redactSecretReferences removes raw secret-like values from resolution output.
func redactSecretReferences(values map[string]any) map[string]any {
	redacted := map[string]any{}
	for key, value := range values {
		if reference, ok := value.(string); ok && strings.HasPrefix(strings.TrimSpace(reference), "secret://") {
			redacted[key] = strings.TrimSpace(reference)
			continue
		}
		if strings.TrimSpace(key) != "" {
			redacted[key] = "secret://redacted/" + strings.TrimSpace(key)
		}
	}
	return redacted
}

// normalizedFieldList trims and deduplicates field names.
func normalizedFieldList(values []string) []string {
	seen := map[string]struct{}{}
	out := []string{}
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	return out
}

// stringSet returns a trimmed lookup set.
func stringSet(values []string) map[string]struct{} {
	set := map[string]struct{}{}
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			set[trimmed] = struct{}{}
		}
	}
	return set
}

// hasConcreteValue reports whether a value should count as resolved.
func hasConcreteValue(value any) bool {
	switch typed := value.(type) {
	case nil:
		return false
	case string:
		return strings.TrimSpace(typed) != ""
	default:
		return true
	}
}
