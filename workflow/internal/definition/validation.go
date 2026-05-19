// This file validates declarative workflow definitions.
package definition

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	// KindStateMachine identifies a long-lived state-machine workflow.
	KindStateMachine = "state_machine"
	// KindDAG identifies a bounded dependency graph workflow.
	KindDAG = "dag"
)

var safeIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

var dagActionTypes = map[string]struct{}{
	"agent.run": {},
	"tool.call": {},
	"dag.run":   {},
}

// ActionCatalog reports whether a declarative action type is installed.
type ActionCatalog interface {
	Has(name string) bool
}

// Validate checks a workflow definition for deterministic, registered behavior.
func Validate(def Definition, actions ActionCatalog) error {
	if err := validateSafeID(def.ID, "workflow id"); err != nil {
		return err
	}
	if err := validateSchedule(def.Schedule); err != nil {
		return err
	}
	switch strings.TrimSpace(def.Kind) {
	case KindStateMachine:
		return validateStateMachine(def, actions)
	case KindDAG:
		return validateDAG(def, actions)
	default:
		return fmt.Errorf("workflow %q kind must be %q or %q", def.ID, KindStateMachine, KindDAG)
	}
}

// validateStateMachine checks state and transition references.
func validateStateMachine(def Definition, actions ActionCatalog) error {
	if err := validateSafeID(def.Initial, "initial state"); err != nil {
		return err
	}
	if len(def.States) == 0 {
		return fmt.Errorf("state machine %q must define states", def.ID)
	}
	states := map[string]StateDefinition{}
	for _, state := range def.States {
		if err := validateSafeID(state.ID, "state id"); err != nil {
			return err
		}
		if _, ok := states[state.ID]; ok {
			return fmt.Errorf("state machine %q has duplicate state %q", def.ID, state.ID)
		}
		states[state.ID] = state
		for _, action := range state.OnEntry {
			if err := validateAction(action.Uses, actions); err != nil {
				return fmt.Errorf("state %s entry action: %w", state.ID, err)
			}
		}
	}
	if _, ok := states[def.Initial]; !ok {
		return fmt.Errorf("state machine %q initial state %q is not defined", def.ID, def.Initial)
	}
	for _, state := range def.States {
		seenTriggers := map[string]struct{}{}
		for _, transition := range state.Transitions {
			if err := validateSafeID(transition.Trigger, "transition trigger"); err != nil {
				return err
			}
			if err := validateSafeID(transition.To, "transition target"); err != nil {
				return err
			}
			if _, ok := states[transition.To]; !ok {
				return fmt.Errorf("state %q transition target %q is not defined", state.ID, transition.To)
			}
			if _, ok := seenTriggers[transition.Trigger]; ok {
				return fmt.Errorf("state %q has duplicate trigger %q", state.ID, transition.Trigger)
			}
			if strings.TrimSpace(transition.Guard) != "" && strings.TrimSpace(transition.Guard) != "always" {
				return fmt.Errorf("state %q trigger %q uses unsupported guard %q", state.ID, transition.Trigger, transition.Guard)
			}
			seenTriggers[transition.Trigger] = struct{}{}
		}
	}
	return nil
}

