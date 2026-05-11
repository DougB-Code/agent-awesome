// Package workersecrets assembles Worker secret values for provisioned agents.
//
// Intended use cases:
//   - Combine generated per-agent tokens with operator-provided credentials.
//   - Validate that all Cloudflare Worker secrets required by a deployment are present.
//
// High-level examples:
//   - workersecrets.BuildWithTokens(...) returns cloudflare.SecretValues for cloudflare.Apply.
//
// This package should not reconcile Cloudflare resources or persist deployment records.
package workersecrets
