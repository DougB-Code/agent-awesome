// This file validates parsed command output against a small JSON-schema subset.
package command

import (
	"fmt"
	"math"
	"strings"
)

// validateOutput checks parsed output against the configured validation schema.
func validateOutput(output any, schema map[string]any) ValidationResult {
	if len(schema) == 0 {
		return ValidationResult{Valid: true}
	}
	var errors []string
	validateSchemaAt(output, schema, "$", &errors)
	return ValidationResult{Checked: true, Valid: len(errors) == 0, Errors: errors}
}

// validateSchemaAt recursively checks one value against a schema object.
func validateSchemaAt(value any, schema map[string]any, path string, errors *[]string) {
	if schemaType := stringFromMap(schema, "type"); schemaType != "" && !matchesSchemaType(value, schemaType) {
		*errors = append(*errors, fmt.Sprintf("%s must be %s", path, schemaType))
		return
	}
	if enumValues, ok := schema["enum"].([]any); ok && len(enumValues) > 0 && !containsEqual(enumValues, value) {
		*errors = append(*errors, fmt.Sprintf("%s must match an enum value", path))
	}
	properties, _ := schema["properties"].(map[string]any)
	required := stringList(schema["required"])
	if len(properties) == 0 && len(required) == 0 {
		return
	}
	object, ok := value.(map[string]any)
	if !ok {
		*errors = append(*errors, fmt.Sprintf("%s must be object", path))
		return
	}
	for _, name := range required {
		if _, ok := object[name]; !ok {
			*errors = append(*errors, fmt.Sprintf("%s.%s is required", path, name))
		}
	}
	for name, rawSchema := range properties {
		child, ok := object[name]
		if !ok {
			continue
		}
		childSchema, ok := rawSchema.(map[string]any)
		if !ok {
			continue
		}
		validateSchemaAt(child, childSchema, path+"."+name, errors)
	}
}

// matchesSchemaType reports whether a Go value has the requested JSON type.
func matchesSchemaType(value any, schemaType string) bool {
	switch strings.ToLower(strings.TrimSpace(schemaType)) {
	case "object":
		_, ok := value.(map[string]any)
		return ok
	case "array":
		_, ok := value.([]any)
		return ok
	case "string":
		_, ok := value.(string)
		return ok
	case "number":
		switch value.(type) {
		case float64, float32, int, int64, int32, uint, uint64, uint32:
			return true
		default:
			return false
		}
	case "integer":
		return isInteger(value)
	case "boolean":
		_, ok := value.(bool)
		return ok
	case "null":
		return value == nil
	default:
		return true
	}
}

// isInteger reports whether a decoded numeric value is integral.
func isInteger(value any) bool {
	switch typed := value.(type) {
	case int, int64, int32, uint, uint64, uint32:
		return true
	case float64:
		return math.Trunc(typed) == typed
	case float32:
		return math.Trunc(float64(typed)) == float64(typed)
	default:
		return false
	}
}

// stringFromMap returns a string field from a schema map.
func stringFromMap(values map[string]any, key string) string {
	value, _ := values[key].(string)
	return strings.TrimSpace(value)
}

// stringList converts a decoded schema list to strings.
func stringList(value any) []string {
	raw, ok := value.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		if text, ok := item.(string); ok && strings.TrimSpace(text) != "" {
			out = append(out, strings.TrimSpace(text))
		}
	}
	return out
}

// containsEqual reports whether enum values include the candidate.
func containsEqual(values []any, candidate any) bool {
	candidateText := fmt.Sprint(candidate)
	for _, value := range values {
		if fmt.Sprint(value) == candidateText {
			return true
		}
	}
	return false
}
