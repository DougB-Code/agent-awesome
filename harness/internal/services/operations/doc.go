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
//   - A client calls operation_start with a saved Operation id and run input.
//     Operations resolves configured defaults, records provenance, and starts
//     the bound workflow through the workflow runtime.
package operations
