// Package sessionstore creates memory-backed runtime session services for harness runs.
//
// Use this package when a runtime needs exact chat history to survive
// process restarts while sharing the same SQLite database as long-term memory.
// The package intentionally returns the runtime session service so callers can
// keep session lifecycle, event storage, and history loading in one boundary.
package sessionstore
