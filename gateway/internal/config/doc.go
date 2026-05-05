// Package config loads the personal agent gateway runtime settings.
//
// Intended use cases:
//   - Build gateway configuration from flags and environment variables.
//   - Keep local binary launch settings separate from HTTP gateway behavior.
//
// High-level examples:
//   - config.FromFlags(os.Args[1:]) prepares settings for cmd/agent-gateway.
//   - cfg.HarnessBaseURL identifies the upstream ADK-compatible harness API.
//
// This package should not start processes or serve HTTP requests.
package config
