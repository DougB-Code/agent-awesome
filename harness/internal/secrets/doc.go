// Package secrets centralizes provider credential lookup, storage, removal, and
// interactive input.
//
// Intended use cases:
//   - Resolve provider credentials from the OS keyring or environment.
//   - Store and remove provider credentials in the OS keyring.
//   - Read credential values from terminal or piped input for CLI commands.
//
// High-level examples:
//   - secrets.Lookup("OPENAI_API_KEY") resolves a configured credential.
//   - secrets.SetFromInput(stdin, stdout, "OPENAI_API_KEY", value) stores a
//     credential provided by a CLI command.
//
// This package should only handle secret material and credential storage. CLI
// command definitions belong under cmd/agent-awesome/cli.
package secrets
