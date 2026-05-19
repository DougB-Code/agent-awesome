// This file tests declarative workflow validation rules.
package definition

import (
	"strings"
	"testing"
)

// testCatalog is a minimal action catalog for validation tests.
type testCatalog map[string]bool

// Has reports whether the test action exists.
func (c testCatalog) Has(name string) bool {
	return c[strings.TrimSpace(name)]
}

// TestValidateRejectsUnknownAction verifies definitions cannot call unregistered actions.
func TestValidateRejectsUnknownAction(t *testing.T) {
	err := Validate(Definition{
		Kind: KindDAG,
		ID:   "email_triage",
		Nodes: []NodeDefinition{
			{ID: "fetch", Uses: "email.fetch"},
		},
	}, testCatalog{"agent.run": true})

	if err == nil || !strings.Contains(err.Error(), "not registered") {
		t.Fatalf("Validate() error = %v, want unregistered action", err)
	}
}

// TestValidateRejectsDAGCycle verifies cycles are rejected before execution.
func TestValidateRejectsDAGCycle(t *testing.T) {
	err := Validate(Definition{
		Kind: KindDAG,
		ID:   "cycle",
		Nodes: []NodeDefinition{
			{ID: "a", Uses: "agent.run", DependsOn: []string{"b"}},
			{ID: "b", Uses: "agent.run", DependsOn: []string{"a"}},
		},
	}, testCatalog{"agent.run": true})

	if err == nil || !strings.Contains(err.Error(), "cycle") {
		t.Fatalf("Validate() error = %v, want cycle error", err)
	}
}

// TestValidateRejectsUnsupportedSchedule verifies scheduler limits are explicit.
func TestValidateRejectsUnsupportedSchedule(t *testing.T) {
	err := Validate(Definition{
		Kind:     KindDAG,
		ID:       "frequent",
		Schedule: "*/5 * * * *",
		Nodes: []NodeDefinition{
			{ID: "agent", Uses: "agent.run"},
		},
	}, testCatalog{"agent.run": true})

	if err == nil || !strings.Contains(err.Error(), "invalid minute") {
		t.Fatalf("Validate() error = %v, want unsupported schedule error", err)
	}
}

// TestValidateRejectsStateActionsInDAG verifies DAGs stay orchestration-only.
func TestValidateRejectsStateActionsInDAG(t *testing.T) {
	err := Validate(Definition{
		Kind: KindDAG,
		ID:   "bad_wait",
		Nodes: []NodeDefinition{
			{ID: "wait", Uses: "delay.until"},
		},
	}, testCatalog{"delay.until": true})

	if err == nil || !strings.Contains(err.Error(), "not supported in task DAGs") {
		t.Fatalf("Validate() error = %v, want DAG action surface error", err)
	}
}

// TestValidateAcceptsDAGSafeActions verifies the bounded DAG action surface.
func TestValidateAcceptsDAGSafeActions(t *testing.T) {
	err := Validate(Definition{
		Kind: KindDAG,
		ID:   "safe",
		Nodes: []NodeDefinition{
			{ID: "agent", Uses: "agent.run", Retry: 1, RetryDelay: "10ms"},
			{ID: "tool", Uses: "tool.call", DependsOn: []string{"agent"}},
			{ID: "child", Uses: "dag.run", DependsOn: []string{"tool"}},
		},
	}, testCatalog{"agent.run": true, "tool.call": true, "dag.run": true})

	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
}

// TestValidateRejectsInvalidDAGTimeout verifies bad runtime policy is caught early.
func TestValidateRejectsInvalidDAGTimeout(t *testing.T) {
	err := Validate(Definition{
		Kind: KindDAG,
		ID:   "bad_timeout",
		Nodes: []NodeDefinition{
			{ID: "agent", Uses: "agent.run", Timeout: "soon"},
		},
	}, testCatalog{"agent.run": true})

	if err == nil || !strings.Contains(err.Error(), "timeout") {
		t.Fatalf("Validate() error = %v, want timeout parse error", err)
	}
}

// TestValidateAcceptsStateMachine verifies valid state-machine definitions pass.
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
