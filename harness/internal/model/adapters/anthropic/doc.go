// Package anthropic implements the Anthropic model adapter.
//
// Intended use cases:
//   - Create Anthropic-compatible LLM clients from provider configuration.
//   - Validate Anthropic provider settings.
//   - Translate Agent Awesome messages and tools into Anthropic API requests.
//
// High-level examples:
//   - anthropic.NewFactory(credentials, httpClients) registers an Anthropic
//     provider factory with shared dependencies.
//
// This package should only contain Anthropic-specific adapter behavior. Generic
// adapter contracts belong in internal/model/adapter.
package anthropic
