// Package sourcecontrol installs portable AA packages from source-control
// locations without exposing ad hoc Git shell commands to product workflows.
//
// Intended use cases:
//   - Resolve GitHub or GitLab repository archive URLs from go-get-style
//     source strings.
//   - Copy a package directory containing tool.yaml or mcp.yaml into the local
//     AA package roots.
//
// High-level examples:
//   - Install(ctx, Options{Source: "github.com/org/repo/tools/curl@v1.0.0"})
//     downloads the archive, selects the package subdirectory, and writes it
//     below the configured tools or mcp package root.
package sourcecontrol
