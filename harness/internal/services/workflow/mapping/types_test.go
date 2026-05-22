// This file tests deterministic AA Mapping Spec execution.
package mapping

import (
	"slices"
	"testing"

	"agentawesome/internal/services/workflow/envelope"
)

// TestApplyMapsCalculatedFieldsAndAggregates verifies core mapping operations.
func TestApplyMapsCalculatedFieldsAndAggregates(t *testing.T) {
	input := envelope.New("run_1", "source", 1, map[string]any{
		"subject": "Q2 invoice",
		"lines": []any{
			map[string]any{"qty": 2.0, "price": 5.0},
			map[string]any{"qty": 3.0, "price": 7.0},
		},
	})
	input.SetFacet("email.sender", "billing@example.test")

	output, diagnostics := Apply(Spec{
		Steps: []StepDefinition{
			{Set: &SetStep{Target: "approval.title", Value: ValueSpec{Expr: "'Approve: ' + input.body.value.subject"}}},
			{Set: &SetStep{Target: "approval.requester", Value: ValueSpec{Path: "input.facets.email.sender"}}},
			{Foreach: &ForeachStep{
				Source: "input.body.value.lines",
				As:     "line",
				Target: "lines",
				Map: map[string]ValueSpec{
					"lineTotal": {Expr: "line.qty * line.price"},
				},
			}},
			{Aggregate: &AggregateStep{Source: "output.body.value.lines", Target: "approval.total", Op: "sum", Expr: "item.lineTotal"}},
		},
		Validate: []ValidationRule{{Expr: `output.facets["approval.total"] >= 31`, Message: "total is required"}},
	}, input)

	if len(diagnostics) != 0 {
		t.Fatalf("diagnostics = %#v, want none", diagnostics)
	}
	if output.Facets["approval.title"] != "Approve: Q2 invoice" {
		t.Fatalf("title facet = %#v", output.Facets["approval.title"])
	}
	if output.Facets["approval.requester"] != "billing@example.test" {
		t.Fatalf("requester facet = %#v", output.Facets["approval.requester"])
	}
	if output.Facets["approval.total"] != 31.0 {
		t.Fatalf("total facet = %#v", output.Facets["approval.total"])
	}
}

// TestPreviewReportsRequiredAndProducedPaths verifies design-time mapping preview metadata.
func TestPreviewReportsRequiredAndProducedPaths(t *testing.T) {
	input := envelope.New("run_1", "source", 1, map[string]any{"subject": "Invoice"})
	input.SetFacet("email.sender", "billing@example.test")

	result := Preview(Spec{
		APIVersion: "aa.mapping/v1",
		Kind:       "Mapping",
		Input: IOContract{Expects: ShapeContract{
			Kind:   "object",
			Facets: []string{"email.sender"},
		}},
		Steps: []StepDefinition{
			{Set: &SetStep{
				Target: "approval.title",
				Value:  ValueSpec{Expr: "'Approve: ' + input.body.value.subject"},
			}},
			{Set: &SetStep{
				Target: "output.facets.approval.requester",
				Value:  ValueSpec{Path: "input.facets.email.sender"},
			}},
		},
	}, input)

	if len(result.Diagnostics) != 0 {
		t.Fatalf("diagnostics = %#v, want none", result.Diagnostics)
	}
	if !slices.Contains(result.RequiredPaths, "input.body.kind") ||
		!slices.Contains(result.RequiredPaths, "input.facets.email.sender") ||
		!slices.Contains(result.RequiredPaths, "input.body.value.subject") {
		t.Fatalf("required paths = %#v, want input kind, sender facet, and subject", result.RequiredPaths)
	}
	if !slices.Contains(result.ProducedPaths, "output.body.value.approval.title") ||
		!slices.Contains(result.ProducedPaths, "output.facets.approval.requester") {
		t.Fatalf("produced paths = %#v, want title and requester", result.ProducedPaths)
	}
}

// TestValidateRejectsAmbiguousMappingSteps verifies malformed mapping specs fail statically.
func TestValidateRejectsAmbiguousMappingSteps(t *testing.T) {
	diagnostics := Validate(Spec{
		Steps: []StepDefinition{
			{
				Set:     &SetStep{Target: "a", Value: ValueSpec{Path: "input.body.value.a"}},
				Default: &DefaultStep{Target: "a", Value: "fallback"},
			},
		},
	})

	if len(diagnostics) == 0 {
		t.Fatalf("Validate() diagnostics = nil, want ambiguous operation error")
	}
}

// TestApplyEvaluatesCELExpressions verifies CEL is the primary expression path.
func TestApplyEvaluatesCELExpressions(t *testing.T) {
	input := envelope.New("run_1", "source", 1, map[string]any{"amount": 125.0})
	input.SetFacet("email.subject", "Invoice")

	output, diagnostics := Apply(Spec{
		Steps: []StepDefinition{
			{Set: &SetStep{
				Target: "approval.title",
				Value:  ValueSpec{Expr: `"Approve " + input.facets["email.subject"]`},
			}},
			{Set: &SetStep{
				Target: "approval.large",
				Value:  ValueSpec{Expr: "input.body.value.amount > 100"},
			}},
		},
	}, input)

	if len(diagnostics) != 0 {
		t.Fatalf("diagnostics = %#v, want none", diagnostics)
	}
	if output.Facets["approval.title"] != "Approve Invoice" {
		t.Fatalf("approval.title = %#v, want Approve Invoice", output.Facets["approval.title"])
	}
	if output.Facets["approval.large"] != true {
		t.Fatalf("approval.large = %#v, want true", output.Facets["approval.large"])
	}
}
