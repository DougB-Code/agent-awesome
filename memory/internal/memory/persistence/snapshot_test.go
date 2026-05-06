package persistence

import (
	"bytes"
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

// TestSnapshotTargetRejectsUnsafeEntries verifies archive traversal is ignored.
func TestSnapshotTargetRejectsUnsafeEntries(t *testing.T) {
	if _, ok := snapshotTarget("../secret", "/tmp/memory.db", "/tmp/data"); ok {
		t.Fatal("snapshotTarget accepted traversal")
	}
}
