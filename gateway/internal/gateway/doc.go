// Package gateway composes the personal agent gateway HTTP surface.
//
// Intended use cases:
//   - Serve health, status, and ADK-compatible proxy endpoints.
//   - Keep channel adapters behind one local or cloud deployable binary.
//
// High-level examples:
//   - gateway.NewServer(...) returns the HTTP handler used by cmd/agent-gateway.
//   - Server exposes /api/gateway/status and proxies /api/* to the harness.
//
// This package should not parse flags or start subprocesses directly.
package gateway
