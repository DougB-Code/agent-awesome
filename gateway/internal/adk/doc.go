// Package adk builds ADK REST API URLs and request payloads.
//
// Intended use cases:
//   - Keep ADK path construction consistent across gateway packages.
//   - Build small REST request bodies for agent run calls.
//
// High-level examples:
//   - adk.SessionsURL(...) returns the readiness collection URL.
//   - adk.SessionURL(...) returns one session resource URL.
//   - adk.RunRequestBody(...) builds the JSON body sent to /run_sse.
//
// This package should not send HTTP requests or parse gateway configuration.
package adk
