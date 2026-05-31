// Package main provides the standalone runbook service entrypoint.
//
// Intended use cases:
//   - Run runbook definitions without starting the ADK agent harness.
//   - Expose runbook, launchpad, capability, and runtime-target HTTP APIs.
//   - Serve local runbook runs that may call configured command, MCP, or
//     harness context boundaries when those dependencies are available.
//   - Run one Launchpad queue worker tick from cron through the gateway API.
//
// High-level examples:
//   - go run ./cmd/runbook-service --addr 127.0.0.1:8092 --definitions runbooks --db runbook.db
//   - runbook-service --tool tool.yaml --command-allow-workdir /workspace
//   - runbook-service queue-worker --gateway-base-url https://agent.example.com/api --target-id cloud-overnight
//
// Other packages should not import this package. Reusable runbook runtime
// behavior lives under internal/services/runbook.
package main
