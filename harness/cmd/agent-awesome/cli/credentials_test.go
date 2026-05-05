package cli

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

type fakeCredentialStore struct {
	setName    string
	setValue   string
	removeName string
}

func (s *fakeCredentialStore) SetFromInput(stdin io.Reader, stdout io.Writer, name, value string) error {
	s.setName = name
	s.setValue = value
	_, _ = io.WriteString(stdout, "Stored credential\n")
	return nil
}

func (s *fakeCredentialStore) Remove(stdout io.Writer, name string) error {
	s.removeName = name
	return nil
}

func TestCredentialsCommandSetUsesValueFlag(t *testing.T) {
	store := &fakeCredentialStore{}
	var stdout bytes.Buffer
	cmd := newCredentialsCommandWithActions(store, strings.NewReader(""), &stdout)
	cmd.SetArgs([]string{"set", "OPENAI_API_KEY", "--value", "secret"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if store.setName != "OPENAI_API_KEY" || store.setValue != "secret" {
		t.Fatalf("stored (%q, %q), want OPENAI_API_KEY secret", store.setName, store.setValue)
	}
	if !strings.Contains(stdout.String(), "Stored credential") {
		t.Fatalf("stdout = %q, want stored message", stdout.String())
	}
}

func TestCredentialsCommandRemove(t *testing.T) {
	store := &fakeCredentialStore{}
	cmd := newCredentialsCommandWithActions(store, strings.NewReader(""), io.Discard)
	cmd.SetArgs([]string{"remove", "OPENAI_API_KEY"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if store.removeName != "OPENAI_API_KEY" {
		t.Fatalf("removeName = %q, want OPENAI_API_KEY", store.removeName)
	}
}
