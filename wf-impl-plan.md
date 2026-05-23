# Professional Coding Workflow Pilot Implementation

Status: implemented as a first deployable pilot.

## Implemented

- Workflow definitions accept `kind: state_machine` with hierarchical states, `initial`, `on_entry`, and trigger transitions.
- Workflow runtime executes nested state-machine entry actions through the generic action registry and preserves waiting/resume behavior.
- Source-control worktree preparation can generate safe `aa-*` branches from `branch_prefix` and `branch_summary`.
- Runtime profiles support generic managed `mcp_servers`; bundled profiles register the source-control MCP service.
- Tool config supports node preset and scenario metadata while keeping presets compiled to generic `command.execute` or `mcp.call` actions.
- Added deployable Go command package `harness/tool.go.yaml` with `go_build_all`, `go_test_all`, binary build, and binary invocation presets.
- Added aggregate pilot package `harness/tool.professional-coding.yaml` with generic Codex CLI command data, Go verification, binary invocation, and source-control boundary presets.
- Added `harness/workflows/professional_coding_change.yaml` for worktree-first coding changes.
- Tools and MCP settings panels expose preset and scenario modes outside the workflow designer.
- Added generic `data.defaults` and MCP `server_id` action inputs so workflow defaults and MCP routing stay declarative.
- Tool configuration supports environment-variable expansion so deployable MCP endpoints are not hard-coded in Go or workflow runtime logic.
- Source-control commit excludes AA prepared-worktree metadata so generated control files and workflow build artifacts under `.agent-awesome/` do not enter review branches.
- Live pilot completed through the built AA binary: Codex fixed a real divide bug in a clean Git worktree, Go build/test passed, the workflow built and invoked the binary, sourcecontrol committed, and the branch was pushed.

## Notes

- Codex remains ordinary command template data. Production Go code has no Codex-specific runtime path.
- Source-control calls require explicit `base_ref` and `remote` inputs; the professional workflow supplies `HEAD` and `origin` as declarative defaults.
- Runtime profile and node metadata parsing is schema-explicit. No compatibility shim fills missing workflow runtime sections or alternate node metadata key spellings.
- Publishing currently pushes the prepared branch and returns branch metadata through workflow run output. Pull-request creation remains a future source-control tool.
- The node workbench scenario runner and workflow-palette preset insertion are represented by typed metadata and UI modes; live execution and drag-in insertion remain follow-up slices.
- Deployed command runtimes must allowlist any configured template environment variables, such as `CODEX_HOME`, because template env values pass through the generic command security policy.
