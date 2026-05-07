package state

import (
	"testing"

	"github.com/zalando/go-keyring"
)

// TestKeyringSecretStoreEnsureGeneratedReusesToken verifies apply idempotency.
func TestKeyringSecretStoreEnsureGeneratedReusesToken(t *testing.T) {
	keyring.MockInit()
	store := NewKeyringSecretStore("agent-awesome-test")

	first, err := store.EnsureGenerated("provision/sister/TOKEN")
	if err != nil {
		t.Fatalf("EnsureGenerated() error = %v", err)
	}
	second, err := store.EnsureGenerated("provision/sister/TOKEN")
	if err != nil {
		t.Fatalf("EnsureGenerated() second error = %v", err)
	}
	if first == "" || second == "" || first != second {
		t.Fatalf("generated tokens first=%q second=%q, want stable non-empty token", first, second)
	}
}

// TestKeyringSecretStoreSetAndDelete verifies operator credentials can be managed.
func TestKeyringSecretStoreSetAndDelete(t *testing.T) {
	keyring.MockInit()
	store := NewKeyringSecretStore("agent-awesome-test")

	if err := store.Set("OPENAI_API_KEY", "secret"); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	value, err := store.Lookup("OPENAI_API_KEY")
	if err != nil {
		t.Fatalf("Lookup() error = %v", err)
	}
	if value != "secret" {
		t.Fatalf("Lookup() = %q, want secret", value)
	}
	if err := store.Delete("OPENAI_API_KEY"); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if _, err := store.Lookup("OPENAI_API_KEY"); err == nil {
		t.Fatalf("Lookup() error = nil after delete")
	}
}