// validateDAG checks DAG node references and cycles.
func validateDAG(def Definition, actions ActionCatalog) error {
	if len(def.Nodes) == 0 {
		return fmt.Errorf("dag %q must define nodes", def.ID)
	}
	nodes := map[string]NodeDefinition{}
	for _, node := range def.Nodes {
		if err := validateSafeID(node.ID, "node id"); err != nil {
			return err
		}
		if _, ok := nodes[node.ID]; ok {
			return fmt.Errorf("dag %q has duplicate node %q", def.ID, node.ID)
		}
		if err := validateAction(node.Uses, actions); err != nil {
			return fmt.Errorf("node %s: %w", node.ID, err)
		}
		if err := validateDAGAction(node.Uses); err != nil {
			return fmt.Errorf("node %s: %w", node.ID, err)
		}
		if node.Retry < 0 {
			return fmt.Errorf("node %q retry must not be negative", node.ID)
		}
		if node.Timeout != "" {
			if _, err := time.ParseDuration(node.Timeout); err != nil {
				return fmt.Errorf("node %q timeout: %w", node.ID, err)
			}
		}
		if node.RetryDelay != "" {
			if _, err := time.ParseDuration(node.RetryDelay); err != nil {
				return fmt.Errorf("node %q retry_delay: %w", node.ID, err)
			}
		}
		nodes[node.ID] = node
	}
	for _, node := range def.Nodes {
		seenDeps := map[string]struct{}{}
		for _, dep := range node.DependsOn {
			if err := validateSafeID(dep, "node dependency"); err != nil {
				return err
			}
			if _, ok := nodes[dep]; !ok {
				return fmt.Errorf("node %q depends on missing node %q", node.ID, dep)
			}
			if dep == node.ID {
				return fmt.Errorf("node %q cannot depend on itself", node.ID)
			}
			if _, ok := seenDeps[dep]; ok {
				return fmt.Errorf("node %q repeats dependency %q", node.ID, dep)
			}
			seenDeps[dep] = struct{}{}
		}
	}
	return validateAcyclic(def.Nodes)
}

// validateAcyclic rejects DAG cycles before go-workflow construction.
func validateAcyclic(nodes []NodeDefinition) error {
	graph := map[string][]string{}
	for _, node := range nodes {
		graph[node.ID] = append([]string(nil), node.DependsOn...)
	}
	visiting := map[string]bool{}
	visited := map[string]bool{}
	var visit func(string) error
	visit = func(id string) error {
		if visiting[id] {
			return fmt.Errorf("dag has dependency cycle involving %q", id)
		}
		if visited[id] {
			return nil
		}
		visiting[id] = true
		for _, dep := range graph[id] {
			if err := visit(dep); err != nil {
				return err
			}
		}
		visiting[id] = false
		visited[id] = true
		return nil
	}
	for id := range graph {
		if err := visit(id); err != nil {
			return err
		}
	}
	return nil
}

// validateDAGAction limits bounded DAGs to straight-shot orchestration actions.
func validateDAGAction(name string) error {
	trimmed := strings.TrimSpace(name)
	if _, ok := dagActionTypes[trimmed]; ok {
		return nil
	}
	return fmt.Errorf("action %q is not supported in task DAGs", trimmed)
}

// validateAction ensures the action is supplied by the installed registry.
func validateAction(name string, actions ActionCatalog) error {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return fmt.Errorf("action uses is required")
	}
	if actions == nil || !actions.Has(trimmed) {
		return fmt.Errorf("action %q is not registered", trimmed)
	}
	return nil
}

// validateSchedule accepts an empty schedule or a simple five-field cron shape.
func validateSchedule(value string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	fields := strings.Fields(trimmed)
	if len(fields) != 5 {
		return fmt.Errorf("schedule %q must use five-field cron syntax", trimmed)
	}
	if fields[2] != "*" || fields[3] != "*" || fields[4] != "*" {
		return fmt.Errorf("schedule %q must use daily minute/hour syntax", trimmed)
	}
	minute, err := strconv.Atoi(fields[0])
	if err != nil || minute < 0 || minute > 59 {
		return fmt.Errorf("schedule %q has invalid minute", trimmed)
	}
	hour, err := strconv.Atoi(fields[1])
	if err != nil || hour < 0 || hour > 23 {
		return fmt.Errorf("schedule %q has invalid hour", trimmed)
	}
	return nil
}

// validateSafeID checks ids used in durable records and route payloads.
func validateSafeID(value string, label string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return fmt.Errorf("%s is required", label)
	}
	if !safeIDPattern.MatchString(trimmed) {
		return fmt.Errorf("%s %q is invalid", label, trimmed)
	}
	return nil
}
