// This file tests graph-backed codebase catalog persistence and resolution.
package repository

import (
	"context"
	"reflect"
	"testing"

	"memory/internal/memory/domain"
)

// TestCodebaseCatalogRoundTrip verifies typed records persist through graph storage.
func TestCodebaseCatalogRoundTrip(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()

	saved, err := repo.UpsertCodebase(ctx, domain.UpsertCodebaseRequest{Codebase: domain.Codebase{
		Name:               "Agent Awesome",
		Aliases:            []string{"AA"},
		RepositoryPath:     "/home/doug/dev/agentawesome/agent",
		DefaultRemote:      "origin",
		DefaultBranch:      "main",
		Provider:           "github",
		ProviderRepository: "github.com/doug/agentawesome.git",
		RuntimeTargetID:    "this_computer",
		AgentProfileID:     "automation_agent",
	}})
	if err != nil {
		t.Fatalf("UpsertCodebase() error = %v", err)
	}
	loaded, err := repo.GetCodebase(ctx, domain.CodebaseIDRequest{ID: saved.ID})
	if err != nil {
		t.Fatalf("GetCodebase() error = %v", err)
	}
	if loaded.Name != "Agent Awesome" || loaded.RepositoryPath == "" || loaded.ProviderRepository != "doug/agentawesome" {
		t.Fatalf("loaded = %#v, want saved codebase metadata", loaded)
	}
	if !reflect.DeepEqual(loaded.Aliases, []string{"aa", "agent awesome"}) {
		t.Fatalf("aliases = %#v, want normalized aliases", loaded.Aliases)
	}
	listed, err := repo.ListCodebases(ctx, domain.CodebaseQuery{Text: "agent", Limit: 10})
	if err != nil {
		t.Fatalf("ListCodebases() error = %v", err)
	}
	if len(listed) != 1 || listed[0].ID != loaded.ID {
		t.Fatalf("listed = %#v, want saved codebase", listed)
	}
}

// TestResolveCodebaseReturnsStrongMatch verifies alias lookup does not need a path.
func TestResolveCodebaseReturnsStrongMatch(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()
	if _, err := repo.UpsertCodebase(ctx, domain.UpsertCodebaseRequest{Codebase: domain.Codebase{Name: "Agent Awesome", Aliases: []string{"AA"}, RepositoryPath: "/repo"}}); err != nil {
		t.Fatalf("UpsertCodebase() error = %v", err)
	}
	resolved, err := repo.ResolveCodebase(ctx, domain.ResolveCodebaseRequest{Query: "Agent Awesome"})
	if err != nil {
		t.Fatalf("ResolveCodebase() error = %v", err)
	}
	if resolved.Status != "matched" || resolved.Codebase == nil || resolved.Codebase.RepositoryPath != "/repo" {
		t.Fatalf("resolution = %#v, want matched Agent Awesome", resolved)
	}
}

// TestResolveCodebaseReturnsAmbiguity verifies ambiguous aliases are not guessed.
func TestResolveCodebaseReturnsAmbiguity(t *testing.T) {
	ctx := context.Background()
	repo := openTestRepository(t)
	defer repo.Close()
	if _, err := repo.UpsertCodebase(ctx, domain.UpsertCodebaseRequest{Codebase: domain.Codebase{Name: "Agent Awesome", Aliases: []string{"AA"}, RepositoryPath: "/repo/one"}}); err != nil {
		t.Fatalf("Upsert first error = %v", err)
	}
	if _, err := repo.UpsertCodebase(ctx, domain.UpsertCodebaseRequest{Codebase: domain.Codebase{Name: "Analytics App", Aliases: []string{"AA"}, RepositoryPath: "/repo/two"}}); err != nil {
		t.Fatalf("Upsert second error = %v", err)
	}
	resolved, err := repo.ResolveCodebase(ctx, domain.ResolveCodebaseRequest{Query: "AA"})
	if err != nil {
		t.Fatalf("ResolveCodebase() error = %v", err)
	}
	if resolved.Status != "ambiguous" || len(resolved.Matches) != 2 {
		t.Fatalf("resolution = %#v, want two ambiguous matches", resolved)
	}
}
