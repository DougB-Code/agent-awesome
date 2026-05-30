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

// TestUnresolvedInputRefPathsFindsRemainingTokens verifies unresolved refs can be reported clearly.
func TestUnresolvedInputRefPathsFindsRemainingTokens(t *testing.T) {
	paths := unresolvedInputRefPaths("/work/${workflow_input.workdir}/${missing}")
	if len(paths) != 2 || paths[0] != "workflow_input.workdir" || paths[1] != "missing" {
		t.Fatalf("paths = %#v, want unresolved reference paths", paths)
	}
}
