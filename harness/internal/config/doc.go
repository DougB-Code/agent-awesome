// Package config loads Agent Awesome YAML configuration from explicit or
// default paths.
//
// Intended use cases:
//   - Load model, agent, and tool configuration files.
//   - Resolve default config file paths under the user's config directory.
//
// High-level examples:
//   - config.LoadModel(path) parses model provider settings.
//   - config.DefaultAgentPath() returns the default agent YAML path.
//
// This package should focus on file loading and default paths. Schema types and
// validation rules belong in internal/config/schema.
package config
