// Package google implements the Google Generative AI model adapter.
//
// Intended use cases:
//   - Create Google-backed LLM clients from provider configuration.
//   - Resolve Google API credentials through the shared adapter interface.
//   - Validate Google provider settings.
//
// High-level examples:
//   - google.NewFactory(credentials) returns a provider factory for Google
//     models.
//
// This package should only contain Google-specific adapter behavior. Generic
// model factory registration belongs in internal/model.
package google
