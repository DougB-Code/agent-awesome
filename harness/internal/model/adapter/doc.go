// Package adapter defines shared interfaces and helpers for model providers.
//
// Intended use cases:
//   - Implement provider factories for concrete model adapters.
//   - Resolve credentials and HTTP clients through injectable abstractions.
//   - Return sanitized provider errors from adapter implementations.
//
// High-level examples:
//   - adapter.ResolveCredential(resolver, "OPENAI_API_KEY") reads a provider
//     secret through the configured resolver.
//   - adapter.NewProviderErrorWithDetail(provider, model, code, status, detail)
//     formats a safe provider error.
//
// This package should contain provider-agnostic contracts only. Concrete API
// serialization belongs in packages under internal/model/adapters.
package adapter
