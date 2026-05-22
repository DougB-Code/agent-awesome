// This file implements deterministic JSON-shaped path and schema helpers.
package jsondata

import (
	"fmt"
	"math"
	"reflect"
	"strconv"
	"strings"
)

// SchemaError describes one JSON-schema subset validation failure.
type SchemaError struct {
	Path    string
	Message string
	Code    string
}

// Dotted looks up one dotted path in maps and arrays.
func Dotted(input any, path string) (any, bool) {
	if strings.TrimSpace(path) == "" {
		return input, true
	}
	current := input
	for _, part := range strings.Split(path, ".") {
		if part == "" {
			return nil, false
		}
		switch typed := current.(type) {
		case map[string]any:
			next, ok := typed[part]
			if !ok {
				return nil, false
			}
			current = next
		case []any:
			index, err := strconv.Atoi(part)
			if err != nil || index < 0 || index >= len(typed) {
				return nil, false
			}
			current = typed[index]
		default:
			return nil, false
		}
	}
	return current, true
}

// ValidateSchema checks a deterministic JSON-schema subset.
func ValidateSchema(value any, schema map[string]any, rootPath string, requireSchema bool) []SchemaError {
	if len(schema) == 0 {
		if requireSchema {
			return []SchemaError{{Path: rootPath, Code: "schema_required", Message: "schema is required"}}
		}
		return nil
	}
	if strings.TrimSpace(rootPath) == "" {
		rootPath = "$"
	}
	var errors []SchemaError
	validateSchemaAt(value, schema, rootPath, &errors)
	return errors
}

// SchemaMessages returns human-facing schema validation messages.
func SchemaMessages(errors []SchemaError) []string {
	messages := make([]string, 0, len(errors))
	for _, item := range errors {
		messages = append(messages, item.Message)
	}
	return messages
}

// validateSchemaAt recursively checks a value against one schema object.
func validateSchemaAt(value any, schema map[string]any, path string, errors *[]SchemaError) {
	if schemaType, _ := schema["type"].(string); strings.TrimSpace(schemaType) != "" && !MatchesSchemaType(value, schemaType) {
		*errors = append(*errors, SchemaError{Path: path, Code: "schema_type_mismatch", Message: fmt.Sprintf("%s must be %s", path, schemaType)})
		return
	}
	if enumValues, ok := schema["enum"].([]any); ok && len(enumValues) > 0 && !containsEqual(enumValues, value) {
		*errors = append(*errors, SchemaError{Path: path, Code: "schema_enum_mismatch", Message: fmt.Sprintf("%s has unsupported value", path)})
	}
	properties, _ := schema["properties"].(map[string]any)
	required := schemaStringList(schema["required"])
	if len(properties) == 0 && len(required) == 0 {
		return
	}
	object, ok := value.(map[string]any)
	if !ok {
		*errors = append(*errors, SchemaError{Path: path, Code: "schema_object_required", Message: path + " must be object"})
		return
	}
	for _, name := range required {
		if _, ok := object[name]; !ok {
			childPath := path + "." + name
			*errors = append(*errors, SchemaError{Path: childPath, Code: "schema_required_missing", Message: childPath + " is required"})
		}
	}
	for name, rawSchema := range properties {
		childSchema, ok := rawSchema.(map[string]any)
		if !ok {
			continue
		}
		if child, ok := object[name]; ok {
			validateSchemaAt(child, childSchema, path+"."+name, errors)
		}
	}
}

// MatchesSchemaType reports whether a value satisfies a schema type string.
func MatchesSchemaType(value any, schemaType string) bool {
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
		return schemaInteger(value)
	case "boolean":
		_, ok := value.(bool)
		return ok
	case "null":
		return value == nil
	default:
		return true
	}
}

// schemaInteger reports whether a numeric value is integral.
func schemaInteger(value any) bool {
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

// containsEqual reports whether a list contains a deeply equal value.
func containsEqual(values []any, target any) bool {
	for _, value := range values {
		if reflect.DeepEqual(value, target) {
			return true
		}
	}
	return false
}

// schemaStringList converts a decoded JSON string list.
func schemaStringList(value any) []string {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		if text, ok := item.(string); ok && strings.TrimSpace(text) != "" {
			out = append(out, strings.TrimSpace(text))
		}
	}
	return out
}
