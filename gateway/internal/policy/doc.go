// Package policy builds gateway-owned runtime instructions for agent requests.
//
// Intended use cases:
//   - Keep agent operating policy separate from HTTP forwarding mechanics.
//   - Inject configurable runtime guidance into ADK run request text parts.
//
// High-level examples:
//   - policy.NewInjector(policy.Config{Text: policy.DefaultRuntimePolicyText}) creates the default injector.
//   - injector.Inject(body) updates ADK run request JSON when text user parts are present.
package policy
