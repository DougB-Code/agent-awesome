// This file tests deterministic Launch input resolution behavior.
package resolution

import (
	"context"
	"testing"
)

// TestResolverPrecedenceAndProvenance verifies earlier sources win by default.
func TestResolverPrecedenceAndProvenance(t *testing.T) {
	result, err := NewResolver().Resolve(context.Background(), Request{
		RequiredFields:    []string{"change_request", "repository_path"},
		RunRequest:        map[string]any{"change_request": "Fix crash", "remote": "fork"},
		LaunchDefaults: map[string]any{"remote": "origin"},
		CodebaseDefaults:  map[string]any{"repository_path": "/repo", "remote": "upstream"},
		RunbookDefaults:  map[string]any{"package_path": "."},
		GeneratedValues:   map[string]any{"commit_message": "Fix crash"},
	})
	if err != nil {
		t.Fatalf("Resolve() error = %v", err)
	}
	if result.Status != "resolved" {
		t.Fatalf("status = %q, want resolved", result.Status)
	}
	if result.Input["remote"] != "fork" || result.Fields["remote"].Source != SourceRunRequest {
		t.Fatalf("remote field = %#v, want run request winner", result.Fields["remote"])
	}
	if result.Fields["repository_path"].Source != SourceCodebaseDefault {
		t.Fatalf("repository_path source = %q, want codebase default", result.Fields["repository_path"].Source)
	}
	if len(result.Candidates["remote"]) != 2 {
		t.Fatalf("remote candidates = %#v, want lower-precedence diagnostics", result.Candidates["remote"])
	}
}

// TestResolverNeedsInput verifies missing required fields are structured.
func TestResolverNeedsInput(t *testing.T) {
	result, err := NewResolver().Resolve(context.Background(), Request{RequiredFields: []string{"change_request"}})
	if err != nil {
		t.Fatalf("Resolve() error = %v", err)
	}
	if result.Status != "needs_input" || len(result.Unresolved) != 1 {
		t.Fatalf("result = %#v, want one unresolved field", result)
	}
}

// TestResolverRedactsSecretValues verifies only references are persisted.
func TestResolverRedactsSecretValues(t *testing.T) {
	result, err := NewResolver().Resolve(context.Background(), Request{
		SecretReferences: map[string]any{"github_token": "raw-token"},
	})
	if err != nil {
		t.Fatalf("Resolve() error = %v", err)
	}
	if result.Input["github_token"] != "secret://redacted/github_token" {
		t.Fatalf("secret = %#v, want redacted reference", result.Input["github_token"])
	}
}
