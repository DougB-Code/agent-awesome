# Codex CLI Pilot Phased Implementation Plan

## Summary

Implement AA's Codex CLI pilot without adding Codex-specific workflow support. `workflow` remains orchestration-only, `command` owns CLI execution and CLI output parsing, a new `mcp` component owns local MCP server management, and a new `sourcecontrol` component owns Git safety operations. The pilot workflow composes these generic boundaries to plan, review, implement, test, clean up, commit, push, and open a PR.

## Architecture Decisions From Planning

- Do not add a first-class Codex action. Codex CLI is one configured CLI contract among many.
- Keep daemon and tool names aligned with component ownership. Prefer component-shaped daemons such as `commandd`, `mcpd`, and `sourcecontrold`, with matching MCP tool names such as `command.execute`, `mcp.call`, and `sourcecontrol.prepare_worktree`.
- Do not build a top-level scripting component for v1. Starlark parser support stays in `command` because its only responsibility is converting completed CLI output into structured command output.
- Do not expand existing harness-local `request_command` behavior. Workflow-facing CLI automation belongs in `command`.
- Treat GitHub PR creation as an external CLI concern through `gh`; GitHub is not part of the source-control abstraction.
- Treat Git worktree, branch, commit, push, backup, and restore behavior as product safety concerns owned by `sourcecontrol`.
- Support CLIs that emit JSON, YAML, HUML, plain text, or mixed output. Parse first when needed, then validate the parsed structure when a schema is available.

## Phase 1: CLI Contracts In `command`

- Keep `command` focused on CLI tools only.
- Rename or alias the daemon surface to `commandd` so the process name matches the top-level component.
- Extend command templates with structured CLI contract fields for parameter schema, output contract, parser id, output source, artifact globs, environment policy, working-directory policy, and optional validation schema.
- Add `command.execute` as the workflow-friendly MCP tool that can create, run, poll, and return one structured command result.
- Preserve bounded raw stdout/stderr tails while adding parsed `output`, `diagnostics`, `artifacts`, and `validation` fields to command results.
- Validate JSON output directly when a CLI emits JSON. For text, YAML, HUML, or mixed output, run the configured parser before schema validation.
- Add Codex CLI as ordinary command configuration, not as first-class product logic.

## Phase 2: Command Parser Subsystem

- Add `command/internal/parser` for CLI output parsing only.
- Add a file-based Starlark parser catalog.
- Choose Starlark because parser scripts should be easy for users and AI agents to generate without a complex toolchain.
- Default parser files to the user OS config directory from `os.UserConfigDir()`, under Agent Awesome config, for example `agent-awesome/command/parsers`.
- Allow parser-dir override with `AGENTAWESOME_COMMAND_PARSER_DIR` and `--parser-dir`.
- Require parser files to export `parse(stdout, stderr, exit_code, status)`.
- Use Starlark-Go native function metadata to validate the exported `parse` function before execution: verify it is a `*starlark.Function`, then enforce parameter count and names. Do not write a source-text signature parser when Starlark exposes native metadata.
- Reject parser files that are missing `parse`, export a non-function, use the wrong signature, or return an invalid result shape.
- Keep the parser return shape generic enough for command to expose parsed output, validation diagnostics, and artifact metadata without knowing tool-specific semantics.

## Phase 3: Local MCP Server Component

- Add a new top-level `mcp` component for local MCP server management.
- Provide a component-aligned daemon surface named `mcpd`.
- Own local MCP server configuration, lifecycle, health checks, tool discovery, and tool invocation.
- Do not expand `command` to manage MCP servers.
- Expose MCP tools for server list, tool list, call tool, start, stop, restart, and status, using a consistent `mcp.*` naming style.
- Route workflow-facing local MCP calls through this component instead of embedding local MCP server management in `workflow`.

## Phase 4: Workflow Gates

- Add generic workflow data-gating primitives, not quality-gate product concepts.
- Add `data.assert` as a registered workflow action allowed in task states.
- Support deterministic checks over task input using dotted paths with `equals`, `not_equals`, `exists`, and `schema` modes.
- Use this to gate Codex planning, implementation, review, cleanup, and test progression based on structured command/MCP outputs.
- Keep AGENTS.md/design-goal compliance encoded as workflow states and assertions, not as hard-coded workflow engine behavior.

## Phase 5: Source Control Boundary

- Add a new top-level `sourcecontrol` component.
- Provide a component-aligned daemon surface named `sourcecontrold`.
- Provide MCP tools for prepare worktree, status, commit, push, backup/restore, and cleanup worktree, using a consistent `sourcecontrol.*` naming style.
- Keep Git behavior behind this boundary; use Go code and go-git where practical, with any Git CLI fallback hidden inside the daemon.
- Store safety backups under `build/sourcecontrol`.
- Refuse unsafe operations unless the workflow is operating inside a prepared worktree.

## Phase 6: Full Codex CLI Pilot Workflow

- Prepare an isolated worktree and branch through `sourcecontrol`.
- Invoke Codex CLI through `command.execute` to produce a structured plan.
- Assert the plan complies with AA goals: project conventions, SOLID, AGENTS.md, relevant skills, no unnecessary backwards compatibility, no duplicate implementations, and no hard-coded values.
- Invoke Codex CLI through `command.execute` to implement.
- Run configured tests and linters through `command.execute`.
- Invoke Codex CLI for post-review and cleanup loops when deviations are reported.
- Commit and push through `sourcecontrol`.
- Open the PR through a configured `gh pr create` CLI contract in `command`.

## Test Plan

- Add `command` tests for template parsing, OS config parser defaults, parser-dir override, Starlark signature enforcement, parser failures, JSON and parsed-output validation, artifact discovery, and `command.execute`.
- Add `mcp` tests for server config loading, lifecycle state, tool discovery, tool invocation, and failure reporting.
- Add `workflow` tests proving `data.assert` gates task states on parsed command/MCP output.
- Add `sourcecontrol` tests using temporary Git repositories for worktree prep, dirty-work protection, backup/restore, commit, push-safe paths, and cleanup.
- Add one integration test using fake Codex, fake test, and fake `gh` commands to drive the pilot workflow end to end.

## Assumptions

- `gh` is treated as an installed external CLI for PR creation, even if it is not currently available in this shell.
- Starlark parser support stays inside `command` for CLI output parsing only.
- Workflow-level Starlark execution is deferred until there is a concrete workflow use case.
- Existing harness-local `request_command` code is not expanded for this pilot.
- Existing underscore-style command MCP tools may remain temporarily during migration, but new workflow-facing names should use component-aligned dot names.
