// Package contextapi exposes harness-owned context tool operations over HTTP.
//
// Intended use cases:
//   - Let gateways request normalized context data without frontends calling MCP.
//   - Keep MCP invocation inside the harness process and its tool configuration.
//
// High-level examples:
//   - contextapi.Start(ctx, addr, tools) serves /api/context/tools/list and
//     /api/context/tools/call for gateway-only use.
package contextapi
