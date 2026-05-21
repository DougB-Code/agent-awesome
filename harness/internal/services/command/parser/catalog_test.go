// This file tests the Starlark parser catalog contract.
package parser

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestParseRunsValidStarlarkParser verifies the parser ABI and result mapping.
func TestParseRunsValidStarlarkParser(t *testing.T) {
	dir := t.TempDir()
	writeParser(t, dir, "jsonish", `
def parse(stdout, stderr, exit_code, status):
    return {
        "output": {"stdout": stdout, "exit_code": exit_code, "status": status},
        "diagnostics": [{"severity": "info", "message": stderr}],
    }
`)
	catalog, err := NewCatalog(dir)
	if err != nil {
		t.Fatalf("NewCatalog() error = %v", err)
	}

	result, err := catalog.Parse(context.Background(), "jsonish", Input{
		Stdout:   "body",
		Stderr:   "note",
		ExitCode: 7,
		Status:   "failed",
	})
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	output, _ := result["output"].(map[string]any)
	if output["stdout"] != "body" || output["status"] != "failed" {
		t.Fatalf("output = %#v, want parser result", output)
	}
}

// TestParseRejectsWrongSignature verifies native Starlark function metadata is enforced.
func TestParseRejectsWrongSignature(t *testing.T) {
	dir := t.TempDir()
	writeParser(t, dir, "bad", `
def parse(stdout):
    return {}
`)
	catalog, err := NewCatalog(dir)
	if err != nil {
		t.Fatalf("NewCatalog() error = %v", err)
	}

	_, err = catalog.Parse(context.Background(), "bad", Input{})
	if err == nil || !strings.Contains(err.Error(), "must accept stdout") {
		t.Fatalf("Parse() error = %v, want signature rejection", err)
	}
}

// TestParseRejectsMissingExport verifies parser files must export parse().
func TestParseRejectsMissingExport(t *testing.T) {
	dir := t.TempDir()
	writeParser(t, dir, "missing", `
def convert(stdout, stderr, exit_code, status):
    return {}
`)
	catalog, err := NewCatalog(dir)
	if err != nil {
		t.Fatalf("NewCatalog() error = %v", err)
	}

	_, err = catalog.Parse(context.Background(), "missing", Input{})
	if err == nil || !strings.Contains(err.Error(), "must export parse") {
		t.Fatalf("Parse() error = %v, want missing parse rejection", err)
	}
}

// TestParseRejectsNonFunctionExport verifies parse must be callable Starlark code.
func TestParseRejectsNonFunctionExport(t *testing.T) {
	dir := t.TempDir()
	writeParser(t, dir, "constant", `
parse = {"output": "nope"}
`)
	catalog, err := NewCatalog(dir)
	if err != nil {
		t.Fatalf("NewCatalog() error = %v", err)
	}

	_, err = catalog.Parse(context.Background(), "constant", Input{})
	if err == nil || !strings.Contains(err.Error(), "parse export must be a function") {
		t.Fatalf("Parse() error = %v, want non-function parse rejection", err)
	}
}

// TestParseRejectsInvalidResultShape verifies parsers return dictionaries only.
func TestParseRejectsInvalidResultShape(t *testing.T) {
	dir := t.TempDir()
	writeParser(t, dir, "list", `
def parse(stdout, stderr, exit_code, status):
    return [stdout]
`)
	catalog, err := NewCatalog(dir)
	if err != nil {
		t.Fatalf("NewCatalog() error = %v", err)
	}

	_, err = catalog.Parse(context.Background(), "list", Input{})
	if err == nil || !strings.Contains(err.Error(), "must be a dictionary") {
		t.Fatalf("Parse() error = %v, want shape rejection", err)
	}
}

// writeParser writes one parser catalog file for tests.
func writeParser(t *testing.T, dir string, id string, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, id+".star"), []byte(body), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
}
