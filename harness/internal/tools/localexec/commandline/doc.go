// Package commandline renders command lines for human review.
//
// Intended use cases:
//   - Produce shell-like command strings for confirmation prompts.
//   - Quote executable arguments consistently in local execution UI.
//
// High-level examples:
//   - commandline.ReviewedCommandLine("git", []string{"status", "--short"})
//     returns a display string suitable for review.
//
// This package should not execute commands or parse shell syntax. Execution
// belongs in internal/tools/localexec.
package commandline
