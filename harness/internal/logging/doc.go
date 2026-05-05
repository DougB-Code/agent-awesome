// Package logging configures process-wide logging for Agent Awesome.
//
// Intended use cases:
//   - Configure Go log output before runtime execution.
//   - Derive logging settings from environment variables.
//
// High-level examples:
//   - logging.Configure() initializes the default logger for the process.
//
// This package should stay small and process-oriented. Feature-specific logging
// decisions should remain with the packages that emit those logs.
package logging
