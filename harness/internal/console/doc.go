// Package console implements the interactive console runtime mode.
//
// Intended use cases:
//   - Run a text console loop against a configured ADK runner.
//   - Render model events and request local tool confirmations.
//   - Parse console-specific runtime arguments.
//
// High-level examples:
//   - console.ShouldRun(args) detects whether CLI runtime args select console.
//   - console.Run(ctx, cfg, args) starts the interactive console experience.
//
// This package should not define top-level Cobra commands or model adapters.
// CLI wiring belongs in cmd/agent-awesome/cli, and provider calls belong under
// internal/model.
package console
