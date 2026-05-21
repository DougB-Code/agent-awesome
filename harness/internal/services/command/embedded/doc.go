// Package embedded runs the command MCP service inside another AA process.
//
// Use this package when harness should own command execution without starting a
// separate command process. Embedded hosts share the same command service,
// policy validation, parser catalog, and MCP transport.
package embedded
