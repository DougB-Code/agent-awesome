// This file tests snapshot archive save and atomic restore behavior.
package persistence

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"memory/internal/memory/domain"
	graphrepo "memory/internal/memory/graph/repository"
	"memory/internal/memory/service"
)

// TestSnapshotRoundTrip verifies database and source files survive archive restore.
func TestSnapshotRoundTrip(t *testing.T) {
	source := t.TempDir()
	sourceDB := filepath.Join(source, "memory.db")
	sourceData := filepath.Join(source, "data")
	if err := os.MkdirAll(filepath.Join(sourceData, "sources"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sourceDB, []byte("sqlite bytes"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sourceData, "sources", "a.txt"), []byte("source"), 0o600); err != nil {
		t.Fatal(err)
	}
	archive, err := buildSnapshot(sourceDB, sourceData)
	if err != nil {
		t.Fatal(err)
	}

	target := t.TempDir()
	targetDB := filepath.Join(target, "memory.db")
	targetData := filepath.Join(target, "data")
	if err := extractSnapshot(bytes.NewReader(archive), targetDB, targetData); err != nil {
		t.Fatal(err)
	}
	dbData, err := os.ReadFile(targetDB)
	if err != nil {
		t.Fatal(err)
	}
	if string(dbData) != "sqlite bytes" {
		t.Fatalf("db = %q, want sqlite bytes", dbData)
	}
	sourceFile, err := os.ReadFile(filepath.Join(targetData, "sources", "a.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(sourceFile) != "source" {
		t.Fatalf("source = %q, want source", sourceFile)
	}
}

// TestSnapshotTargetRejectsUnsafeEntries verifies archive traversal is rejected.
func TestSnapshotTargetRejectsUnsafeEntries(t *testing.T) {
	if _, _, err := snapshotTarget("../secret", "/tmp/memory.db", "/tmp/data"); err == nil {
		t.Fatal("snapshotTarget accepted traversal")
	}
}

// TestRestoreRejectsCorruptArchiveWithoutDeletingExistingData verifies corrupt snapshots are inert.
func TestRestoreRejectsCorruptArchiveWithoutDeletingExistingData(t *testing.T) {
	targetDB, targetData := existingSnapshotTarget(t)

	if err := extractSnapshot(bytes.NewReader([]byte("not a gzip")), targetDB, targetData); err == nil {
		t.Fatal("extractSnapshot() error = nil, want corrupt archive error")
	}
	assertExistingSnapshot(t, targetDB, targetData)
}

// TestRestoreRejectsMissingDBWithoutDeletingExistingData verifies required DB validation.
func TestRestoreRejectsMissingDBWithoutDeletingExistingData(t *testing.T) {
	targetDB, targetData := existingSnapshotTarget(t)
	archive := testSnapshotArchive(t, map[string]string{
		"data/sources/new.txt": "new source",
	}, nil)

	if err := extractSnapshot(bytes.NewReader(archive), targetDB, targetData); err == nil {
		t.Fatal("extractSnapshot() error = nil, want missing DB error")
	}
	assertExistingSnapshot(t, targetDB, targetData)
}

// TestRestoreRejectsTraversalWithoutDeletingExistingData verifies unsafe paths fail closed.
func TestRestoreRejectsTraversalWithoutDeletingExistingData(t *testing.T) {
	targetDB, targetData := existingSnapshotTarget(t)
	archive := testSnapshotArchive(t, map[string]string{
		"memory.db": "new db",
		"../secret": "nope",
	}, nil)

	if err := extractSnapshot(bytes.NewReader(archive), targetDB, targetData); err == nil {
		t.Fatal("extractSnapshot() error = nil, want traversal error")
	}
	assertExistingSnapshot(t, targetDB, targetData)
}

// TestRestoreFailureLeavesPreviousDataReadable verifies late extract errors do not promote.
func TestRestoreFailureLeavesPreviousDataReadable(t *testing.T) {
	targetDB, targetData := existingSnapshotTarget(t)
	archive := testSnapshotArchive(t, map[string]string{
		"memory.db": "new db",
	}, []tar.Header{{
		Name:     "data/sources/link.txt",
		Typeflag: tar.TypeSymlink,
		Linkname: "/tmp/nope",
		Mode:     0o600,
	}})

	if err := extractSnapshot(bytes.NewReader(archive), targetDB, targetData); err == nil {
		t.Fatal("extractSnapshot() error = nil, want unsupported entry error")
	}
	assertExistingSnapshot(t, targetDB, targetData)
}

// TestHTTPStoreSnapshotDrillRestoresMemoryAndTasks verifies the beta snapshot workflow.
func TestHTTPStoreSnapshotDrillRestoresMemoryAndTasks(t *testing.T) {
	ctx := context.Background()
	token := "snapshot-token"
	var savedSnapshot []byte
	endpoint := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token {
			http.NotFound(w, r)
			return
		}
		switch r.Method {
		case http.MethodGet:
			if len(savedSnapshot) == 0 {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Type", "application/gzip")
			_, _ = w.Write(savedSnapshot)
		case http.MethodPut:
			data, err := io.ReadAll(r.Body)
			if err != nil {
				http.Error(w, "read snapshot", http.StatusBadRequest)
				return
			}
			savedSnapshot = append(savedSnapshot[:0], data...)
			w.WriteHeader(http.StatusNoContent)
		default:
			http.NotFound(w, r)
		}
	}))
	defer endpoint.Close()

	sourceRoot := t.TempDir()
	sourceDB := filepath.Join(sourceRoot, "memory.db")
	sourceData := filepath.Join(sourceRoot, "data")
	source := openSnapshotDrillService(t, sourceDB, sourceData)
	capture, err := source.Capture(ctx, domain.CaptureRequest{
		Actor:          "snapshot-test",
		Content:        "Snapshot drill preference survives redeploy.",
		Title:          "Snapshot drill preference",
		Scope:          domain.ScopeUser,
		Kind:           domain.KindProfileFact,
		TrustLevel:     domain.TrustUserAsserted,
		IdempotencyKey: "snapshot-drill-memory",
	})
	if err != nil {
		t.Fatalf("capture memory: %v", err)
	}
	task, err := source.CreateTask(ctx, domain.CreateTaskRequest{
		Actor:          "snapshot-test",
		Title:          "Verify restored task",
		IdempotencyKey: "snapshot-drill-task",
	})
	if err != nil {
		t.Fatalf("create task: %v", err)
	}
	if err := source.Close(ctx); err != nil {
		t.Fatalf("close source service: %v", err)
	}

	store := HTTPStore{URL: endpoint.URL, Token: token, Timeout: 5 * time.Second, Client: endpoint.Client()}
	if err := store.Save(ctx, sourceDB, sourceData); err != nil {
		t.Fatalf("save snapshot: %v", err)
	}
	if len(savedSnapshot) == 0 {
		t.Fatalf("saved snapshot is empty")
	}

	restoreRoot := t.TempDir()
	restoreDB := filepath.Join(restoreRoot, "memory.db")
	restoreData := filepath.Join(restoreRoot, "data")
	if err := store.Restore(ctx, restoreDB, restoreData); err != nil {
		t.Fatalf("restore snapshot: %v", err)
	}
	restored := openSnapshotDrillService(t, restoreDB, restoreData)
	defer restored.Close(context.Background())

	bundle, err := restored.SearchSources(ctx, domain.RetrievalQuery{
		Scope: domain.ScopeUser,
		Text:  "preference survives redeploy",
		Limit: 10,
	})
	if err != nil {
		t.Fatalf("search restored memory: %v", err)
	}
	if len(bundle.Primary) != 1 || bundle.Primary[0].ID != capture.MemoryID {
		t.Fatalf("restored memory = %#v, want %s", bundle.Primary, capture.MemoryID)
	}
	if bundle.Primary[0].Raw == nil || !strings.Contains(bundle.Primary[0].Raw.ContentText, "survives redeploy") {
		t.Fatalf("restored raw source = %#v, want original content", bundle.Primary[0].Raw)
	}

	tasks, err := restored.ListTasks(ctx, domain.TaskQuery{Search: "Verify restored task", IncludeDone: true, Limit: 10})
	if err != nil {
		t.Fatalf("list restored tasks: %v", err)
	}
	if len(tasks) != 1 || tasks[0].ID != task.ID {
		t.Fatalf("restored tasks = %#v, want %s", tasks, task.ID)
	}
}

