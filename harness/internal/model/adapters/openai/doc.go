// Package openai adapts runtime chat requests through the official OpenAI Go
// SDK.
//
// Intended use cases:
//   - Create SDK-backed LLM clients from provider configuration.
//   - Translate runtime messages, tools, and tool responses for chat completions.
//   - Validate OpenAI-compatible provider settings.
//
// High-level examples:
//   - openai.NewFactory(credentials, httpClients) returns a provider factory
//     for OpenAI and OpenAI-compatible models.
//
// This package should only contain OpenAI-compatible adapter behavior. Shared
// model creation and adapter contracts belong in internal/model and
// internal/model/adapter.
package openai
