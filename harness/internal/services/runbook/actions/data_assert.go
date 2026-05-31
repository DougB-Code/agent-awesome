// This file implements deterministic runbook data assertions.
package actions

import (
	"context"
	"fmt"
	"reflect"
	"strings"

	"agentawesome/internal/services/runbook/jsondata"
)

// dataAssert checks runbook input using dotted paths and deterministic modes.
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

// assertionCheckFromMap converts generic runbook args into a typed check.
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
	value, exists := jsondata.Dotted(input, check.Path)
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
		errors := jsondata.ValidateSchema(value, check.Schema, "$", true)
		return len(errors) == 0, strings.Join(jsondata.SchemaMessages(errors), "; ")
	default:
		return false, "mode must be equals, not_equals, exists, or schema"
	}
}

// assertionCheck stores one normalized data.assert check.
type assertionCheck struct {
	Path   string
	Mode   string
	Value  any
	Schema map[string]any
}
