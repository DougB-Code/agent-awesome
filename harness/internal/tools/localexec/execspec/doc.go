// Package execspec defines local process execution request and response data.
//
// Intended use cases:
//   - Pass reviewed command calls between local execution components.
//   - Return process output, exit code, and truncation metadata.
//
// High-level examples:
//   - execspec.ToolCall describes the executable, args, stdin, and working
//     directory for a process.
//   - execspec.Output reports stdout, stderr, and exit status.
//
// This package should remain data-only. Process execution belongs in
// internal/tools/localexec.
package execspec
