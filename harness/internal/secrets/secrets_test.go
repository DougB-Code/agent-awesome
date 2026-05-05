// This file tests credential lookup, storage, and removal behavior.
package secrets

import (
	"bytes"
	"io"
	"strings"
	"testing"

	"github.com/zalando/go-keyring"
)

func TestLookupUsesKeyringBeforeEnv(t *testing.T) {
	go_keyringMockInit(t)
	t.Setenv("TEST_API_KEY", "env-value")
	if err := Set("TEST_API_KEY", "keyring-value"); err != nil {
		t.Fatalf("Set() error = %v", err)
	}

	got, err := Lookup("TEST_API_KEY")
	if err != nil {
		t.Fatalf("Lookup() error = %v", err)
	}
	if got.Value != "keyring-value" || got.Source != SourceKeyring {
		t.Fatalf("Lookup() = %#v, want keyring value", got)
	}
}

func TestLookupFallsBackToEnv(t *testing.T) {
	go_keyringMockInit(t)
	t.Setenv("TEST_API_KEY", "env-value")

	got, err := Lookup("TEST_API_KEY")
	if err != nil {
		t.Fatalf("Lookup() error = %v", err)
	}
	if got.Value != "env-value" || got.Source != SourceEnv {
		t.Fatalf("Lookup() = %#v, want env value", got)
	}
}

func TestRemoveDeletesKeyringCredential(t *testing.T) {
	go_keyringMockInit(t)
	if err := Set("TEST_API_KEY", "keyring-value"); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	if err := Remove("TEST_API_KEY"); err != nil {
		t.Fatalf("Remove() error = %v", err)
	}
	if _, err := Lookup("TEST_API_KEY"); err == nil {
		t.Fatalf("Lookup() error = nil, want missing credential error")
	}
}

func TestSetFromInputUsesProvidedValue(t *testing.T) {
	go_keyringMockInit(t)
	var stdout bytes.Buffer

	if err := SetFromInput(strings.NewReader(""), &stdout, "TEST_API_KEY", "secret"); err != nil {
		t.Fatalf("SetFromInput() error = %v", err)
	}
	got, err := Lookup("TEST_API_KEY")
	if err != nil {
		t.Fatalf("Lookup() error = %v", err)
	}
	if got.Value != "secret" || got.Source != SourceKeyring {
		t.Fatalf("Lookup() = %#v, want keyring secret", got)
	}
	if !strings.Contains(stdout.String(), "Stored credential") {
		t.Fatalf("stdout = %q, want stored message", stdout.String())
	}
}

func TestSetFromInputReadsStdin(t *testing.T) {
	go_keyringMockInit(t)

	if err := SetFromInput(strings.NewReader("secret-from-stdin\n"), io.Discard, "TEST_API_KEY", ""); err != nil {
		t.Fatalf("SetFromInput() error = %v", err)
	}
	got, err := Lookup("TEST_API_KEY")
	if err != nil {
		t.Fatalf("Lookup() error = %v", err)
	}
	if got.Value != "secret-from-stdin" || got.Source != SourceKeyring {
		t.Fatalf("Lookup() = %#v, want keyring stdin secret", got)
	}
}

func TestRemoveAndReport(t *testing.T) {
	go_keyringMockInit(t)
	if err := Set("TEST_API_KEY", "keyring-value"); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	var stdout bytes.Buffer

	if err := RemoveAndReport(&stdout, "TEST_API_KEY"); err != nil {
		t.Fatalf("RemoveAndReport() error = %v", err)
	}
	if _, err := Lookup("TEST_API_KEY"); err == nil {
		t.Fatalf("Lookup() error = nil, want missing credential error")
	}
	if !strings.Contains(stdout.String(), "Removed credential") {
		t.Fatalf("stdout = %q, want removed message", stdout.String())
	}
}

func go_keyringMockInit(t *testing.T) {
	t.Helper()
	keyring.MockInit()
}
