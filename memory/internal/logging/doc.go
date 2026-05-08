// Package logging configures process-wide zerolog output for memory services.
//
// Intended use cases:
//   - Initialize structured logging before the memory daemon starts.
//   - Bridge standard-library log output from dependencies into zerolog.
//
// High-level example:
//   - logging.Configure("memory.log") writes JSON logs to a file.
package logging
