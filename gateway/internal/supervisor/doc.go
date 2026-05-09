// Package supervisor manages optional local service processes for the gateway.
//
// Intended use cases:
//   - Track harness and memory readiness while the gateway is serving.
//   - Start configured sibling binaries for local personal deployments.
//
// High-level examples:
//   - supervisor.Manager.Expect(...) records dependencies expected at startup.
//   - supervisor.New(...).Ensure(ctx, service) verifies or starts a dependency.
//   - supervisor.Manager.Close(...) stops only processes it started.
//
// This package should not proxy HTTP traffic or parse command-line flags.
package supervisor
