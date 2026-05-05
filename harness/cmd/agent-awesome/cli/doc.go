// Package cli defines the Cobra command tree for the agent-awesome executable.
//
// Intended use cases:
//   - Execute the production CLI from cmd/agent-awesome.
//   - Build the root command in tests or integration harnesses.
//   - Translate command-line flags and arguments into calls to internal
//     implementation packages.
//
// High-level examples:
//   - cli.Execute(context.Background()) starts the full CLI.
//   - cli.NewRootCommand(ctx) builds the command tree for tests.
//
// This package should contain Cobra command definitions only. Command behavior
// belongs under internal packages such as internal/app and internal/secrets.
package cli
