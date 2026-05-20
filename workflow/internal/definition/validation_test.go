// This file tests declarative workflow validation rules.
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

// TestValidateRejectsLegacyGraphKind verifies executable definitions are state machines only.
func TestValidateRejectsLegacyGraphKind(t *testing.T) {
	err := Validate(Definition{
		Kind: "dag",
		ID:   "old_graph",
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), `must be "state_machine"`) {
		t.Fatalf("Validate() error = %v, want state_machine-only kind error", err)
	}
}

// TestLoadFileRejectsRootTaskGraphNodes verifies executable YAML uses states only.
func TestLoadFileRejectsRootTaskGraphNodes(t *testing.T) {
	path := filepath.Join(t.TempDir(), "leaky.yaml")
	if err := os.WriteFile(path, []byte(`
kind: state_machine
id: leaky
initial: start
states:
  - id: start
nodes:
  - id: tool
    uses: tool.call
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	if _, err := LoadFile(path, testCatalog{"tool.call": true}); err == nil || !strings.Contains(err.Error(), "field nodes not found") {
		t.Fatalf("LoadFile() error = %v, want root nodes rejected", err)
	}
}

// TestValidateRejectsUnknownTaskAction verifies task states cannot call unregistered actions.
func TestValidateRejectsUnknownTaskAction(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "email_triage",
		States: []StateDefinition{
			{ID: "fetch", Type: StateTypeTask, Uses: "email.fetch"},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "not registered") {
		t.Fatalf("Validate() error = %v, want unregistered action", err)
	}
}

// TestValidateRejectsTaskStateCycle verifies cycles are rejected before execution.
func TestValidateRejectsTaskStateCycle(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "cycle",
		States: []StateDefinition{
			{ID: "a", Type: StateTypeTask, Uses: "tool.call", DependsOn: []string{"b"}},
			{ID: "b", Type: StateTypeTask, Uses: "tool.call", DependsOn: []string{"a"}},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "cycle") {
		t.Fatalf("Validate() error = %v, want cycle error", err)
	}
}

// TestValidateRejectsUnsupportedSchedule verifies scheduler limits are explicit.
func TestValidateRejectsUnsupportedSchedule(t *testing.T) {
	err := Validate(Definition{
		Kind:     KindStateMachine,
		ID:       "frequent",
		Schedule: "*/5 * * * *",
		States: []StateDefinition{
			{ID: "tool", Type: StateTypeTask, Uses: "tool.call"},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "invalid minute") {
		t.Fatalf("Validate() error = %v, want unsupported schedule error", err)
	}
}

// TestValidateRejectsControlActionsInTaskStates verifies task states stay tool-only.
func TestValidateRejectsControlActionsInTaskStates(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "bad_wait",
		States: []StateDefinition{
			{ID: "wait", Type: StateTypeTask, Uses: "delay.until"},
		},
	}, testCatalog{"delay.until": true})

	if err == nil || !strings.Contains(err.Error(), "not supported in task states") {
		t.Fatalf("Validate() error = %v, want task action surface error", err)
	}
}

// TestValidateAcceptsTaskStateSafeActions verifies the bounded task action surface.
func TestValidateAcceptsTaskStateSafeActions(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "safe",
		States: []StateDefinition{
			{ID: "mcp", Type: StateTypeTask, Uses: "mcp.call", Retry: 1, RetryDelay: "10ms"},
			{ID: "assert", Type: StateTypeTask, Uses: "data.assert", DependsOn: []string{"mcp"}},
			{ID: "tool", Type: StateTypeTask, Uses: "tool.call", DependsOn: []string{"assert"}},
			{ID: "child", Type: StateTypeTask, Uses: "workflow.run", DependsOn: []string{"tool"}},
		},
	}, testCatalog{"mcp.call": true, "data.assert": true, "tool.call": true, "workflow.run": true})

	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
}

// TestValidateRejectsRemovedActions verifies old workflow actions are unavailable.
func TestValidateRejectsRemovedActions(t *testing.T) {
	for _, action := range []string{"cli.command", "agent.run", "dag.run"} {
		err := Validate(Definition{
			Kind: KindStateMachine,
			ID:   "removed_" + strings.ReplaceAll(action, ".", "_"),
			States: []StateDefinition{
				{ID: "task", Type: StateTypeTask, Uses: action},
			},
		}, testCatalog{action: true})
		if err == nil || !strings.Contains(err.Error(), "not supported in task states") {
			t.Fatalf("Validate(%q) error = %v, want removed action rejected", action, err)
		}
	}
}

// TestValidateRejectsInvalidTaskTimeout verifies bad runtime policy is caught early.
func TestValidateRejectsInvalidTaskTimeout(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "bad_timeout",
		States: []StateDefinition{
			{ID: "tool", Type: StateTypeTask, Uses: "tool.call", Timeout: "soon"},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "timeout") {
		t.Fatalf("Validate() error = %v, want timeout parse error", err)
	}
}

// TestValidateAcceptsStateMachine verifies valid process-state definitions pass.
func TestValidateAcceptsStateMachine(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "course_download",
		Initial: "login",
		States: []StateDefinition{
			{
				ID: "login",
				OnEntry: []ActionDefinition{
					{ID: "ask_user", Uses: "human.request"},
				},
				Transitions: []TransitionDefinition{
					{Trigger: "submitted", To: "download"},
				},
			},
			{ID: "download"},
		},
	}, testCatalog{"human.request": true})

	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
}

// TestLoadFileAcceptsNestedStateMachine verifies YAML can author composite phases.
func TestLoadFileAcceptsNestedStateMachine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested.yaml")
	if err := os.WriteFile(path, []byte(`
kind: state_machine
id: nested_flow
initial: intake
states:
  - id: intake
    initial: collect
    on_entry:
      - id: validate_input
        uses: data.assert
    transitions:
      - trigger: failed
        to: blocked
    states:
      - id: collect
        transitions:
          - trigger: succeeded
            to: done
  - id: blocked
  - id: done
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	loaded, err := LoadFile(path, testCatalog{"data.assert": true})
	if err != nil {
		t.Fatalf("LoadFile() error = %v", err)
	}
	if loaded.Definition.States[0].Initial != "collect" {
		t.Fatalf("composite initial = %q, want collect", loaded.Definition.States[0].Initial)
	}
	if len(loaded.Definition.States[0].States) != 1 {
		t.Fatalf("nested states = %#v, want one child", loaded.Definition.States[0].States)
	}
}

// TestValidateRejectsCompositeWithoutInitial verifies phases declare entry children.
func TestValidateRejectsCompositeWithoutInitial(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "missing_child_initial",
		Initial: "phase",
		States: []StateDefinition{
			{ID: "phase", States: []StateDefinition{{ID: "child"}}},
		},
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), "must define an initial substate") {
		t.Fatalf("Validate() error = %v, want missing initial substate", err)
	}
}

