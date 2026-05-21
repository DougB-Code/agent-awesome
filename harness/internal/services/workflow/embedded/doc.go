// Package embedded exposes workflow runtime wiring for in-process hosts.
//
// Intended use cases:
//   - Start the workflow HTTP/MCP surface from the harness process.
//   - Share the same runtime, store, action registry, and transport
//     implementation from harness-owned listeners.
//
// High-level examples:
//   - embedded.Start(ctx, cfg) starts workflow routes on a host-owned listener.
//   - server.Close(ctx) gracefully shuts down the listener and workflow store.
//
// This package is the process-boundary adapter for hosts outside the workflow
// runtime packages. Workflow business rules belong in the runtime package.
package embedded
