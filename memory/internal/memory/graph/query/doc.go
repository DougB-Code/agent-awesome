// Package query parses and executes context graph queries and mutations.
//
// Use this package when callers need deterministic graph inspection or audited
// edits without natural-language interpretation. The grammar is intentionally low-level:
// FIND statements scan graph node kinds, MATCH statements traverse directed
// graph relationships, WHERE predicates compare typed fields, GROUP BY exposes
// count aggregation, and ORDER BY/LIMIT keep result sets bounded. INSERT, SET,
// and DELETE statements require actor and source metadata and append audit
// events while preserving lifecycle-delete semantics. MATCH results return row
// values plus graph path metadata for callers that need to render or inspect
// the traversed nodes and edges.
package query
