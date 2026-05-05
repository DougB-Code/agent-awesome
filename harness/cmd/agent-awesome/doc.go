// Package main provides the agent-awesome executable entrypoint.
//
// Intended use cases:
//   - Build or run the installed agent-awesome binary.
//   - Start the Cobra command tree from process startup.
//
// High-level examples:
//   - go run ./cmd/agent-awesome run -- console
//   - agent-awesome credentials set OPENAI_API_KEY
//
// Other packages should not import this package. Reusable command wiring lives
// in cmd/agent-awesome/cli, and runtime behavior lives under internal.
package main
