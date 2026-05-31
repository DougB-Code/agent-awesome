package repository

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"memory/internal/memory/domain"
)

// TestPoolRoutesMemoryByDomain verifies each memory boundary gets its own SQLite file.
func TestPoolRoutesMemoryByDomain(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	pool, err := OpenPool(ctx, Config{DataRoot: filepath.Join(root, "data")})
	if err != nil {
		t.Fatalf("open pool: %v", err)
	}
	defer pool.Close()

	userCapture, err := pool.Capture(ctx, domain.CaptureRequest{DomainID: domain.DomainUser, Content: "pool user memory"})
	if err != nil {
		t.Fatalf("capture user: %v", err)
	}
	projectCapture, err := pool.Capture(ctx, domain.CaptureRequest{DomainID: domain.DomainProject, Content: "pool project memory"})
	if err != nil {
		t.Fatalf("capture project: %v", err)
	}
	for _, domainID := range []domain.DomainID{domain.DomainUser, domain.DomainProject} {
		path := filepath.Join(root, "data", "domains", string(domainID), domainDatabaseName)
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("stat domain db %s: %v", path, err)
		}
	}

	userRecords, err := pool.Search(ctx, domain.RetrievalQuery{DomainID: domain.DomainUser, Text: "pool", Limit: 10})
	if err != nil {
		t.Fatalf("search user: %v", err)
	}
	if got := memoryIDs(userRecords); !reflect.DeepEqual(got, []domain.MemoryID{userCapture.MemoryID}) {
		t.Fatalf("user records = %#v, want only user memory", got)
	}
	projectRecords, err := pool.Search(ctx, domain.RetrievalQuery{DomainID: domain.DomainProject, Text: "pool", Limit: 10})
	if err != nil {
		t.Fatalf("search project: %v", err)
	}
	if got := memoryIDs(projectRecords); !reflect.DeepEqual(got, []domain.MemoryID{projectCapture.MemoryID}) {
		t.Fatalf("project records = %#v, want only project memory", got)
	}
}

// TestPoolSearchIncludesGlobalDomain verifies global reads are a pool-level merge.
func TestPoolSearchIncludesGlobalDomain(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	pool, err := OpenPool(ctx, Config{DataRoot: filepath.Join(root, "data")})
	if err != nil {
		t.Fatalf("open pool: %v", err)
	}
	defer pool.Close()

	userCapture, err := pool.Capture(ctx, domain.CaptureRequest{DomainID: domain.DomainUser, Content: "shared pool user memory"})
	if err != nil {
		t.Fatalf("capture user: %v", err)
	}
	globalCapture, err := pool.Capture(ctx, domain.CaptureRequest{DomainID: domain.DomainGlobal, Content: "shared pool global memory"})
	if err != nil {
		t.Fatalf("capture global: %v", err)
	}
	records, err := pool.Search(ctx, domain.RetrievalQuery{DomainID: domain.DomainUser, IncludeGlobal: true, Text: "shared", Limit: 10})
	if err != nil {
		t.Fatalf("search with global: %v", err)
	}
	wantIDs := []domain.MemoryID{globalCapture.MemoryID, userCapture.MemoryID}
	sortMemoryIDs(wantIDs)
	if got := memoryIDs(records); !reflect.DeepEqual(got, wantIDs) {
		t.Fatalf("records = %#v, want global and user memories", got)
	}
	if records[0].DomainID != domain.DomainUser || records[1].DomainID != domain.DomainGlobal {
		t.Fatalf("record domains = %q/%q, want user/global", records[0].DomainID, records[1].DomainID)
	}
}

// TestPoolCreatesAndRemovesDomainWithoutRestart verifies live pool membership changes.
func TestPoolCreatesAndRemovesDomainWithoutRestart(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	pool, err := OpenPool(ctx, Config{DataRoot: filepath.Join(root, "data")})
	if err != nil {
		t.Fatalf("open pool: %v", err)
	}
	defer pool.Close()

	info, err := pool.CreateMemoryDomain(ctx, domain.DomainID("client-a"))
	if err != nil {
		t.Fatalf("create domain: %v", err)
	}
	if !info.Open || !info.Exists {
		t.Fatalf("created domain info = %#v, want open existing db", info)
	}
	if _, err := pool.Capture(ctx, domain.CaptureRequest{DomainID: domain.DomainID("client-a"), Content: "client alpha memory"}); err != nil {
		t.Fatalf("capture client memory: %v", err)
	}
	detached, err := pool.RemoveMemoryDomain(ctx, domain.DomainID("client-a"), false)
	if err != nil {
		t.Fatalf("detach domain: %v", err)
	}
	if detached.Open || !detached.Exists {
		t.Fatalf("detached domain info = %#v, want closed db still on disk", detached)
	}
	records, err := pool.Search(ctx, domain.RetrievalQuery{DomainID: domain.DomainID("client-a"), Text: "alpha", Limit: 10})
	if err != nil {
		t.Fatalf("search detached domain: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("records after detach = %#v, want reopened record", records)
	}
	deleted, err := pool.RemoveMemoryDomain(ctx, domain.DomainID("client-a"), true)
	if err != nil {
		t.Fatalf("delete domain: %v", err)
	}
	if deleted.Exists || deleted.Open {
		t.Fatalf("deleted domain info = %#v, want no file and closed handle", deleted)
	}
	if _, err := os.Stat(filepath.Join(root, "data", "domains", "client-a")); !os.IsNotExist(err) {
		t.Fatalf("deleted domain root stat err = %v, want not exist", err)
	}
}

// sortMemoryIDs sorts memory ids for order-independent assertions.
func sortMemoryIDs(ids []domain.MemoryID) {
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
}
