// This file exposes deterministic expression evaluation helpers.
package expr

import (
	"strings"

	"github.com/google/cel-go/cel"

	"agentawesome/internal/services/runbook/envelope"
)

// VariablesFromEnvelopes builds CEL variables for input, output, and locals.
func VariablesFromEnvelopes(input envelope.Envelope, output envelope.Envelope, locals map[string]any) map[string]any {
	input.Normalize()
	output.Normalize()
	vars := map[string]any{
		"input":  input.ToMap(),
		"output": output.ToMap(),
	}
	for key, value := range locals {
		name := strings.TrimSpace(key)
		if name != "" {
			vars[name] = value
		}
	}
	return vars
}

// Evaluate runs one CEL expression against dynamic JSON-like variables.
func Evaluate(expression string, variables map[string]any) (any, error) {
	envOptions := make([]cel.EnvOption, 0, len(variables))
	vars := map[string]any{}
	for key, value := range variables {
		name := strings.TrimSpace(key)
		if name == "" {
			continue
		}
		envOptions = append(envOptions, cel.Variable(name, cel.DynType))
		vars[name] = value
	}
	env, err := cel.NewEnv(envOptions...)
	if err != nil {
		return nil, err
	}
	ast, issues := env.Compile(strings.TrimSpace(expression))
	if issues != nil && issues.Err() != nil {
		return nil, issues.Err()
	}
	program, err := env.Program(ast)
	if err != nil {
		return nil, err
	}
	value, _, err := program.Eval(vars)
	if err != nil {
		return nil, err
	}
	return value.Value(), nil
}

// EvaluateBool runs one CEL expression and coerces its result to runbook truthiness.
func EvaluateBool(expression string, variables map[string]any) (bool, error) {
	value, err := Evaluate(expression, variables)
	if err != nil {
		return false, err
	}
	if boolValue, ok := value.(bool); ok {
		return boolValue, nil
	}
	return Truthy(value), nil
}

// Truthy reports whether a JSON-like value should count as present and true.
func Truthy(value any) bool {
	switch typed := value.(type) {
	case nil:
		return false
	case bool:
		return typed
	case string:
		return strings.TrimSpace(typed) != ""
	case []any:
		return len(typed) > 0
	case map[string]any:
		return len(typed) > 0
	default:
		return true
	}
}
