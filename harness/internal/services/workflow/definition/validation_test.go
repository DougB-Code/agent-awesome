// This file tests target workflow graph validation rules.
package definition

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/decision"
)

// testCatalog is a minimal action catalog for validation tests.
type testCatalog map[string]bool

// Has reports whether the test action exists.
func (c testCatalog) Has(name string) bool {
	return c[strings.TrimSpace(name)]
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

// TestLoadFileAcceptsProfessionalCodingWorkflow verifies the shipped pilot workflow is deployable.
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

// TestValidateRejectsUnknownNodeAction verifies nodes cannot call unregistered actions.
func TestValidateRejectsUnknownNodeAction(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "email_triage",
		Nodes: []NodeDefinition{
			{ID: "fetch", Uses: "email.fetch"},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "not registered") {
		t.Fatalf("Validate() error = %v, want unregistered action", err)
	}
}

// TestValidateRejectsNodeCycle verifies cycles are rejected before execution.
func TestValidateRejectsNodeCycle(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "cycle",
		Nodes: []NodeDefinition{
			{ID: "a", Uses: "tool.call"},
			{ID: "b", Uses: "tool.call"},
		},
		Edges: []EdgeDefinition{
			{From: PortRef{Node: "a"}, To: PortRef{Node: "b"}},
			{From: PortRef{Node: "b"}, To: PortRef{Node: "a"}},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "cycle") {
		t.Fatalf("Validate() error = %v, want cycle error", err)
	}
}

// TestValidateRejectsUnsupportedSchedule verifies scheduler limits are explicit.
func TestValidateRejectsUnsupportedSchedule(t *testing.T) {
	err := Validate(Definition{
		Kind:     KindWorkflow,
		ID:       "frequent",
		Schedule: "*/5 * * * *",
		Nodes: []NodeDefinition{
			{ID: "tool", Uses: "tool.call"},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "invalid minute") {
		t.Fatalf("Validate() error = %v, want unsupported schedule error", err)
	}
}

// TestValidateAcceptsWorkflowGraph verifies the bounded action surface can be composed.
func TestValidateAcceptsWorkflowGraph(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "safe",
		Nodes: []NodeDefinition{
			{ID: "mcp", Uses: "mcp.call", Retry: 1, RetryDelay: "10ms"},
			{ID: "assert", Uses: "data.assert"},
			{ID: "tool", Uses: "tool.call"},
			{ID: "child", Uses: "workflow.run"},
		},
		Edges: []EdgeDefinition{
			{From: PortRef{Node: "mcp"}, To: PortRef{Node: "assert"}},
			{From: PortRef{Node: "assert"}, To: PortRef{Node: "tool"}},
			{From: PortRef{Node: "tool"}, To: PortRef{Node: "child"}},
		},
	}, testCatalog{"mcp.call": true, "data.assert": true, "tool.call": true, "workflow.run": true})

	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
}

// TestValidateRejectsInvalidNodeTimeout verifies bad runtime policy is caught early.
func TestValidateRejectsInvalidNodeTimeout(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "bad_timeout",
		Nodes: []NodeDefinition{
			{ID: "tool", Uses: "tool.call", Timeout: "soon"},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "timeout") {
		t.Fatalf("Validate() error = %v, want timeout parse error", err)
	}
}

// TestValidateRejectsMissingMappingRef verifies adapter references are deterministic.
func TestValidateRejectsMissingMappingRef(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "missing_mapping",
		Nodes: []NodeDefinition{
			{ID: "source", Uses: "tool.call"},
			{ID: "target", Uses: "tool.call"},
		},
		Edges: []EdgeDefinition{
			{From: PortRef{Node: "source"}, To: PortRef{Node: "target"}, Adapter: adaptersWithMappingRef("not_defined")},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "mappingRef") {
		t.Fatalf("Validate() error = %v, want missing mapping reference", err)
	}
}

// TestValidateRejectsAmbiguousEdgeCondition verifies conditional edges declare one predicate source.
func TestValidateRejectsAmbiguousEdgeCondition(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "ambiguous_edge",
		Nodes: []NodeDefinition{
			{ID: "source", Uses: "tool.call"},
			{ID: "target", Uses: "tool.call"},
		},
		Edges: []EdgeDefinition{
			{
				From: PortRef{Node: "source"},
				To:   PortRef{Node: "target"},
				When: decisionWhen("input.body.value.ready", "input.body.value.approved"),
			},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "expr or path, not both") {
		t.Fatalf("Validate() error = %v, want ambiguous condition error", err)
	}
}

// TestValidateRejectsIncompatibleDirectEdge verifies declared contracts guard edges.
func TestValidateRejectsIncompatibleDirectEdge(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "contract_block",
		Nodes: []NodeDefinition{
			{ID: "source", Uses: "tool.call", Output: contracts.Contract{Produces: []contracts.Carrier{{Kind: "text"}}}},
			{ID: "target", Uses: "tool.call", Input: contracts.Contract{Accepts: []contracts.Carrier{{Kind: "file", MediaTypes: []string{"application/pdf"}}}}},
		},
		Edges: []EdgeDefinition{
			{From: PortRef{Node: "source"}, To: PortRef{Node: "target"}},
		},
	}, testCatalog{"tool.call": true})

	if err == nil || !strings.Contains(err.Error(), "not contract compatible") {
		t.Fatalf("Validate() error = %v, want contract compatibility error", err)
	}
}

// TestValidateAllowsExplicitAdapterForIncompatibleEdge verifies adapters make adaptation explicit.
func TestValidateAllowsExplicitAdapterForIncompatibleEdge(t *testing.T) {
	err := Validate(Definition{
		Kind: KindWorkflow,
		ID:   "contract_adapt",
		Nodes: []NodeDefinition{
			{ID: "source", Uses: "tool.call", Output: contracts.Contract{Produces: []contracts.Carrier{{Kind: "text"}}}},
			{ID: "target", Uses: "tool.call", Input: contracts.Contract{Accepts: []contracts.Carrier{{Kind: "object"}}}},
		},
		Edges: []EdgeDefinition{
			{From: PortRef{Node: "source"}, To: PortRef{Node: "target"}, Adapter: adaptersWithKind("mapping")},
		},
	}, testCatalog{"tool.call": true})

	if err != nil {
		t.Fatalf("Validate() error = %v", err)
	}
}

// TestLoadFileAcceptsWorkflowGraph verifies YAML authors target graph definitions.
func TestLoadFileAcceptsWorkflowGraph(t *testing.T) {
	path := filepath.Join(t.TempDir(), "workflow.yaml")
	if err := os.WriteFile(path, []byte(`
kind: workflow
id: loaded_flow
nodes:
  - id: source
    type: tool
    tool: mock_tool
    with:
      arguments: {}
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	loaded, err := LoadFile(path, testCatalog{"tool.call": true})
	if err != nil {
		t.Fatalf("LoadFile() error = %v", err)
	}
	if loaded.Definition.Kind != KindWorkflow || len(loaded.Definition.Nodes) != 1 {
		t.Fatalf("definition = %#v, want workflow graph", loaded.Definition)
	}
}

// adaptersWithMappingRef builds a small adapter reference for validation tests.
func adaptersWithMappingRef(name string) adapters.Definition {
	return adapters.Definition{MappingRef: name}
}

// adaptersWithKind builds a small adapter declaration for validation tests.
func adaptersWithKind(kind string) adapters.Definition {
	return adapters.Definition{Kind: kind}
}

// decisionWhen builds an edge predicate for validation tests.
func decisionWhen(expr string, path string) decision.When {
	return decision.When{Expr: expr, Path: path}
}
