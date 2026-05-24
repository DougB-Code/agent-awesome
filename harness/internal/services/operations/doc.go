// Package operations owns reusable workflow setup, input resolution, and run links.
//
// Intended use cases:
//   - Save an Operation that binds a workflow to defaults, codebases, targets,
//     policy, schedules, and secret references.
//   - Preview an Operation run to see resolved input and missing setup.
//   - Start a workflow through the Operations boundary instead of workflow run
//     setup forms.
//
// High-level example:
//   - A Slack request calls coding_change_start with a change request and
//     codebase name. Operations resolves the codebase, builds complete workflow
//     input, records provenance, and starts the configured coding workflow.
package operations
