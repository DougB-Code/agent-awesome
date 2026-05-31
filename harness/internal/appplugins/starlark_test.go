// This file tests Starlark app plugin rendering.
package appplugins

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

// TestRenderPackageRunsStarlarkManifest verifies the render ABI and result
// conversion for a board-capable app plugin.
func TestRenderPackageRunsStarlarkManifest(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "app.star"), []byte(`
def render():
    return {
        "id": "workflow-board",
        "name": "Workflow Board",
        "entrypoint": {"starlark": "app.star"},
        "panels": [
            {
                "id": "board",
                "title": "Board",
                "kind": "board",
                "actions": [
                    {"id": "create-card", "title": "Create card", "kind": "workflow"},
                ],
            },
        ],
    }
`), 0o600); err != nil {
		t.Fatalf("WriteFile(app.star) error = %v", err)
	}

	manifest, err := RenderPackage(context.Background(), dir, "app.star")
	if err != nil {
		t.Fatalf("RenderPackage() error = %v", err)
	}
	if got, want := manifest["id"], "workflow-board"; got != want {
		t.Fatalf("manifest[id] = %v, want %v", got, want)
	}
	panels, ok := manifest["panels"].([]any)
	if !ok || len(panels) != 1 {
		t.Fatalf("manifest[panels] = %#v, want one panel", manifest["panels"])
	}
	panel, ok := panels[0].(map[string]any)
	if !ok || panel["kind"] != "board" {
		t.Fatalf("panel = %#v, want board panel", panels[0])
	}
}

// TestRenderPackageRejectsEscapedEntrypoint verifies entrypoints stay inside the
// app plugin package directory.
func TestRenderPackageRejectsEscapedEntrypoint(t *testing.T) {
	dir := t.TempDir()
	if _, err := RenderPackage(context.Background(), dir, "../app.star"); err == nil {
		t.Fatal("RenderPackage() error = nil, want package-local entrypoint error")
	}
}

// TestRenderFileRejectsWrongSignature verifies render() cannot depend on hidden
// runtime arguments.
func TestRenderFileRejectsWrongSignature(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "app.star")
	if err := os.WriteFile(path, []byte(`
def render(context):
    return {}
`), 0o600); err != nil {
		t.Fatalf("WriteFile(app.star) error = %v", err)
	}

	if _, err := RenderFile(context.Background(), path); err == nil {
		t.Fatal("RenderFile() error = nil, want render ABI error")
	}
}

// TestRenderFileCancelsRunawayStarlark verifies scripts cannot run forever.
func TestRenderFileCancelsRunawayStarlark(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "app.star")
	if err := os.WriteFile(path, []byte(`
def render():
    while True:
        pass
    return {}
`), 0o600); err != nil {
		t.Fatalf("WriteFile(app.star) error = %v", err)
	}

	if _, err := RenderFile(context.Background(), path); err == nil {
		t.Fatal("RenderFile() error = nil, want runaway script error")
	}
}
