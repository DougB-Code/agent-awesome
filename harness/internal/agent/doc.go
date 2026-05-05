// Package agent defines Agent Awesome's internal agent-domain types and
// validation rules.
//
// Intended use cases:
//   - Represent the normalized identity and instructions of an agent.
//   - Validate agent-domain invariants after configuration has been loaded.
//   - Share agent concepts across app wiring, runtime construction, and tests.
//
// High-level examples:
//   - agent.NewDefinition(name, description, instruction) validates agent
//     fields and returns a normalized definition.
//
// This package should own agent concepts, not infrastructure. Configuration
// loading belongs in internal/config, broad wiring belongs in internal/app, and
// launcher-specific adaptation belongs in internal/runtime.
package agent
