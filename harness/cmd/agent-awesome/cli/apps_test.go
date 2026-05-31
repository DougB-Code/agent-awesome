// This file tests app plugin CLI commands.
package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestAppsRenderWritesManifest verifies the CLI executes a Starlark app plugin
// entrypoint and writes a manifest.
func TestAppsRenderWritesManifest(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "app.star"), []byte(`
def render():
    return {
        "id": "workflow-board",
        "name": "Workflow Board",
        "panels": [{"id": "board", "title": "Board", "kind": "board"}],
    }
`), 0o600); err != nil {
		t.Fatalf("WriteFile(app.star) error = %v", err)
	}
	var stdout bytes.Buffer
	cmd := newAppsCommandWithWriter(context.Background(), &stdout)
	cmd.SetArgs([]string{"render", dir})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "workflow-board") || !strings.Contains(got, "panels:") {
		t.Fatalf("stdout = %q, want rendered YAML manifest", got)
	}
}

// TestAppsRenderWritesJSON verifies the render command supports machine output.
func TestAppsRenderWritesJSON(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "plugin.star"), []byte(`
def render():
    return {"id": "calendar-sync", "name": "Calendar Sync", "panels": []}
`), 0o600); err != nil {
		t.Fatalf("WriteFile(plugin.star) error = %v", err)
	}
	var stdout bytes.Buffer
	cmd := newAppsCommandWithWriter(context.Background(), &stdout)
	cmd.SetArgs([]string{"render", dir, "--entrypoint", "plugin.star", "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, `"id":"calendar-sync"`) {
		t.Fatalf("stdout = %q, want rendered JSON manifest", got)
	}
}

// TestAppsTemplateWritesAppleCalendarManifest verifies the Apple Calendar
// plugin template is exposed through the app plugin CLI.
func TestAppsTemplateWritesAppleCalendarManifest(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAppsCommandWithWriter(context.Background(), &stdout)
	cmd.SetArgs([]string{"template", "apple-calendar", "--profile", "Personal"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "apple-calendar") ||
		!strings.Contains(got, "AA_APPLE_CALENDAR_PERSONAL_APP_PASSWORD") {
		t.Fatalf("stdout = %q, want Apple Calendar manifest template", got)
	}
}
