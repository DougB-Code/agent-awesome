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
	// StateTypeTask identifies a durable task state inside a state machine.
	StateTypeTask = "task"
)

var safeIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

var taskActionTypes = map[string]struct{}{
	"mcp.call":     {},
	"tool.call":    {},
	"workflow.run": {},
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
	default:
		return fmt.Errorf("workflow %q kind must be %q", def.ID, KindStateMachine)
	}
}

// validateStateMachine checks state and transition references.
func validateStateMachine(def Definition, actions ActionCatalog) error {
	if len(def.States) == 0 {
		return fmt.Errorf("state machine %q must define states", def.ID)
	}
	if hasTaskStates(def) {
		return validateTaskStateGraph(def, actions)
	}
	if err := validateSafeID(def.Initial, "initial state"); err != nil {
		return err
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

// validateTaskStateGraph checks task-state references and cycles.
func validateTaskStateGraph(def Definition, actions ActionCatalog) error {
	states := map[string]StateDefinition{}
	for _, state := range def.States {
		if err := validateSafeID(state.ID, "state id"); err != nil {
			return err
		}
		if _, ok := states[state.ID]; ok {
			return fmt.Errorf("state machine %q has duplicate state %q", def.ID, state.ID)
		}
		if !IsTaskState(state) {
			return fmt.Errorf("state %q cannot mix process states with task states", state.ID)
		}
		if len(state.OnEntry) > 0 || len(state.Transitions) > 0 {
			return fmt.Errorf("task state %q must not define on_entry or transitions", state.ID)
		}
		if err := validateAction(state.Uses, actions); err != nil {
			return fmt.Errorf("task state %s: %w", state.ID, err)
		}
		if err := validateTaskAction(state.Uses); err != nil {
			return fmt.Errorf("task state %s: %w", state.ID, err)
		}
		if state.Retry < 0 {
			return fmt.Errorf("task state %q retry must not be negative", state.ID)
		}
		if err := validateDuration(state.Timeout, "timeout", state.ID); err != nil {
			return err
		}
		if err := validateDuration(state.RetryDelay, "retry_delay", state.ID); err != nil {
			return err
		}
		states[state.ID] = state
	}
	if strings.TrimSpace(def.Initial) != "" {
		if err := validateSafeID(def.Initial, "initial state"); err != nil {
			return err
		}
		if _, ok := states[def.Initial]; !ok {
			return fmt.Errorf("state machine %q initial state %q is not defined", def.ID, def.Initial)
		}
	}
	for _, state := range def.States {
		seenDeps := map[string]struct{}{}
		for _, dep := range state.DependsOn {
			if err := validateSafeID(dep, "state dependency"); err != nil {
				return err
			}
			if _, ok := states[dep]; !ok {
				return fmt.Errorf("task state %q depends on missing state %q", state.ID, dep)
			}
			if dep == state.ID {
				return fmt.Errorf("task state %q cannot depend on itself", state.ID)
			}
			if _, ok := seenDeps[dep]; ok {
				return fmt.Errorf("task state %q repeats dependency %q", state.ID, dep)
			}
			seenDeps[dep] = struct{}{}
		}
	}
	return validateTaskAcyclic(def.States)
}

// validateDuration checks one optional task-state duration field.
func validateDuration(value string, field string, stateID string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	if _, err := time.ParseDuration(value); err != nil {
		return fmt.Errorf("task state %q %s: %w", stateID, field, err)
	}
	return nil
}

// validateTaskAcyclic rejects task-state cycles before runtime scheduling.
func validateTaskAcyclic(states []StateDefinition) error {
	graph := map[string][]string{}
	for _, state := range states {
		graph[state.ID] = append([]string(nil), state.DependsOn...)
	}
	visiting := map[string]bool{}
	visited := map[string]bool{}
	var visit func(string) error
	visit = func(id string) error {
		if visiting[id] {
			return fmt.Errorf("task states have dependency cycle involving %q", id)
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

// validateTaskAction limits task states to deterministic tool orchestration actions.
func validateTaskAction(name string) error {
	trimmed := strings.TrimSpace(name)
	if _, ok := taskActionTypes[trimmed]; ok {
		return nil
	}
	return fmt.Errorf("action %q is not supported in task states", trimmed)
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

// HasTaskStates reports whether a definition uses the task-state workflow model.
func HasTaskStates(def Definition) bool {
	return hasTaskStates(def)
}

// IsTaskState reports whether a state is a durable executable task state.
func IsTaskState(state StateDefinition) bool {
	return strings.TrimSpace(state.Type) == StateTypeTask ||
		strings.TrimSpace(state.Uses) != "" ||
		len(state.DependsOn) > 0 ||
		strings.TrimSpace(state.Timeout) != "" ||
		state.Retry != 0 ||
		strings.TrimSpace(state.RetryDelay) != ""
}

// hasTaskStates reports whether any state declares task-state metadata.
func hasTaskStates(def Definition) bool {
	for _, state := range def.States {
		if IsTaskState(state) {
			return true
		}
	}
	return false
}