// TestValidateRejectsDuplicateNestedStateID verifies nested ids stay globally unique.
func TestValidateRejectsDuplicateNestedStateID(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "duplicate_nested",
		Initial: "phase",
		States: []StateDefinition{
			{
				ID:      "phase",
				Initial: "child",
				States:  []StateDefinition{{ID: "child"}},
			},
			{ID: "child"},
		},
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), `duplicate state "child"`) {
		t.Fatalf("Validate() error = %v, want duplicate nested state", err)
	}
}

// TestValidateRejectsInvalidTransitionTarget verifies transitions target real states.
func TestValidateRejectsInvalidTransitionTarget(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "bad_transition",
		Initial: "start",
		States: []StateDefinition{
			{ID: "start", Transitions: []TransitionDefinition{{Trigger: "go", To: "missing"}}},
		},
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), `target "missing" is not defined`) {
		t.Fatalf("Validate() error = %v, want invalid transition target", err)
	}
}

// TestValidateRejectsInvalidHierarchyParent verifies flat parent references are checked.
func TestValidateRejectsInvalidHierarchyParent(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "bad_parent",
		Initial: "child",
		States: []StateDefinition{
			{ID: "child", Parent: "missing"},
		},
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), `parent "missing" is not defined`) {
		t.Fatalf("Validate() error = %v, want invalid parent reference", err)
	}
}

// TestValidateRejectsNestedParentConflict verifies nested YAML cannot contradict parent fields.
func TestValidateRejectsNestedParentConflict(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "conflicting_parent",
		Initial: "phase_a",
		States: []StateDefinition{
			{
				ID:      "phase_a",
				Initial: "child",
				States:  []StateDefinition{{ID: "child", Parent: "phase_b"}},
			},
			{ID: "phase_b", Initial: "child"},
		},
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), `conflicts with containing state "phase_a"`) {
		t.Fatalf("Validate() error = %v, want nested parent conflict", err)
	}
}

// TestValidateRejectsHierarchyCycles verifies parent cycles cannot reach runtime.
func TestValidateRejectsHierarchyCycles(t *testing.T) {
	err := Validate(Definition{
		Kind:    KindStateMachine,
		ID:      "parent_cycle",
		Initial: "a",
		States: []StateDefinition{
			{ID: "a", Parent: "b"},
			{ID: "b", Parent: "a"},
		},
	}, testCatalog{})

	if err == nil || !strings.Contains(err.Error(), "cycle") {
		t.Fatalf("Validate() error = %v, want hierarchy cycle", err)
	}
}

// TestValidateRejectsHierarchicalTaskStates verifies task graphs remain flat.
func TestValidateRejectsHierarchicalTaskStates(t *testing.T) {
	err := Validate(Definition{
		Kind: KindStateMachine,
		ID:   "hierarchical_tasks",
		States: []StateDefinition{
			{
				ID:      "phase",
				Initial: "task",
				States: []StateDefinition{
					{ID: "task", Type: StateTypeTask, Uses: "tool.call"},
				},
			},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "cannot mix process states with task states") {
		t.Fatalf("Validate() error = %v, want mixed task/process hierarchy", err)
	}
}
