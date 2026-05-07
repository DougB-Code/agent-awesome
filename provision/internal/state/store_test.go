package state

import (
	"errors"
	"testing"
)

// TestStoreSaveAndLoad verifies non-secret agent metadata persists on disk.
func TestStoreSaveAndLoad(t *testing.T) {
	store := NewStore(t.TempDir())
	saved, err := store.Save(AgentRecord{
		AgentID:    "sister",
		UserID:     "sister",
		Hostname:   "sister.agent-awesome.com",
		WorkerName: "agent-awesome-sister",
		BucketName: "agent-awesome-sister-memory",
	})
	if err != nil {
		t.Fatalf("Save() error = %v", err)
	}

	loaded, err := store.Load("sister")
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if loaded.WorkerName != saved.WorkerName {
		t.Fatalf("WorkerName = %q, want %q", loaded.WorkerName, saved.WorkerName)
	}
	if loaded.CreatedAt.IsZero() || loaded.UpdatedAt.IsZero() {
		t.Fatalf("timestamps were not populated: %#v", loaded)
	}
}

// TestStoreLoadMissingReturnsNotFound verifies callers can distinguish absent records.
func TestStoreLoadMissingReturnsNotFound(t *testing.T) {
	_, err := NewStore(t.TempDir()).Load("missing")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("Load() error = %v, want ErrNotFound", err)
	}
}

// TestStoreDeleteRemovesRecord verifies local cleanup removes saved metadata.
func TestStoreDeleteRemovesRecord(t *testing.T) {
	store := NewStore(t.TempDir())
	if _, err := store.Save(AgentRecord{AgentID: "sister"}); err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	if err := store.Delete("sister"); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if _, err := store.Load("sister"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Load() error = %v, want ErrNotFound", err)
	}
}

// TestStoreListSortsRecords verifies list output is stable for operators.
func TestStoreListSortsRecords(t *testing.T) {
	store := NewStore(t.TempDir())
	if _, err := store.Save(AgentRecord{AgentID: "zoe", Hostname: "zoe.example.com"}); err != nil {
		t.Fatalf("Save(zoe) error = %v", err)
	}
	if _, err := store.Save(AgentRecord{AgentID: "anna", Hostname: "anna.example.com"}); err != nil {
		t.Fatalf("Save(anna) error = %v", err)
	}

	records, err := store.List()
	if err != nil {
		t.Fatalf("List() error = %v", err)
	}
	if len(records) != 2 || records[0].AgentID != "anna" || records[1].AgentID != "zoe" {
		t.Fatalf("List() = %#v, want sorted anna then zoe", records)
	}
}

// TestCredentialNameIsAgentScoped verifies generated token names are isolated.
func TestCredentialNameIsAgentScoped(t *testing.T) {
	if got, want := CredentialName("sister", "TOKEN"), "provision/sister/TOKEN"; got != want {
		t.Fatalf("CredentialName() = %q, want %q", got, want)
	}
}
