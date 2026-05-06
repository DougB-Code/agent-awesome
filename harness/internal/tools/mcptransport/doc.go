// Package mcptransport builds MCP client transports from Agent Awesome tool
// configuration.
//
// Intended use cases:
//   - Share MCP transport construction between the ADK toolset adapter and
//     harness-owned context APIs.
//   - Apply configured process environments and HTTP headers consistently.
//
// High-level examples:
//   - mcptransport.New(server) returns a transport for one configured MCP
//     server.
package mcptransport
