// Package policy builds optional operator runtime instructions for agent requests.
//
// Intended use cases:
//   - Keep explicit operator policy separate from HTTP forwarding mechanics.
//   - Inject configured guidance into ADK run request text parts when enabled.
//
// High-level examples:
//   - policy.NewInjector(policy.Config{Text: "Use concise replies."}) creates an enabled injector.
//   - injector.Inject(body) updates ADK run request JSON when configured text is present.
package policy
