// Package launchpad owns reusable runbook setup, input resolution, and run links.
//
// Intended use cases:
//   - Save an Launch that binds a runbook to defaults, codebases, targets,
//     policy, schedules, and secret references.
//   - Preview an Launch run to see resolved input and missing setup.
//   - Start a runbook through the Launchpad boundary instead of runbook run
//     setup forms.
//
// High-level example:
//   - A client calls launchpad_start with a saved Launch id and run input.
//     Launchpad resolves configured defaults, records provenance, and starts
//     the bound runbook through the runbook runtime.
package launchpad
