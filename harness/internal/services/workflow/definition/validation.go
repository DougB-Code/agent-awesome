// This file validates hierarchical workflow state-machine definitions.
package definition

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	// KindStateMachine identifies a hierarchical durable state machine.
	KindStateMachine = "state_machine"
)

var safeIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

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
	if strings.TrimSpace(def.Kind) == KindStateMachine {
		return validateStateMachine(def, actions)
	}
	return fmt.Errorf("workflow %q kind must be %q", def.ID, KindStateMachine)
}

// validateStateMachine checks hierarchical states, entry actions, and transitions.
func validateStateMachine(def Definition, actions ActionCatalog) error {
	if len(def.States) == 0 {
		return fmt.Errorf("state machine %q must define states", def.ID)
	}
	states := map[string]StateDefinition{}
	if err := collectStateDefinitions(def.States, states, actions); err != nil {
		return err
	}
	initial := strings.TrimSpace(def.Initial)
	if initial == "" {
		initial = strings.TrimSpace(def.States[0].ID)
	}
	if _, ok := states[initial]; !ok {
		return fmt.Errorf("state machine %q initial state %q is not defined", def.ID, initial)
	}
	for _, state := range states {
		if len(state.States) > 0 {
			childInitial := strings.TrimSpace(state.Initial)
			if childInitial == "" {
				childInitial = strings.TrimSpace(state.States[0].ID)
			}
			if _, ok := states[childInitial]; !ok {
				return fmt.Errorf("state %q initial state %q is not defined", state.ID, childInitial)
			}
		}
		for _, transition := range state.Transitions {
			trigger := strings.TrimSpace(transition.Trigger)
			if trigger == "" {
				return fmt.Errorf("state %q transition trigger is required", state.ID)
			}
			if target := strings.TrimSpace(transition.To); target != "" {
				if _, ok := states[target]; !ok {
					return fmt.Errorf("state %q transition target %q is not defined", state.ID, target)
				}
			}
		}
	}
	return nil
}

// collectStateDefinitions indexes states and validates their entry actions.
func collectStateDefinitions(items []StateDefinition, states map[string]StateDefinition, actions ActionCatalog) error {
	for _, state := range items {
		if err := validateSafeID(state.ID, "state id"); err != nil {
			return err
		}
		if _, ok := states[state.ID]; ok {
			return fmt.Errorf("state machine has duplicate state %q", state.ID)
		}
		states[state.ID] = state
		for _, actionNode := range state.OnEntry {
			if err := validateSafeID(actionNode.ID, "state action id"); err != nil {
				return err
			}
			action := NodeAction(actionNode)
			if err := validateAction(action, actions); err != nil {
				return fmt.Errorf("state %s action %s: %w", state.ID, actionNode.ID, err)
			}
			if actionNode.Retry < 0 {
				return fmt.Errorf("state action %q retry must not be negative", actionNode.ID)
			}
			if err := validateDuration(actionNode.Timeout, "timeout", actionNode.ID); err != nil {
				return err
			}
			if err := validateDuration(actionNode.RetryDelay, "retry_delay", actionNode.ID); err != nil {
				return err
			}
		}
		if err := collectStateDefinitions(state.States, states, actions); err != nil {
			return err
		}
	}
	return nil
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

// validateDuration checks one optional node duration field.
func validateDuration(value string, field string, nodeID string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	if _, err := time.ParseDuration(value); err != nil {
		return fmt.Errorf("node %q %s: %w", nodeID, field, err)
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

// HasStateMachine reports whether a definition uses hierarchical states.
func HasStateMachine(def Definition) bool {
	return strings.TrimSpace(def.Kind) == KindStateMachine && len(def.States) > 0
}

// NodeAction resolves the registered action used by a state entry action.
func NodeAction(node NodeDefinition) string {
	if strings.TrimSpace(node.Uses) != "" {
		return strings.TrimSpace(node.Uses)
	}
	switch strings.ToLower(strings.TrimSpace(node.Type)) {
	case "tool":
		return "tool.call"
	case "mcp":
		return "mcp.call"
	case "command":
		return "command.execute"
	case "llm", "model":
		return "llm.generate"
	case "workflow":
		return "workflow.run"
	case "assert", "validation":
		return "data.assert"
	case "decision":
		return "decision.route"
	case "human":
		return "human.request"
	case "delay", "wait":
		return "delay.until"
	default:
		return strings.TrimSpace(node.Type)
	}
}
