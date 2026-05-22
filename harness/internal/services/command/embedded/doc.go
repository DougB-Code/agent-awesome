// Package embedded runs the command MCP service inside another AA process.
//
// Use this package when a host must expose command execution to external MCP
// clients without starting a separate command process. In-process ADK runtimes
// should prefer direct command tools.
package embedded
