// Package callbacks contains ADK runtime callbacks that enforce local tool-call
// invariants before tools cross into external MCP services.
//
// Intended use cases:
//   - Keep task idempotency and argument normalization out of model prompts.
//   - Apply deterministic guardrails to ADK tool calls before MCP execution.
//
// High-level examples:
//   - callbacks.TaskInvariantCallbacks() installs task-management callbacks on
//     an llmagent.Config.
package callbacks
