// Package proxy forwards gateway API requests to the configured agent harness.
//
// Intended use cases:
//   - Preserve ADK-compatible Flutter traffic through a stable gateway URL.
//   - Inject server-owned runtime policy before agent runs reach the harness.
//
// High-level examples:
//   - proxy.New(...) creates a handler mounted at /api/.
//   - proxy.InjectRuntimePolicy(...) updates run_sse request bodies.
//
// This package should not authenticate callers or start local services.
package proxy
