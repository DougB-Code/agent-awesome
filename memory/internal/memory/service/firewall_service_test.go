// This file tests service-boundary memory firewall authorization.
package service

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	"memory/internal/memory/domain"
	graphrepo "memory/internal/memory/graph/repository"
)

// TestFirewallPolicyRestrictsMemoryReadWrite verifies service operations honor firewall grants.
func TestFirewallPolicyRestrictsMemoryReadWrite(t *testing.T) {
	ctx := context.Background()
	service := newTestServiceWithFirewallPolicy(t, FirewallPolicy{
		Firewalls: []FirewallRule{
			{Firewall: domain.FirewallUser, Readers: []string{"reader", "both"}, Writers: []string{"writer"}},
			{Firewall: domain.FirewallGlobal, Readers: []string{"both"}, Writers: []string{"global-writer"}},
		},
	})

	if _, err := service.Capture(ctx, domain.CaptureRequest{Actor: "reader", Content: "policy denied write", Firewall: domain.FirewallUser}); err == nil {
		t.Fatal("reader capture should be denied")
	}
	userCapture, err := service.Capture(ctx, domain.CaptureRequest{
		Actor:    "writer",
		Content:  "policy user source",
		Title:    "Policy User",
		Firewall: domain.FirewallUser,
	})
	if err != nil {
		t.Fatalf("capture user memory: %v", err)
	}
	if _, err := service.Capture(ctx, domain.CaptureRequest{
		Actor:    "global-writer",
		Content:  "policy global source",
		Title:    "Policy Global",
		Firewall: domain.FirewallGlobal,
	}); err != nil {
		t.Fatalf("capture global memory: %v", err)
	}
	if _, err := service.SearchMemory(ctx, domain.RetrievalQuery{Actor: "intruder", Firewall: domain.FirewallUser, Text: "policy"}); err == nil {
		t.Fatal("intruder search should be denied")
	}
	bundle, err := service.SearchMemory(ctx, domain.RetrievalQuery{Actor: "reader", Firewall: domain.FirewallUser, Text: "policy", Limit: 10})
	if err != nil {
		t.Fatalf("reader search: %v", err)
	}
	if len(bundle.Primary) != 1 || bundle.Primary[0].ID != userCapture.MemoryID {
		t.Fatalf("reader primary = %#v, want only user memory %s", bundle.Primary, userCapture.MemoryID)
	}
	if _, err := service.SearchMemory(ctx, domain.RetrievalQuery{Actor: "reader", Firewall: domain.FirewallUser, IncludeGlobal: true, Text: "policy"}); err == nil {
		t.Fatal("reader global-inclusive search should be denied")
	}
	bundle, err = service.SearchMemory(ctx, domain.RetrievalQuery{Actor: "both", Firewall: domain.FirewallUser, IncludeGlobal: true, Text: "policy", Limit: 10})
	if err != nil {
		t.Fatalf("both search: %v", err)
	}
	if len(bundle.Primary) != 2 {
		t.Fatalf("global-inclusive primary count = %d, want 2", len(bundle.Primary))
	}
	if _, err := service.LoadEntityPageForActor(ctx, "reader", domain.FirewallUser, domain.EntityID("entity:policy"), "Policy"); err == nil {
		t.Fatal("reader page load should be denied because it may create or rebuild a page")
	}
}

// TestFirewallPolicyRestrictsGraphQueries verifies graph queries check read and write grants.
func TestFirewallPolicyRestrictsGraphQueries(t *testing.T) {
	ctx := context.Background()
	service := newTestServiceWithFirewallPolicy(t, FirewallPolicy{
		Firewalls: []FirewallRule{
			{Firewall: domain.FirewallUser, Readers: []string{"reader"}, Writers: []string{"writer"}},
		},
	})
	if _, err := service.Capture(ctx, domain.CaptureRequest{Actor: "writer", Content: "graph policy source", Firewall: domain.FirewallUser}); err != nil {
		t.Fatalf("capture graph memory: %v", err)
	}
	if _, err := service.QueryContextGraph(ctx, domain.GraphQueryRequest{Actor: "intruder", Firewall: domain.FirewallUser, Query: `FIND memory RETURN title LIMIT 10`}); err == nil {
		t.Fatal("intruder graph read should be denied")
	}
	result, err := service.QueryContextGraph(ctx, domain.GraphQueryRequest{Actor: "reader", Firewall: domain.FirewallUser, Query: `FIND memory RETURN title LIMIT 10`})
	if err != nil {
		t.Fatalf("reader graph query: %v", err)
	}
	if len(result.Rows) != 1 {
		t.Fatalf("reader graph rows = %d, want 1", len(result.Rows))
	}
	_, err = service.QueryContextGraph(ctx, domain.GraphQueryRequest{
		Actor:        "reader",
		Firewall:     domain.FirewallUser,
		Query:        `INSERT NODE task SET title = "Denied"`,
		SourceNodeID: "source:test",
	})
	if err == nil || !strings.Contains(err.Error(), "cannot write") {
		t.Fatalf("reader graph mutation error = %v, want write denial", err)
	}
}

// TestGraphMutationRequiresExplicitActor verifies service normalization keeps mutation provenance strict.
func TestGraphMutationRequiresExplicitActor(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)
	_, err := service.QueryContextGraph(ctx, domain.GraphQueryRequest{
		Query:        `INSERT NODE task SET title = "No actor"`,
		SourceNodeID: "source:test",
	})
	if err == nil || !strings.Contains(err.Error(), "actor is required") {
		t.Fatalf("mutation error = %v, want explicit actor requirement", err)
	}
}

// newTestServiceWithFirewallPolicy creates an isolated service with a normalized policy.
func newTestServiceWithFirewallPolicy(t *testing.T, policy FirewallPolicy) *Service {
	t.Helper()
	root := t.TempDir()
	repo, err := graphrepo.Open(context.Background(), graphrepo.Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = repo.Close() })
	normalized, err := NormalizeFirewallPolicy(policy)
	if err != nil {
		t.Fatalf("normalize policy: %v", err)
	}
	return New(RepositoriesFrom(repo), nil, Config{FirewallPolicy: &normalized})
}
