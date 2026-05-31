// This file tests source-control package installation.
package sourcecontrol

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

// TestInstallCopiesLocalToolPackage verifies local package installation.
func TestInstallCopiesLocalToolPackage(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source", "curl")
	if err := os.MkdirAll(filepath.Join(source, "bin"), 0o700); err != nil {
		t.Fatalf("MkdirAll(source) error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(source, "tool.yaml"), []byte("name: Curl\n"), 0o600); err != nil {
		t.Fatalf("WriteFile(tool) error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(source, "bin", "helper.sh"), []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatalf("WriteFile(helper) error = %v", err)
	}

	result, err := Install(context.Background(), Options{
		Source:   source,
		ToolRoot: filepath.Join(root, "tools"),
		MCPRoot:  filepath.Join(root, "mcp"),
	})
	if err != nil {
		t.Fatalf("Install() error = %v", err)
	}

	if result.Kind != "tool" || result.PackageID != "curl" {
		t.Fatalf("result = %#v, want curl tool package", result)
	}
	if got, err := os.ReadFile(filepath.Join(root, "tools", "curl", "tool.yaml")); err != nil || string(got) != "name: Curl\n" {
		t.Fatalf("installed tool = %q, %v", got, err)
	}
	if _, err := os.Stat(filepath.Join(root, "tools", "curl", "bin", "helper.sh")); err != nil {
		t.Fatalf("installed helper stat error = %v", err)
	}
}

// TestInstallCopiesLocalAppPluginPackage verifies app plugin installation.
func TestInstallCopiesLocalAppPluginPackage(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source", "calendar")
	if err := os.MkdirAll(source, 0o700); err != nil {
		t.Fatalf("MkdirAll(source) error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(source, "app.yaml"), []byte("name: Calendar\n"), 0o600); err != nil {
		t.Fatalf("WriteFile(app) error = %v", err)
	}

	result, err := Install(context.Background(), Options{
		Source:   source,
		ToolRoot: filepath.Join(root, "tools"),
		MCPRoot:  filepath.Join(root, "mcp"),
		AppRoot:  filepath.Join(root, "app-plugins"),
	})
	if err != nil {
		t.Fatalf("Install() error = %v", err)
	}

	if result.Kind != "app" || result.PackageID != "calendar" {
		t.Fatalf("result = %#v, want calendar app package", result)
	}
	if got, err := os.ReadFile(filepath.Join(root, "app-plugins", "calendar", "app.yaml")); err != nil || string(got) != "name: Calendar\n" {
		t.Fatalf("installed app = %q, %v", got, err)
	}
}

// TestParseGitHubSourceBuildsArchiveURL verifies go-get-style GitHub parsing.
func TestParseGitHubSourceBuildsArchiveURL(t *testing.T) {
	source, err := parseSource("github.com/example/tools/packages/curl@release")
	if err != nil {
		t.Fatalf("parseSource() error = %v", err)
	}
	if source.Subdir != "packages/curl" {
		t.Fatalf("Subdir = %q, want packages/curl", source.Subdir)
	}
	if source.PackageHint != "tools" {
		t.Fatalf("PackageHint = %q, want tools", source.PackageHint)
	}
	if source.ArchiveURL == "" {
		t.Fatalf("ArchiveURL is empty")
	}
}
