// Package resolution resolves Launch run input from deterministic sources.
//
// Intended use cases:
//   - Preview or start an Launch from UI, Slack, API, schedule, or task context.
//   - Preserve display-safe provenance for every resolved field.
//   - Return structured missing-field metadata instead of opening broad forms.
//
// High-level example:
//   - Build a ResolutionRequest with run request values, Launch defaults,
//     codebase defaults, runbook defaults, generated values, and secret
//     references, then call Resolver.Resolve before starting a runbook run.
package resolution
