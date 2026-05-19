// This file implements deterministic workflow data assertions.
package actions

import (
	"context"
	"fmt"
	"math"
	"reflect"
	"strconv"
	"strings"
)

// dataAssert checks workflow input using dotted paths and deterministic modes.
func dataAssert(_ context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	checks := assertionChecks(args)
	if len(checks) == 0 {
		return nil, fmt.Errorf("data.assert requires at least one check")
	}
	results := make([]map[string]any, 0, len(checks))
	for _, check := range checks {
		passed, message := evaluateAssertion(execCtx.Input, check)
		results = append(results, map[string]any{
			"path":   check.Path,
			"mode":   check.Mode,
			"passed": passed,
		})
		if !passed {
			return map[string]any{"passed": false, "checks": results}, fmt.Errorf("data.assert %s %s failed: %s", check.Path, check.Mode, message)
		}
	}
	return map[string]any{"passed": true, "checks": results}, nil
}

// assertionChecks normalizes single-check or checks-list arguments.
func assertionChecks(args map[string]any) []assertionCheck {
	if rawChecks, ok := args["checks"].([]any); ok {
		checks := make([]assertionCheck, 0, len(rawChecks))
		for _, item := range rawChecks {
			if itemMap, ok := item.(map[string]any); ok {
				checks = append(checks, assertionCheckFromMap(itemMap))
			}
		}
		return checks
	}
	return []assertionCheck{assertionCheckFromMap(args)}
}

// assertionCheckFromMap converts generic workflow args into a typed check.
func assertionCheckFromMap(values map[string]any) assertionCheck {
	mode, _ := values["mode"].(string)
	path, _ := values["path"].(string)
	return assertionCheck{
		Path:   strings.TrimSpace(path),
		Mode:   strings.TrimSpace(mode),
		Value:  values["value"],
		Schema: schemaArg(values),
	}
}

// schemaArg returns either schema or value for schema assertions.
func schemaArg(values map[string]any) map[string]any {
	if schema, ok := values["schema"].(map[string]any); ok {
		return schema
	}
	if schema, ok := values["value"].(map[string]any); ok {
		return schema
	}
	return nil
}

// evaluateAssertion applies one assertion to input data.
func evaluateAssertion(input map[string]any, check assertionCheck) (bool, string) {
	if check.Path == "" {
		return false, "path is required"
	}
	value, exists := resolveDottedPath(input, check.Path)
	switch strings.TrimSpace(check.Mode) {
	case "equals":
		return reflect.DeepEqual(value, check.Value), fmt.Sprintf("got %v, want %v", value, check.Value)
	case "not_equals":
		return !reflect.DeepEqual(value, check.Value), fmt.Sprintf("got disallowed value %v", value)
	case "exists":
		return exists, "path does not exist"
	case "schema":
		if !exists {
			return false, "path does not exist"
		}
		errors := validateSchema(value, check.Schema)
		return len(errors) == 0, strings.Join(errors, "; ")
	default:
		return false, "mode must be equals, not_equals, exists, or schema"
	}
}

// resolveDottedPath looks up one dotted path in maps and arrays.
func resolveDottedPath(input any, path string) (any, bool) {
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

// validateSchema checks a deterministic JSON-schema subset.
func validateSchema(value any, schema map[string]any) []string {
	if len(schema) == 0 {
		return []string{"schema is required"}
	}
	var errors []string
	validateSchemaAt(value, schema, "$", &errors)
	return errors
}

// validateSchemaAt recursively checks a value against one schema object.
func validateSchemaAt(value any, schema map[string]any, path string, errors *[]string) {
	if schemaType, _ := schema["type"].(string); strings.TrimSpace(schemaType) != "" && !matchesSchemaType(value, schemaType) {
		*errors = append(*errors, fmt.Sprintf("%s must be %s", path, schemaType))
		return
	}
	properties, _ := schema["properties"].(map[string]any)
	required := schemaStringList(schema["required"])
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
		childSchema, ok := rawSchema.(map[string]any)
		if !ok {
			continue
		}
		if child, ok := object[name]; ok {
			validateSchemaAt(child, childSchema, path+"."+name, errors)
		}
	}
}

// matchesSchemaType reports whether a value matches one JSON schema type.
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
		case float64, float32, int, int64, int32:
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
	case int, int64, int32:
		return true
	case float64:
		return math.Trunc(typed) == typed
	case float32:
		return math.Trunc(float64(typed)) == float64(typed)
	default:
		return false
	}
}

// schemaStringList converts a decoded schema list to strings.
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

// assertionCheck stores one normalized data.assert check.
type assertionCheck struct {
	Path   string
	Mode   string
	Value  any
	Schema map[string]any
}
