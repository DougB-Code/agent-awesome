// Package schema defines and validates Agent Awesome configuration structures.
//
// Intended use cases:
//   - Represent model, agent, MCP, and local execution YAML data.
//   - Validate loaded configuration before runtime construction.
//   - Resolve selected provider and model entries from a model config.
//
// High-level examples:
//   - cfg.Validate() checks model provider configuration.
//   - schema.ValidateAgent(agentCfg) rejects incomplete agent settings.
//
// This package should not read files or start runtimes. File loading belongs in
// internal/config, and execution behavior belongs in internal/runtime.
package schema
