// Package workdir resolves and validates local execution working directories.
//
// Intended use cases:
//   - Resolve requested command directories against an execution base.
//   - Canonicalize paths before security checks.
//   - Verify paths remain inside configured roots.
//
// High-level examples:
//   - workdir.ResolveCWD(base, requested, roots) returns a safe working
//     directory for command execution.
//   - workdir.PathWithin(path, root) checks containment after canonicalization.
//
// This package should not run commands. It only decides whether a working
// directory is safe to use.
package workdir
