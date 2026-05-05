// Package openai implements OpenAI-compatible chat model adapters.
//
// Intended use cases:
//   - Create OpenAI-compatible LLM clients from provider configuration.
//   - Serialize messages, tools, and tool responses for chat-completion APIs.
//   - Validate OpenAI-compatible provider settings.
//
// High-level examples:
//   - openai.NewFactory(credentials, httpClients) returns a provider factory
//     for OpenAI-compatible models.
//
// This package should only contain OpenAI-compatible adapter behavior. Shared
// model creation and adapter contracts belong in internal/model and
// internal/model/adapter.
package openai
