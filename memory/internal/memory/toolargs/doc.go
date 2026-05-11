// Package toolargs converts model tool arguments into memory service requests.
//
// Use this package from transports after they have identified a tool call and
// need to normalize loose model arguments. It does not own MCP schemas,
// JSON-RPC routing, HTTP behavior, or service execution.
package toolargs
