// Package mcpclient creates MCP client sessions for harness tool consumers.
//
// Intended use cases:
//   - Open configured MCP transports for higher-level harness services.
//   - Keep transport construction out of context API and memory adapters.
//
// High-level examples:
//   - mcpclient.Connect(ctx, server, "agent-awesome-context-api", "v1.0.0")
//     returns a client session for listing or calling tools.
//
// This package should not decide which tools to expose or interpret tool
// responses. That behavior belongs in the caller package.
package mcpclient
