// Package model builds provider-backed language model clients.
//
// Intended use cases:
//   - Register supported model provider adapters.
//   - Create LLM clients from validated provider selections.
//
// High-level examples:
//   - model.NewFactory().New(ctx, selection) creates a provider client.
//
// This package should coordinate model creation, not implement provider HTTP
// protocols directly. Provider-specific behavior belongs in model/adapters.
package model
