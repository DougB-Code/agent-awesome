// Package proxy forwards gateway API requests to the configured agent harness.
//
// Intended use cases:
//   - Preserve Flutter assistant traffic through a stable gateway URL.
//   - Apply caller-provided body transformers before upstream forwarding.
//
// High-level examples:
//   - proxy.New(...) creates a handler mounted at /api/.
//   - proxy.WithBodyTransformer(...) installs a generic request body rewrite hook.
//
// This package should not authenticate callers or start local services.
package proxy
