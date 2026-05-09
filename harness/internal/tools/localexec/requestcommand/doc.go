// Package requestcommand implements reviewed arbitrary command proposals.
//
// Intended use cases:
//   - Expose a tool that lets models propose local commands for user review.
//   - Persist user approval policies only when local-exec opts in explicitly.
//   - Execute approved proposals through the local execution backend.
//
// High-level examples:
//   - requestcommand.NewTool(cfg, executor) creates the request_command tool.
//   - RequestCommandInput describes the command proposal submitted by a model.
//
// This package should not define static allowlisted local exec commands. That
// behavior belongs in internal/tools/localexec.
package requestcommand
