// Package main provides the standalone workflow service entrypoint.
//
// Intended use cases:
//   - Run workflow definitions without starting the ADK agent harness.
//   - Expose workflow, operation, capability, and runtime-target HTTP APIs.
//   - Serve local workflow runs that may call configured command, MCP, or
//     harness context boundaries when those dependencies are available.
//
// High-level examples:
//   - go run ./cmd/workflow-service --addr 127.0.0.1:8092 --definitions workflows --db workflow.db
//   - workflow-service --tool tool.yaml --command-allow-workdir /workspace
//
// Other packages should not import this package. Reusable workflow runtime
// behavior lives under internal/services/workflow.
package main
