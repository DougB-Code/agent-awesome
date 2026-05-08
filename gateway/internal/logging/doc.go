// Package logging configures process-wide zerolog output for the gateway.
//
// Intended use cases:
//   - Initialize structured logging before gateway services start.
//   - Bridge standard-library log output from internal packages into zerolog.
//
// High-level example:
//   - logging.Configure("") writes zerolog records to stderr.
package logging
