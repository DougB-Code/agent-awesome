// Package embedded exposes runbook runtime wiring for in-process hosts.
//
// Intended use cases:
//   - Start the runbook HTTP/MCP surface from the harness process.
//   - Share the same runtime, store, action registry, and transport
//     implementation from harness-owned listeners.
//
// High-level examples:
//   - embedded.Start(ctx, cfg) starts runbook routes on a host-owned listener.
//   - server.Close(ctx) gracefully shuts down the listener and runbook store.
//
// This package is the process-boundary adapter for hosts outside the runbook
// runtime packages. Runbook business rules belong in the runtime package.
package embedded
