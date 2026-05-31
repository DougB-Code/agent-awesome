// Package targets owns Computer or Server runtime target inventory.
//
// Intended use cases:
//   - Register "This computer" automatically from the running harness process.
//   - Store target health, capability inventory, codebase grants, and logs.
//   - Serve the UI and Launchpad service with target records without coupling
//     runbook orchestration to one machine or deployment shape.
//
// High-level example:
//   - The embedded harness starts, records the local target with its capability
//     ids, and the UI lists that target as the default place Launchpad can run.
package targets
