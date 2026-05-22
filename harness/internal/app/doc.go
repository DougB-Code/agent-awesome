// Package app provides broad, cross-package wiring for the Agent Awesome CLI.
// It coordinates configuration loading, model creation, tools, and runtime
// launch behavior without owning the narrower implementation details.
//
// Intended use cases:
//   - Run the configured Agent Awesome application from parsed CLI options.
//   - Build a runtime launcher configuration from validated config files.
//
// High-level examples:
//   - app.Run(ctx, opts) executes the application.
//   - app.NewRuntimeConfig(ctx, modelCfg, agentCfg, toolsCfg, opts, commands)
//     prepares a launcher configuration for tests or callers that already loaded
//     config.
//
// This package is the place for application-level orchestration across internal
// packages. It should not own Cobra command definitions, provider protocols,
// tool internals, or reusable low-level validation logic.
package app