// TestHTTPStoreRestoreIgnoresMissingAndEmptySnapshots verifies first boot behavior.
func TestHTTPStoreRestoreIgnoresMissingAndEmptySnapshots(t *testing.T) {
	ctx := context.Background()
	responses := []struct {
		status int
		body   string
	}{
		{status: http.StatusNotFound},
		{status: http.StatusOK, body: ""},
	}
	for _, response := range responses {
		endpoint := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(response.status)
			_, _ = w.Write([]byte(response.body))
		}))
		store := HTTPStore{URL: endpoint.URL, Token: "token", Timeout: 5 * time.Second, Client: endpoint.Client()}
		err := store.Restore(ctx, filepath.Join(t.TempDir(), "memory.db"), filepath.Join(t.TempDir(), "data"))
		endpoint.Close()
		if err != nil {
			t.Fatalf("Restore() for HTTP %d body %q error = %v", response.status, response.body, err)
		}
	}
}

// TestHTTPStoreRestoreRejectsCorruptSnapshot verifies bad remote archives fail closed.
func TestHTTPStoreRestoreRejectsCorruptSnapshot(t *testing.T) {
	ctx := context.Background()
	targetDB, targetData := existingSnapshotTarget(t)
	endpoint := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("not a gzip"))
	}))
	defer endpoint.Close()

	store := HTTPStore{URL: endpoint.URL, Token: "token", Timeout: 5 * time.Second, Client: endpoint.Client()}
	if err := store.Restore(ctx, targetDB, targetData); err == nil {
		t.Fatal("Restore() error = nil, want corrupt archive error")
	}
	assertExistingSnapshot(t, targetDB, targetData)
}

