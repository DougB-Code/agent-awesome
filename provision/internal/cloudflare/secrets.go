// This file defines the in-memory Worker secret carrier used during apply.
package cloudflare

// SecretValues stores secret material only in memory during provisioning.
type SecretValues map[string]string
