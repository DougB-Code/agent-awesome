// Package persistence saves and restores memory service snapshots.
//
// Intended use cases:
//   - Restore a graph SQLite database and source directory before memoryd
//     starts serving requests.
//   - Save that same state to an external object store during graceful
//     shutdown.
//
// This package should not know about MCP, graph query semantics, or Cloudflare
// bindings directly; callers provide ordinary HTTP snapshot endpoints.
package persistence
