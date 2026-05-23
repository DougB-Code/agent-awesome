// This file implements deterministic workflow data defaulting.
package actions

import (
	"context"
	"strings"
)

// dataDefaults overlays input values onto a default object without mutating either map.
func dataDefaults(_ context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	input := resolvedMapArg(args, "input", execCtx.Input, execCtx.Input)
	defaults := resolvedMapArg(args, "defaults", nil, execCtx.Input)
	return mergeDefaults(defaults, input), nil
}

// mergeDefaults returns defaults with non-empty input values taking precedence.
func mergeDefaults(defaults map[string]any, input map[string]any) map[string]any {
	merged := cloneAnyMap(defaults)
	for key, value := range input {
		if nestedInput, ok := value.(map[string]any); ok {
			if nestedDefaults, ok := merged[key].(map[string]any); ok {
				merged[key] = mergeDefaults(nestedDefaults, nestedInput)
				continue
			}
		}
		if isDefaultableValue(value) {
			continue
		}
		merged[key] = value
	}
	return merged
}

// isDefaultableValue reports whether a value should be replaced by a default.
func isDefaultableValue(value any) bool {
	if value == nil {
		return true
	}
	if text, ok := value.(string); ok {
		return strings.TrimSpace(text) == ""
	}
	return false
}

// cloneAnyMap copies a JSON-like object map.
func cloneAnyMap(values map[string]any) map[string]any {
	if values == nil {
		return map[string]any{}
	}
	next := make(map[string]any, len(values))
	for key, value := range values {
		if nested, ok := value.(map[string]any); ok {
			next[key] = cloneAnyMap(nested)
			continue
		}
		next[key] = value
	}
	return next
}
