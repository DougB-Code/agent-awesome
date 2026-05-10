// Package review defines shared payload primitives for local command review.
//
// Intended use cases:
//   - Describe selectable approval actions for local command confirmation UIs.
//   - Render bounded stdin previews for human-readable review prompts.
//   - Reuse review data shapes across configured and arbitrary command tools.
//
// High-level examples:
//   - review.Option describes one confirmation action such as deny or approve.
//   - review.NewStdinPreview(stdin) creates a bounded stdin payload for JSON UI.
//   - review.AppendStdinPromptSection(builder, stdin) appends prompt text.
//
// This package should not decide whether commands are allowed or execute them.
// Policy checks belong to the calling command package.
package review
