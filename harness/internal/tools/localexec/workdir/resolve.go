// This file resolves and validates command working directories.
package workdir

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ResolveCWD converts a requested working directory into a canonical absolute
// path and ensures it stays under one of the allowed roots.
func ResolveCWD(base, requested string, roots []string) (string, error) {
	cwd := strings.TrimSpace(requested)
	if cwd == "" {
		cwd = base
	} else if filepath.IsAbs(cwd) {
		cwd = filepath.Clean(cwd)
	} else {
		cwd = filepath.Join(base, cwd)
	}
	abs, err := filepath.Abs(cwd)
	if err != nil {
		return "", fmt.Errorf("resolve cwd: %w", err)
	}
	abs, err = CanonicalPath(abs)
	if err != nil {
		return "", fmt.Errorf("resolve cwd %q: %w", requested, err)
	}
	allowed, err := allowedRoots(base, roots)
	if err != nil {
		return "", err
	}
	for _, allowed := range allowed {
		if PathWithin(abs, allowed) {
			return abs, nil
		}
	}
	return "", fmt.Errorf("cwd %q is outside allowed workdirs", requested)
}

// allowedRoots resolves and canonicalizes configured local-exec roots.
func allowedRoots(base string, roots []string) ([]string, error) {
	if len(roots) == 0 {
		roots = []string{base}
	}
	allowed := make([]string, 0, len(roots))
	for _, root := range roots {
		resolved := strings.TrimSpace(root)
		if resolved == "" {
			return nil, fmt.Errorf("local-exec allowed workdir must not be empty")
		}
		if !filepath.IsAbs(resolved) {
			resolved = filepath.Join(base, resolved)
		}
		abs, err := filepath.Abs(resolved)
		if err != nil {
			return nil, fmt.Errorf("resolve local-exec allowed workdir %q: %w", root, err)
		}
		canonical, err := CanonicalPath(abs)
		if err != nil {
			return nil, fmt.Errorf("resolve local-exec allowed workdir %q: %w", root, err)
		}
		allowed = append(allowed, canonical)
	}
	return allowed, nil
}

// CanonicalPath resolves symlinks and returns a clean absolute path.
func CanonicalPath(path string) (string, error) {
	resolved, err := filepath.EvalSymlinks(filepath.Clean(path))
	if err != nil {
		return "", err
	}
	abs, err := filepath.Abs(resolved)
	if err != nil {
		return "", err
	}
	return filepath.Clean(abs), nil
}

// ExecutionBase returns the workspace base directory for local command
// execution.
func ExecutionBase() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("resolve execution cwd: %w", err)
	}
	return filepath.Clean(cwd), nil
}

// PathWithin reports whether path is equal to or inside root.
func PathWithin(path, root string) bool {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}
	return rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)))
}
