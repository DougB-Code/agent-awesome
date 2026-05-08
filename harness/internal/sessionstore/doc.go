// Package sessionstore creates memory-backed ADK session services for harness runs.
//
// Use this package when a runtime needs exact ADK chat history to survive
// process restarts while sharing the same SQLite database as long-term memory.
// The package intentionally returns ADK's session.Service so callers can keep
// session lifecycle, event storage, and history loading inside the Google Agent
// Development Kit.
package sessionstore
