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
