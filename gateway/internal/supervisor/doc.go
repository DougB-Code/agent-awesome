// Package supervisor manages optional local service processes for the gateway.
//
// Intended use cases:
//   - Check harness and memory readiness before the gateway begins serving.
//   - Start configured sibling binaries for local personal deployments.
//
// High-level examples:
//   - supervisor.New(...).Ensure(ctx, service) verifies or starts a dependency.
//   - supervisor.Manager.Close(...) stops only processes it started.
//
// This package should not proxy HTTP traffic or parse command-line flags.
package supervisor
