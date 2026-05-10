// Package projection builds source-backed read models from memory graph facts.
//
// Use this package for deterministic CQRS projections such as the Today
// executive summary. It should depend on domain DTOs, not transports,
// repositories, or agent-runtime prompts.
package projection
