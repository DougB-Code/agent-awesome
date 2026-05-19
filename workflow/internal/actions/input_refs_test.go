// This file tests action input reference expansion.
package actions

import "testing"

// TestResolveInputRefsReplacesNestedValues verifies action args can use parent outputs.
func TestResolveInputRefsReplacesNestedValues(t *testing.T) {
	resolved := resolveInputRefs(map[string]any{
		"worktree_path": "${prepare.worktree_path}",
		"message":       "commit ${plan.output.summary}",
	}, map[string]any{
		"prepare": map[string]any{"worktree_path": "/tmp/wt"},
		"plan":    map[string]any{"output": map[string]any{"summary": "ok"}},
	})
	values, _ := resolved.(map[string]any)
	if values["worktree_path"] != "/tmp/wt" || values["message"] != "commit ok" {
		t.Fatalf("resolved = %#v, want substituted values", values)
	}
}
