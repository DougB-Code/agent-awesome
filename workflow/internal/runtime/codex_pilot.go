// This file defines the built-in Codex CLI pilot workflow template.
package runtime

import (
	"workflow/internal/definition"
	"workflow/internal/store"
)

// codexCLIPilotTemplate returns a generic workflow composed from MCP, command, and source-control tools.
func codexCLIPilotTemplate() store.TemplateRecord {
	return store.TemplateRecord{
		ID:          "codex_cli_pilot",
		Name:        "Codex CLI Pilot",
		Description: "Plan, implement, test, review, clean up, commit, push, and open a PR through generic boundaries.",
		Category:    "source_control",
		Tags:        []string{"codex", "command", "sourcecontrol", "state-machine"},
		Parameters: []map[string]any{
			{"id": "mcp_endpoint", "label": "MCP manager endpoint", "type": "string", "default": "http://127.0.0.1:8094/mcp"},
			{"id": "sourcecontrol_server_id", "label": "Source-control server id", "type": "string", "default": "sourcecontrol"},
			{"id": "command_server_id", "label": "Command server id", "type": "string", "default": "command"},
		},
		Requirements: map[string]any{
			"actions": []any{"mcp.call", "data.assert"},
			"input":   []any{"repository_path", "worktree_path", "branch", "base_ref", "remote", "commit_message"},
		},
		Body: map[string]any{
			"kind":        definition.KindStateMachine,
			"id":          "codex_cli_pilot",
			"name":        "Codex CLI Pilot",
			"description": "Generic Codex CLI pilot workflow.",
			"states": []any{
				mcpTask("prepare", nil, "mcp.call", map[string]any{
					"endpoint": "{{mcp_endpoint}}",
					"tool":     "mcp.call",
					"arguments": map[string]any{
						"server_id": "{{sourcecontrol_server_id}}",
						"tool":      "sourcecontrol.prepare_worktree",
						"arguments": map[string]any{
							"repository_path": "${repository_path}",
							"worktree_path":   "${worktree_path}",
							"branch":          "${branch}",
							"base_ref":        "${base_ref}",
						},
					},
				}),
				mcpTask("plan", []string{"prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_plan")),
				assertTask("assert_plan", []string{"plan"}, []any{
					map[string]any{"path": "plan.output.plan.compliant", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.project_conventions", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.solid", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.agents", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.relevant_skills", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.no_unnecessary_backwards_compatibility", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.no_duplicate_implementations", "mode": "equals", "value": true},
					map[string]any{"path": "plan.output.plan.no_hardcoded_values", "mode": "equals", "value": true},
				}),
				mcpTask("backup", []string{"assert_plan", "prepare"}, "mcp.call", sourceControlArgs("{{mcp_endpoint}}", "{{sourcecontrol_server_id}}", "sourcecontrol.backup")),
				mcpTask("implement", []string{"backup", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_implement")),
				assertTask("assert_implement", []string{"implement"}, []any{
					map[string]any{"path": "implement.status", "mode": "equals", "value": "succeeded"},
					map[string]any{"path": "implement.validation.valid", "mode": "equals", "value": true},
				}),
				mcpTask("test", []string{"assert_implement", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "test")),
				assertTask("assert_tests", []string{"test"}, []any{
					map[string]any{"path": "test.status", "mode": "equals", "value": "succeeded"},
					map[string]any{"path": "test.output.passed", "mode": "equals", "value": true},
				}),
				mcpTask("post_review", []string{"assert_tests", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_review")),
				mcpTask("cleanup", []string{"post_review", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_cleanup")),
				assertTask("assert_cleanup", []string{"cleanup"}, []any{
					map[string]any{"path": "cleanup.status", "mode": "equals", "value": "succeeded"},
					map[string]any{"path": "cleanup.validation.valid", "mode": "equals", "value": true},
				}),
				mcpTask("retest", []string{"assert_cleanup", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "test")),
				assertTask("assert_retest", []string{"retest"}, []any{
					map[string]any{"path": "retest.status", "mode": "equals", "value": "succeeded"},
					map[string]any{"path": "retest.output.passed", "mode": "equals", "value": true},
				}),
				mcpTask("final_review", []string{"assert_retest", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_review")),
				assertTask("assert_review", []string{"final_review"}, []any{map[string]any{"path": "final_review.output.deviations", "mode": "equals", "value": []any{}}}),
				mcpTask("commit", []string{"assert_review", "prepare"}, "mcp.call", map[string]any{
					"endpoint": "{{mcp_endpoint}}",
					"tool":     "mcp.call",
					"arguments": map[string]any{
						"server_id": "{{sourcecontrol_server_id}}",
						"tool":      "sourcecontrol.commit",
						"arguments": map[string]any{
							"worktree_path": "${prepare.worktree_path}",
							"message":       "${workflow_input.commit_message}",
						},
					},
				}),
				mcpTask("push", []string{"commit", "prepare"}, "mcp.call", map[string]any{
					"endpoint": "{{mcp_endpoint}}",
					"tool":     "mcp.call",
					"arguments": map[string]any{
						"server_id": "{{sourcecontrol_server_id}}",
						"tool":      "sourcecontrol.push",
						"arguments": map[string]any{
							"worktree_path": "${prepare.worktree_path}",
							"remote":        "${workflow_input.remote}",
							"branch":        "${workflow_input.branch}",
						},
					},
				}),
				mcpTask("open_pr", []string{"push", "prepare"}, "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "gh_pr_create")),
				assertTask("assert_pr", []string{"open_pr"}, []any{map[string]any{"path": "open_pr.output.url", "mode": "exists"}}),
			},
		},
	}
}

// mcpTask builds one task-state body.
func mcpTask(id string, dependsOn []string, uses string, with map[string]any) map[string]any {
	state := map[string]any{"id": id, "type": definition.StateTypeTask, "uses": uses, "with": with}
	if len(dependsOn) > 0 {
		state["depends_on"] = dependsOn
	}
	return state
}

// assertTask builds one data.assert task state.
func assertTask(id string, dependsOn []string, checks []any) map[string]any {
	return mcpTask(id, dependsOn, "data.assert", map[string]any{"checks": checks})
}

// commandExecuteArgs builds arguments for command.execute through the MCP manager.
func commandExecuteArgs(endpoint string, serverID string, templateID string) map[string]any {
	return map[string]any{
		"endpoint": endpoint,
		"tool":     "mcp.call",
		"arguments": map[string]any{
			"server_id": serverID,
			"tool":      "command.execute",
			"arguments": map[string]any{
				"template_id": templateID,
				"cwd":         "${prepare.worktree_path}",
			},
		},
	}
}

// sourceControlArgs builds arguments for a source-control worktree operation.
func sourceControlArgs(endpoint string, serverID string, tool string) map[string]any {
	return map[string]any{
		"endpoint": endpoint,
		"tool":     "mcp.call",
		"arguments": map[string]any{
			"server_id": serverID,
			"tool":      tool,
			"arguments": map[string]any{
				"worktree_path": "${prepare.worktree_path}",
			},
		},
	}
}
