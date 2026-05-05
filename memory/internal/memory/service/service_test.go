package service

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"agent-awesome.com/memoryinternal/agent-awesome.com/memorydomain"
	graphrepo "agent-awesome.com/memoryinternal/agent-awesome.com/memorygraph/repository"
)

// TestSearchMemoryBuildsRetrievalBundle verifies service-level retrieval context.
func TestSearchMemoryBuildsRetrievalBundle(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)

	first, err := service.Capture(ctx, domain.CaptureRequest{
		Content: "bundle source one",
		Title:   "Bundle one",
		Scope:   domain.ScopeUser,
		Source:  domain.SourceRef{System: "test", ID: "one"},
	})
	if err != nil {
		t.Fatalf("capture first: %v", err)
	}
	if _, err := service.Capture(ctx, domain.CaptureRequest{
		Content: "bundle source two",
		Title:   "Bundle two",
		Scope:   domain.ScopeUser,
		Source:  domain.SourceRef{System: "test", ID: "two"},
	}); err != nil {
		t.Fatalf("capture second: %v", err)
	}
	bundle, err := service.SearchMemory(ctx, domain.RetrievalQuery{Scope: domain.ScopeUser, Text: "bundle", Limit: 10})
	if err != nil {
		t.Fatalf("search memory: %v", err)
	}
	if len(bundle.Primary) != 2 || len(bundle.Supporting) != 1 || len(bundle.Provenance) != 2 {
		t.Fatalf("bundle sizes = primary %d supporting %d provenance %d", len(bundle.Primary), len(bundle.Supporting), len(bundle.Provenance))
	}
	foundFirst := false
	for _, record := range bundle.Primary {
		foundFirst = foundFirst || record.ID == first.MemoryID
	}
	if !foundFirst {
		t.Fatalf("bundle primary records = %#v, want memory %s", bundle.Primary, first.MemoryID)
	}
}

// TestSearchSourcesHydratesRawText verifies source search includes evidence content.
func TestSearchSourcesHydratesRawText(t *testing.T) {
	ctx := context.Background()
	service := newTestService(t)

	if _, err := service.Capture(ctx, domain.CaptureRequest{
		Content: "raw source text to hydrate",
		Title:   "Hydration",
		Scope:   domain.ScopeUser,
	}); err != nil {
		t.Fatalf("capture: %v", err)
	}
	bundle, err := service.SearchSources(ctx, domain.RetrievalQuery{Scope: domain.ScopeUser, Text: "hydrate"})
	if err != nil {
		t.Fatalf("search sources: %v", err)
	}
	if len(bundle.Primary) != 1 || bundle.Primary[0].Raw == nil {
		t.Fatalf("primary source = %#v, want hydrated raw evidence", bundle.Primary)
	}
	if !strings.Contains(bundle.Primary[0].Raw.ContentText, "raw source text") {
		t.Fatalf("raw content = %q, want source text", bundle.Primary[0].Raw.ContentText)
	}
}

// TestStewardDisabledWorkersComplete verifies the service works without a steward.
func TestStewardDisabledWorkersComplete(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	root := t.TempDir()
	repo, err := graphrepo.Open(ctx, graphrepo.Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	service := New(repo, nil, Config{WorkerCount: 2, PollInterval: 10 * time.Millisecond})
	service.Start(ctx)
	defer service.Close(context.Background())

	if _, err := service.Capture(ctx, domain.CaptureRequest{Content: "worker source", Scope: domain.ScopeUser}); err != nil {
		t.Fatalf("capture: %v", err)
	}
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		metrics, err := service.Metrics(ctx)
		if err != nil {
			t.Fatalf("metrics: %v", err)
		}
		if metrics.PendingJobs == 0 && metrics.FailedJobs == 0 {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	metrics, _ := service.Metrics(ctx)
	t.Fatalf("workers did not drain jobs: %#v", metrics)
}

// newTestService creates an isolated service with local durable storage.
func newTestService(t *testing.T) *Service {
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
	return New(repo, nil, Config{})
}
