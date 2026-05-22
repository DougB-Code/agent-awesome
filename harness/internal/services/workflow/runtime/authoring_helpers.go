// This file contains small shared helpers for workflow authoring APIs.
package runtime

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/definition"
)

// unavailableActions returns registered actions that cannot be published yet.
func unavailableActions(_ definition.Definition) []string {
	return nil
}

// invalidValidation builds a failed validation report.
func invalidValidation(path string, err error) ValidationResult {
	return ValidationResult{
		Valid:       false,
		Publishable: false,
		Diagnostics: []ValidationDiagnostic{{
			Severity: "error",
			Path:     path,
			Message:  err.Error(),
		}},
	}
}

// validateAuthoringID checks ids used by authoring records.
func validateAuthoringID(value string, label string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return fmt.Errorf("%s is required", label)
	}
	if !authoringIDPattern.MatchString(trimmed) {
		return fmt.Errorf("%s %q is invalid", label, trimmed)
	}
	return nil
}

// definitionIDFromDraftID returns a safe default definition id for a draft.
func definitionIDFromDraftID(id string) string {
	trimmed := strings.TrimPrefix(strings.TrimSpace(id), "draft_")
	if trimmed == "" || !authoringIDPattern.MatchString(trimmed) {
		return "automation_" + strings.ReplaceAll(strings.TrimSpace(id), "-", "_")
	}
	return trimmed
}

// draftIDForDefinition returns the editable draft id for a loaded definition.
func draftIDForDefinition(id string) string {
	return "draft_" + strings.TrimSpace(id)
}

// stringFromMap returns a string value from a JSON map.
func stringFromMap(body map[string]any, key string, fallback string) string {
	if value, ok := body[key].(string); ok && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	return fallback
}

// anySlice returns a JSON list from decoded draft data.
func anySlice(value any) []any {
	if items, ok := value.([]any); ok {
		return items
	}
	return []any{}
}

// intFromAny reads whole-number JSON values without expression evaluation.
func intFromAny(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	case json.Number:
		parsed, _ := typed.Int64()
		return int(parsed)
	default:
		return 0
	}
}

// cloneMap returns a JSON-deep-copy of a map.
func cloneMap(value map[string]any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return map[string]any{}
	}
	var cloned map[string]any
	if err := json.Unmarshal(encoded, &cloned); err != nil {
		return map[string]any{}
	}
	return cloned
}

// mapFromJSON converts a typed value to generic JSON object form.
func mapFromJSON(value any) (map[string]any, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(encoded, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// definitionHash returns the stable JSON hash used for published metadata.
func definitionHash(def definition.Definition) string {
	encoded, _ := json.Marshal(def)
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:])
}
