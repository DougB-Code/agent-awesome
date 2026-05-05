// Package runtime adapts validated application state to the ADK launcher.
//
// Intended use cases:
//   - Build launcher configuration from an agent definition, LLM, and tools.
//   - Execute the selected runtime mode with delegated ADK launch behavior.
//   - Report delegated command-line syntax for help text.
//
// High-level examples:
//   - runtime.NewConfig(def, llm, tools) prepares launcher configuration.
//   - runtime.Execute(ctx, cfg, args) runs the delegated runtime.
//
// This package should not load YAML files or parse Cobra flags. Application
// coordination belongs in internal/app.
package runtime
