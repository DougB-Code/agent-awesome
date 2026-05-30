// This file tests workflow state-machine validation rules.
package definition

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// testCatalog is a minimal action catalog for validation tests.
type testCatalog map[string]bool

// Has reports whether the test action exists.
func (c testCatalog) Has(name string) bool {
	return c[strings.TrimSpace(name)]
}

// TestValidateRejectsUnsupportedKind verifies only state-machine definitions load.
func TestValidateRejectsUnsupportedKind(t *testing.T) {
	err := Validate(Definition{
		Kind: "workflow",
		ID:   "old_flow",
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), KindStateMachine) {
		t.Fatalf("Validate() error = %v, want state_machine kind error", err)
	}
}

// TestValidateRejectsIncompleteStateMachine verifies hierarchical states are required.
func TestValidateRejectsIncompleteStateMachine(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "old_flow",
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "must define states") {
		t.Fatalf("Validate() error = %v, want missing states error", err)
	}
}

// TestLoadFileAcceptsStateMachineShape verifies hierarchical state machines are deployable.
func TestLoadFileAcceptsStateMachineShape(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state_machine.yaml")
	if err := os.WriteFile(path, []byte(`
kind: state_machine
id: leaky
initial: start
states:
  - id: start
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	if _, err := LoadFile(path, testCatalog{}); err != nil {
		t.Fatalf("LoadFile() error = %v", err)
	}
}

// TestLoadFileAcceptsProfessionalCodingWorkflow verifies the shipped workflow is deployable.
func TestLoadFileAcceptsProfessionalCodingWorkflow(t *testing.T) {
	path := filepath.Join("..", "..", "..", "..", "workflows", "professional_coding_change.yaml")
	loaded, err := LoadFile(path, testCatalog{
		"command.execute": true,
		"data.assert":     true,
		"data.defaults":   true,
		"human.request":   true,
		"mcp.call":        true,
	})
	if err != nil {
		t.Fatalf("LoadFile() error = %v", err)
	}
	if loaded.Definition.Kind != KindStateMachine {
		t.Fatalf("Kind = %q, want %q", loaded.Definition.Kind, KindStateMachine)
	}
}

// TestValidateRejectsUnknownEntryAction verifies actions must be registered.
func TestValidateRejectsUnknownEntryAction(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "email_triage",
		States: []StateDefinition{{
			ID: "start",
			OnEntry: []NodeDefinition{
				{ID: "fetch", Uses: "email.fetch"},
			},
		}},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "not registered") {
		t.Fatalf("Validate() error = %v, want unregistered action", err)
	}
}

// TestValidateRejectsUnsupportedSchedule verifies scheduler limits are explicit.
func TestValidateRejectsUnsupportedSchedule(t *testing.T) {
	err := Validate(Definition{
		Kind:     KindStateMachine,
		ID:       "frequent",
		Schedule: "*/5 * * * *",
		States: []StateDefinition{{
			ID: "start",
		}},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "invalid minute") {
		t.Fatalf("Validate() error = %v, want unsupported schedule error", err)
	}
}

// TestValidateAcceptsHierarchicalStateMachine verifies the bounded action surface can be composed.
func TestValidateAcceptsHierarchicalStateMachine(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "safe",
		Initial: "mcp",
		States: []StateDefinition{
			{
				ID: "mcp",
				OnEntry: []NodeDefinition{
					{ID: "mcp_call", Uses: "mcp.call", Retry: 1, RetryDelay: "10ms"},
				},
				Transitions: []TransitionDefinition{{Trigger: "succeeded", To: "tool"}},
			},
			{
				ID: "tool",
				OnEntry: []NodeDefinition{
					{ID: "tool_call", Uses: "tool.call"},
					{ID: "child_call", Uses: "workflow.run"},
				},
			},
		},
	}, testCatalog{"mcp.call": true, "tool.call": true, "workflow.run": true})

	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
}

// TestValidateRejectsInvalidActionTimeout verifies bad runtime policy is caught early.
func TestValidateRejectsInvalidActionTimeout(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "bad_timeout",
		States: []StateDefinition{{
			ID: "start",
			OnEntry: []NodeDefinition{
				{ID: "tool", Uses: "tool.call", Timeout: "soon"},
			},
		}},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "timeout") {
		t.Fatalf("Validate() error = %v, want timeout parse error", err)
	}
}

// TestValidateRejectsMissingTransitionTarget verifies transitions stay explicit.
func TestValidateRejectsMissingTransitionTarget(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "missing_target",
		States: []StateDefinition{{
			ID:          "start",
			Transitions: []TransitionDefinition{{Trigger: "succeeded", To: "missing"}},
		}},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "transition target") {
		t.Fatalf("Validate() error = %v, want missing transition target", err)
	}
}
