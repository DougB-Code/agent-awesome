// Package platform stores operator-level defaults for managed cloud provisioning.
//
// Intended use cases:
//   - Remember the Cloudflare zone used for provisioned agents.
//   - Remember the hostname suffix used to derive per-agent hostnames.
//   - Remember where the Worker/Container source lives on the operator machine.
//
// High-level examples:
//   - platform.DefaultStore().Save(...) writes the local platform config.
//   - platform.DefaultStore().Load() gives cloudflare apply its default flags.
//
// This package should not provision Cloudflare resources, store secret values,
// or own per-user agent records.
package platform
