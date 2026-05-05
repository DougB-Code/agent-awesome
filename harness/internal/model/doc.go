// Package model builds provider-backed language model clients.
//
// Intended use cases:
//   - Register supported model provider adapters.
//   - Create LLM clients from validated provider selections.
//   - Validate requested model capabilities against model config.
//
// High-level examples:
//   - model.NewFactory().New(ctx, selection) creates a provider client.
//   - model.ValidateRequestedCapabilities(requested, selection) checks feature
//     support before launch.
//
// This package should coordinate model creation, not implement provider HTTP
// protocols directly. Provider-specific behavior belongs in model/adapters.
package model
