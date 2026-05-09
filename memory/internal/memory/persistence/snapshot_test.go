// This file tests snapshot archive save and atomic restore behavior.
package persistence

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
)

// TestSnapshotRoundTrip verifies database and evidence files survive archive restore.
func TestSnapshotRoundTrip(t *testing.T) {
	source := t.TempDir()
	sourceDB := filepath.Join(source, "memory.db")
	sourceData := filepath.Join(source, "data")
	if err := os.MkdirAll(filepath.Join(sourceData, "evidence"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sourceDB, []byte("sqlite bytes"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sourceData, "evidence", "a.txt"), []byte("evidence"), 0o600); err != nil {
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
	evidence, err := os.ReadFile(filepath.Join(targetData, "evidence", "a.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if string(evidence) != "evidence" {
		t.Fatalf("evidence = %q, want evidence", evidence)
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
		"data/evidence/new.txt": "new evidence",
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
		Name:     "data/evidence/link.txt",
		Typeflag: tar.TypeSymlink,
		Linkname: "/tmp/nope",
		Mode:     0o600,
	}})

	if err := extractSnapshot(bytes.NewReader(archive), targetDB, targetData); err == nil {
		t.Fatal("extractSnapshot() error = nil, want unsupported entry error")
	}
	assertExistingSnapshot(t, targetDB, targetData)
}

// existingSnapshotTarget creates live data that should survive failed restores.
func existingSnapshotTarget(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	targetDB := filepath.Join(root, "memory.db")
	targetData := filepath.Join(root, "data")
	if err := os.MkdirAll(filepath.Join(targetData, "evidence"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(targetDB, []byte("existing db"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(targetData, "evidence", "existing.txt"), []byte("existing evidence"), 0o600); err != nil {
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
	evidence, err := os.ReadFile(filepath.Join(targetData, "evidence", "existing.txt"))
	if err != nil {
		t.Fatalf("read existing evidence: %v", err)
	}
	if string(evidence) != "existing evidence" {
		t.Fatalf("evidence = %q, want existing evidence", evidence)
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
