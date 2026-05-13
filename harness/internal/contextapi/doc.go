// Package contextapi exposes harness-owned context tool operations over HTTP.
//
// Intended use cases:
//   - Let gateways request normalized context data without frontends calling MCP.
//   - Keep MCP invocation inside the harness process and its tool configuration.
//   - Bind directly only to loopback, or require a bearer token for public binds.
//
// High-level examples:
//   - contextapi.StartWithConfig(ctx, cfg, tools) serves /api/context/tools/list
//     and /api/context/tools/call for gateway-owned access.
//   - POST /api/context/tools/call with a domain_id to route memory tools
//     through active-profile read/write grants instead of frontend MCP access.
package contextapi
