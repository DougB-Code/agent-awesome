// Package appplugins renders manifest data for app plugin packages.
//
// Intended use cases:
//   - Execute package-local Starlark entrypoints that produce app panel
//     manifests.
//   - Validate that rendered plugin data is JSON/YAML compatible before the UI
//     loads it.
//   - Keep super-app extension contracts outside first-class product routes.
//
// High-level example:
//   - appplugins.RenderPackage(ctx, "plugins/workflow-board", "app.star")
//     executes render() and returns a manifest map suitable for app.yaml.
package appplugins
