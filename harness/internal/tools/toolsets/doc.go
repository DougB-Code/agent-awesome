// Package toolsets builds runtime tool and toolset bundles from configuration.
//
// Intended use cases:
//   - Combine configured MCP toolsets for the ADK runtime.
//   - Build MCP transports from validated tool configuration.
//   - Provide confirmation routing for tool names that need review.
//
// High-level examples:
//   - toolsets.Build(cfg) returns runtime tool configuration for the launcher.
//
// This package wires tool providers together. Individual tool implementation
// details belong in their narrower packages.
package toolsets
