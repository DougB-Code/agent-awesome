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
			"actions": []any{"mcp.call", "data.assert", "human.request"},
			"input":   []any{"repository_path", "worktree_path", "branch", "base_ref", "remote", "commit_message"},
		},
		Body: map[string]any{
			"kind":        definition.KindStateMachine,
			"id":          "codex_cli_pilot",
			"name":        "Codex CLI Pilot",
			"description": "Generic Codex CLI pilot workflow.",
			"initial":     "intake",
			"states": []any{
				codexPhase("intake", "assert_request", []any{
					codexActionState("assert_request", "data.assert", map[string]any{"checks": []any{
						map[string]any{"path": "workflow_input.repository_path", "mode": "exists"},
						map[string]any{"path": "workflow_input.worktree_path", "mode": "exists"},
						map[string]any{"path": "workflow_input.branch", "mode": "exists"},
						map[string]any{"path": "workflow_input.base_ref", "mode": "exists"},
						map[string]any{"path": "workflow_input.commit_message", "mode": "exists"},
					}}, codexTransitions("request_approval", "blocked")),
					codexActionState("request_approval", "human.request", map[string]any{
						"prompt":  "Approve starting the coding change workflow?",
						"payload": map[string]any{"workflow": "codex_cli_pilot"},
					}, []any{map[string]any{"trigger": "approved", "to": "preparation"}, map[string]any{"trigger": "rejected", "to": "blocked"}}),
				}),
				codexPhase("preparation", "prepare", []any{
					codexActionState("prepare", "mcp.call", map[string]any{
						"endpoint": "{{mcp_endpoint}}",
						"tool":     "mcp.call",
						"arguments": map[string]any{
							"server_id": "{{sourcecontrol_server_id}}",
							"tool":      "sourcecontrol.prepare_worktree",
							"arguments": map[string]any{
								"repository_path": "${workflow_input.repository_path}",
								"worktree_path":   "${workflow_input.worktree_path}",
								"branch":          "${workflow_input.branch}",
								"base_ref":        "${workflow_input.base_ref}",
							},
						},
					}, codexTransitions("plan", "blocked")),
					codexActionState("plan", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_plan"), codexTransitions("assert_plan", "blocked")),
					codexActionState("assert_plan", "data.assert", map[string]any{"checks": codexPlanChecks()}, codexTransitions("backup", "blocked")),
					codexActionState("backup", "mcp.call", sourceControlArgs("{{mcp_endpoint}}", "{{sourcecontrol_server_id}}", "sourcecontrol.backup"), codexTransitions("change", "blocked")),
				}),
				codexPhase("change", "implement", []any{
					codexActionState("implement", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_implement"), codexTransitions("assert_implement", "blocked")),
					codexActionState("assert_implement", "data.assert", map[string]any{"checks": []any{
						map[string]any{"path": "implement.status", "mode": "equals", "value": "succeeded"},
						map[string]any{"path": "implement.validation.valid", "mode": "equals", "value": true},
					}}, codexTransitions("quality_loop", "blocked")),
				}),
				codexPhase("quality_loop", "test", []any{
					codexActionState("test", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "test"), codexTransitions("assert_tests", "blocked")),
					codexActionState("assert_tests", "data.assert", map[string]any{"checks": []any{
						map[string]any{"path": "test.status", "mode": "equals", "value": "succeeded"},
						map[string]any{"path": "test.output.passed", "mode": "equals", "value": true},
					}}, codexTransitions("post_review", "blocked")),
					codexActionState("post_review", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_review"), codexTransitions("cleanup", "blocked")),
					codexActionState("cleanup", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_cleanup"), codexTransitions("assert_cleanup", "blocked")),
					codexActionState("assert_cleanup", "data.assert", map[string]any{"checks": []any{
						map[string]any{"path": "cleanup.status", "mode": "equals", "value": "succeeded"},
						map[string]any{"path": "cleanup.validation.valid", "mode": "equals", "value": true},
					}}, codexTransitions("retest", "blocked")),
					codexActionState("retest", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "test"), codexTransitions("assert_retest", "blocked")),
					codexActionState("assert_retest", "data.assert", map[string]any{"checks": []any{
						map[string]any{"path": "retest.status", "mode": "equals", "value": "succeeded"},
						map[string]any{"path": "retest.output.passed", "mode": "equals", "value": true},
					}}, codexTransitions("final_review", "blocked")),
					codexActionState("final_review", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "codex_review"), codexTransitions("assert_review", "blocked")),
					codexActionState("assert_review", "data.assert", map[string]any{"checks": []any{map[string]any{"path": "final_review.output.deviations", "mode": "equals", "value": []any{}}}}, codexTransitions("publish", "blocked")),
				}),
				codexPhase("publish", "commit", []any{
					codexActionState("commit", "mcp.call", map[string]any{
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
					}, codexTransitions("push", "blocked")),
					codexActionState("push", "mcp.call", map[string]any{
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
					}, codexTransitions("open_pr", "blocked")),
					codexActionState("open_pr", "mcp.call", commandExecuteArgs("{{mcp_endpoint}}", "{{command_server_id}}", "gh_pr_create"), codexTransitions("assert_pr", "blocked")),
					codexActionState("assert_pr", "data.assert", map[string]any{"checks": []any{map[string]any{"path": "open_pr.output.url", "mode": "exists"}}}, codexTransitions("terminal", "blocked")),
				}),
				map[string]any{"id": "blocked"},
				map[string]any{"id": "terminal"},
			},
		},
	}
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

// codexPhase builds one composite process phase.
func codexPhase(id string, initial string, states []any) map[string]any {
	return map[string]any{
		"id":      id,
		"initial": initial,
		"states":  states,
		"transitions": []any{
			map[string]any{"trigger": "failed", "to": "blocked"},
		},
	}
}

// codexActionState builds one process state with a single entry action.
func codexActionState(id string, uses string, with map[string]any, transitions []any) map[string]any {
	return map[string]any{
		"id": id,
		"on_entry": []any{
			map[string]any{"id": id, "uses": uses, "with": with},
		},
		"transitions": transitions,
	}
}

// codexTransitions builds the standard success and failure process exits.
func codexTransitions(successTarget string, failureTarget string) []any {
	return []any{
		map[string]any{"trigger": "succeeded", "to": successTarget},
		map[string]any{"trigger": "failed", "to": failureTarget},
	}
}

// codexPlanChecks returns the coding-standard assertions for the plan gate.
func codexPlanChecks() []any {
	return []any{
		map[string]any{"path": "plan.output.plan.compliant", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.project_conventions", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.solid", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.agents", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.relevant_skills", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.no_unnecessary_backwards_compatibility", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.no_duplicate_implementations", "mode": "equals", "value": true},
		map[string]any{"path": "plan.output.plan.no_hardcoded_values", "mode": "equals", "value": true},
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
