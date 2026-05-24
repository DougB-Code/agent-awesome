// Package resolution resolves Operation run input from deterministic sources.
//
// Intended use cases:
//   - Preview or start an Operation from UI, Slack, API, schedule, or task context.
//   - Preserve display-safe provenance for every resolved field.
//   - Return structured missing-field metadata instead of opening broad forms.
//
// High-level example:
//   - Build a ResolutionRequest with run request values, Operation defaults,
//     codebase defaults, workflow defaults, generated values, and secret
//     references, then call Resolver.Resolve before starting a workflow run.
package resolution
