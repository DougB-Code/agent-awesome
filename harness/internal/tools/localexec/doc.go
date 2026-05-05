// Package localexec implements configured local command execution tools.
//
// Intended use cases:
//   - Build ADK tools from local execution configuration.
//   - Execute allowlisted commands inside approved working directories.
//   - Request user confirmation before risky local command execution.
//
// High-level examples:
//   - localexec.NewTool(cfg) creates a local execution tool.
//   - localexec.NewTools(toolsCfg) creates all local execution tools from tool
//     configuration.
//
// This package should only execute configured local commands. Arbitrary command
// proposal review is handled by the requestcommand subpackage.
package localexec
