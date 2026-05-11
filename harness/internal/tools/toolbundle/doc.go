// Package toolbundle defines the runtime-neutral bundle of ADK tools.
//
// Intended use cases:
//   - Pass assembled tools and toolsets between tool wiring and runtime wiring.
//   - Keep lower-level tool packages independent from the application runtime.
//
// High-level examples:
//   - toolbundle.Bundle{Tools: tools, Toolsets: toolsets} carries callable tools.
package toolbundle
