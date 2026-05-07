// Package cloudflare builds Cloudflare deployment artifacts for provisioned agents.
//
// Intended use cases:
//   - Render a per-agent Wrangler configuration with an isolated R2 bucket.
//   - Derive stable, Cloudflare-compatible resource names from one agent id.
//   - Produce operator commands that can later be replaced by direct API calls.
//
// High-level examples:
//   - cloudflare.NewDeployment(...) creates a validated desired deployment.
//   - cloudflare.WriteBundle(...) writes the generated files under build/.
//
// This package should not prompt users, persist operator state, or store secret
// values.
package cloudflare
