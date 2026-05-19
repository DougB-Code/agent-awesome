// This file tests sourcecontrold configuration parsing.
package main

import "testing"

// TestParseConfigReadsBuildDir verifies build state path configuration.
func TestParseConfigReadsBuildDir(t *testing.T) {
	dir := t.TempDir()
	cfg, err := parseConfig([]string{"-build-dir", dir})
	if err != nil {
		t.Fatalf("parseConfig() error = %v", err)
	}

	if cfg.SourceControl.BuildDir != dir {
		t.Fatalf("BuildDir = %q, want %q", cfg.SourceControl.BuildDir, dir)
	}
}
