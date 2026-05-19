// This file tests deterministic data assertion actions.
package actions

import (
	"context"
	"strings"
	"testing"
)

// TestDataAssertSupportsDottedPaths verifies equals and exists checks over nested data.
func TestDataAssertSupportsDottedPaths(t *testing.T) {
	output, err := dataAssert(context.Background(), Context{Input: map[string]any{
		"plan": map[string]any{"status": "approved"},
	}}, map[string]any{
		"checks": []any{
			map[string]any{"path": "plan.status", "mode": "equals", "value": "approved"},
			map[string]any{"path": "plan", "mode": "exists"},
		},
	})
	if err != nil {
		t.Fatalf("dataAssert() error = %v", err)
	}
	if output["passed"] != true {
		t.Fatalf("output = %#v, want passed", output)
	}
}

// TestDataAssertSchemaRejectsInvalidData verifies schema mode reports failures.
func TestDataAssertSchemaRejectsInvalidData(t *testing.T) {
	_, err := dataAssert(context.Background(), Context{Input: map[string]any{
		"review": map[string]any{"status": 7},
	}}, map[string]any{
		"path": "review",
		"mode": "schema",
		"schema": map[string]any{
			"type":     "object",
			"required": []any{"status"},
			"properties": map[string]any{
				"status": map[string]any{"type": "string"},
			},
		},
	})
	if err == nil || !strings.Contains(err.Error(), "status") {
		t.Fatalf("dataAssert() error = %v, want schema failure", err)
	}
}
