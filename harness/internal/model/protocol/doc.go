// Package protocol converts between Agent Awesome model data and provider SDK
// protocol types.
//
// Intended use cases:
//   - Convert content roles and parts into provider-specific representations.
//   - Build tool declaration payloads for supported model SDKs.
//
// High-level examples:
//   - protocol.ContentText(content) extracts text from a provider content
//     value.
//   - protocol.FunctionDeclarations(req) builds Gemini tool declarations.
//
// This package should hold protocol conversion helpers only. Provider HTTP
// clients and runtime orchestration belong elsewhere.
package protocol
