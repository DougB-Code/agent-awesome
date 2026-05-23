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

// TestDataDefaultsMergesDeclarativeDefaults verifies defaults are overridable.
func TestDataDefaultsMergesDeclarativeDefaults(t *testing.T) {
	output, err := dataDefaults(context.Background(), Context{Input: map[string]any{
		"workflow_input": map[string]any{
			"change_request": "Fix the cache bug",
			"remote":         "upstream",
		},
	}}, map[string]any{
		"input": "${workflow_input}",
		"defaults": map[string]any{
			"branch_summary": "${workflow_input.change_request}",
			"commit_message": "${workflow_input.change_request}",
			"base_ref":       "HEAD",
			"remote":         "origin",
		},
	})
	if err != nil {
		t.Fatalf("dataDefaults() error = %v", err)
	}
	if output["branch_summary"] != "Fix the cache bug" {
		t.Fatalf("branch_summary = %#v, want change request default", output["branch_summary"])
	}
	if output["remote"] != "upstream" {
		t.Fatalf("remote = %#v, want explicit input", output["remote"])
	}
	if output["base_ref"] != "HEAD" {
		t.Fatalf("base_ref = %#v, want default", output["base_ref"])
	}
}
