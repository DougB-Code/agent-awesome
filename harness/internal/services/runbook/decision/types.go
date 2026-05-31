// This file defines ordered runbook decision rules.
package decision

import (
	"encoding/json"
	"fmt"
	"strings"

	"agentawesome/internal/services/runbook/envelope"
	runbookexpr "agentawesome/internal/services/runbook/expr"
	"agentawesome/internal/services/runbook/jsondata"
)

const (
	// FacetRoute stores the selected route on decision output envelopes.
	FacetRoute = "decision.route"
	// FacetRuleID stores the selected rule id on decision output envelopes.
	FacetRuleID = "decision.rule_id"
	// generatedRuleIDFormat creates stable ids for rules without explicit ids.
	generatedRuleIDFormat = "rule_%d"
)

// Definition stores one ordered decision table.
type Definition struct {
	Rules   []Rule `json:"rules,omitempty" yaml:"rules,omitempty"`
	Default string `json:"default,omitempty" yaml:"default,omitempty"`
}

// Rule stores one first-match decision route.
type Rule struct {
	ID    string `json:"id,omitempty" yaml:"id,omitempty"`
	Route string `json:"route" yaml:"route"`
	When  When   `json:"when" yaml:"when"`
}

// When stores a deterministic condition over an input envelope.
type When struct {
	Expr string `json:"expr,omitempty" yaml:"expr,omitempty"`
	Path string `json:"path,omitempty" yaml:"path,omitempty"`
}

// Result reports the route selected by a decision definition.
type Result struct {
	Route   string `json:"route"`
	RuleID  string `json:"rule_id,omitempty"`
	Matched bool   `json:"matched"`
}

// FromMap decodes action arguments into a decision definition.
func FromMap(values map[string]any) (Definition, error) {
	encoded, err := json.Marshal(values)
	if err != nil {
		return Definition{}, fmt.Errorf("encode decision definition: %w", err)
	}
	var def Definition
	if err := json.Unmarshal(encoded, &def); err != nil {
		return Definition{}, fmt.Errorf("decode decision definition: %w", err)
	}
	return def, nil
}

// Validate checks a decision definition for deterministic routing.
func Validate(def Definition) error {
	if strings.TrimSpace(def.Default) == "" {
		return fmt.Errorf("decision default route is required")
	}
	seenRuleIDs := map[string]struct{}{}
	for index, rule := range def.Rules {
		path := fmt.Sprintf("rules.%d", index)
		if strings.TrimSpace(rule.Route) == "" {
			return fmt.Errorf("%s.route is required", path)
		}
		if strings.TrimSpace(rule.ID) != "" {
			if _, ok := seenRuleIDs[strings.TrimSpace(rule.ID)]; ok {
				return fmt.Errorf("decision rule id %q is duplicated", rule.ID)
			}
			seenRuleIDs[strings.TrimSpace(rule.ID)] = struct{}{}
		}
		if err := validateWhen(rule.When, true, path+".when"); err != nil {
			return err
		}
	}
	return nil
}

// ValidateWhen checks an optional edge condition.
func ValidateWhen(when When) error {
	return validateWhen(when, false, "when")
}

// Evaluate returns the first matching route or the default route.
func Evaluate(def Definition, input envelope.Envelope) (Result, error) {
	if err := Validate(def); err != nil {
		return Result{}, err
	}
	input.Normalize()
	for index, rule := range def.Rules {
		ok, err := MatchWhen(rule.When, input)
		if err != nil {
			return Result{}, fmt.Errorf("decision rule %q: %w", ruleIdentity(rule, index), err)
		}
		if ok {
			return Result{Route: strings.TrimSpace(rule.Route), RuleID: ruleIdentity(rule, index), Matched: true}, nil
		}
	}
	return Result{Route: strings.TrimSpace(def.Default), Matched: false}, nil
}

// MatchWhen evaluates one condition against an input envelope.
func MatchWhen(when When, input envelope.Envelope) (bool, error) {
	if err := ValidateWhen(when); err != nil {
		return false, err
	}
	input.Normalize()
	if strings.TrimSpace(when.Expr) != "" {
		emptyOutput := envelope.Empty(input.Meta.RunbookRunID, input.Meta.NodeRunID, input.Meta.Attempt)
		vars := runbookexpr.VariablesFromEnvelopes(input, emptyOutput, nil)
		return runbookexpr.EvaluateBool(when.Expr, vars)
	}
	if strings.TrimSpace(when.Path) != "" {
		value, ok := lookupPath(input, when.Path)
		return ok && runbookexpr.Truthy(value), nil
	}
	return true, nil
}

// OutputEnvelope builds the standard decision result envelope.
func OutputEnvelope(runID string, nodeID string, attempt int, result Result) envelope.Envelope {
	body := map[string]any{
		"route":   result.Route,
		"matched": result.Matched,
	}
	if strings.TrimSpace(result.RuleID) != "" {
		body["rule_id"] = strings.TrimSpace(result.RuleID)
	}
	env := envelope.New(runID, nodeID, attempt, body)
	env.SetFacet(FacetRoute, result.Route)
	if strings.TrimSpace(result.RuleID) != "" {
		env.SetFacet(FacetRuleID, result.RuleID)
	}
	env.Control.SuggestedTrigger = result.Route
	return env
}

// validateWhen checks condition structure for decision rules and edges.
func validateWhen(when When, required bool, path string) error {
	hasExpr := strings.TrimSpace(when.Expr) != ""
	hasPath := strings.TrimSpace(when.Path) != ""
	if hasExpr && hasPath {
		return fmt.Errorf("%s must declare expr or path, not both", path)
	}
	if required && !hasExpr && !hasPath {
		return fmt.Errorf("%s must declare expr or path", path)
	}
	return nil
}

// ruleIdentity returns an explicit or stable generated rule id.
func ruleIdentity(rule Rule, index int) string {
	if strings.TrimSpace(rule.ID) != "" {
		return strings.TrimSpace(rule.ID)
	}
	return fmt.Sprintf(generatedRuleIDFormat, index+1)
}

// lookupPath resolves a decision path from the input envelope.
func lookupPath(input envelope.Envelope, path string) (any, bool) {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return nil, false
	}
	switch {
	case strings.HasPrefix(trimmed, "input.facets."):
		key := strings.TrimPrefix(trimmed, "input.facets.")
		if value, ok := input.Facets[key]; ok {
			return value, true
		}
		return jsondata.Dotted(input.Facets, key)
	case strings.HasPrefix(trimmed, "input.body."):
		body := map[string]any{"kind": input.Body.Kind, "value": input.Body.Value}
		return jsondata.Dotted(body, strings.TrimPrefix(trimmed, "input.body."))
	case strings.HasPrefix(trimmed, "input."):
		return jsondata.Dotted(input.ToMap(), strings.TrimPrefix(trimmed, "input."))
	default:
		return jsondata.Dotted(input.Body.Value, trimmed)
	}
}
