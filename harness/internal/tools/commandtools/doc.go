// Package commandtools adapts the command service boundary into ADK tools.
//
// Use this package when an in-process ADK runtime needs command execution
// capabilities without routing through an MCP loopback listener. External MCP
// hosting remains owned by the command transport packages.
package commandtools
