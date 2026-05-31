// Package capabilities normalizes configured commands, MCP tools, agents, and
// runbook authoring metadata into one registry for Capability Lab checks.
//
// Intended use:
//   - Build a Registry from harness tool and agent config at startup.
//   - List capabilities for UI lab screens and availability badges.
//   - Validate runbook definitions before publish so unavailable capabilities
//     cannot enter executable runbooks.
package capabilities
