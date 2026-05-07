// Package state persists local provisioning records and generated agent secrets.
//
// Intended use cases:
//   - Keep non-secret per-agent metadata in the user's Agent Awesome config dir.
//   - Store generated internal tokens in the OS keyring, not in build artifacts.
//   - Reuse generated tokens across repeated provisioning applies.
//
// High-level examples:
//   - state.DefaultStore().Save(...) records one provisioned agent.
//   - state.DefaultSecretStore().EnsureGenerated(...) returns a stable token.
//
// This package should not call Cloudflare, render Wrangler configs, or know
// provider-specific deployment details beyond opaque metadata fields.
package state