// openSnapshotDrillService opens a graph-backed memory service for snapshot tests.
func openSnapshotDrillService(t *testing.T, dbPath string, dataRoot string) *service.Service {
	t.Helper()
	repo, err := graphrepo.Open(context.Background(), graphrepo.Config{DBPath: dbPath, DataRoot: dataRoot})
	if err != nil {
		t.Fatalf("open graph repository: %v", err)
	}
	return service.New(repo, nil, service.Config{})
}

// existingSnapshotTarget creates live data that should survive failed restores.
func existingSnapshotTarget(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	targetDB := filepath.Join(root, "memory.db")
	targetData := filepath.Join(root, "data")
	if err := os.MkdirAll(filepath.Join(targetData, "sources"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(targetDB, []byte("existing db"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(targetData, "sources", "existing.txt"), []byte("existing source"), 0o600); err != nil {
		t.Fatal(err)
	}
	return targetDB, targetData
}

// assertExistingSnapshot verifies live data remains readable.
func assertExistingSnapshot(t *testing.T, targetDB string, targetData string) {
	t.Helper()
	db, err := os.ReadFile(targetDB)
	if err != nil {
		t.Fatalf("read existing db: %v", err)
	}
	if string(db) != "existing db" {
		t.Fatalf("db = %q, want existing db", db)
	}
	source, err := os.ReadFile(filepath.Join(targetData, "sources", "existing.txt"))
	if err != nil {
		t.Fatalf("read existing source: %v", err)
	}
	if string(source) != "existing source" {
		t.Fatalf("source = %q, want existing source", source)
	}
}

// testSnapshotArchive builds a gzip tar archive for restore tests.
func testSnapshotArchive(t *testing.T, files map[string]string, extraHeaders []tar.Header) []byte {
	t.Helper()
	var buf bytes.Buffer
	gzipWriter := gzip.NewWriter(&buf)
	tarWriter := tar.NewWriter(gzipWriter)
	for name, content := range files {
		header := &tar.Header{Name: name, Mode: 0o600, Size: int64(len(content)), Typeflag: tar.TypeReg}
		if err := tarWriter.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if _, err := tarWriter.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	for _, header := range extraHeaders {
		if err := tarWriter.WriteHeader(&header); err != nil {
			t.Fatal(err)
		}
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}
