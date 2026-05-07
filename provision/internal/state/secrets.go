package state

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"agentprovision/internal/configpath"
	"github.com/zalando/go-keyring"
)

const generatedTokenBytes = 32

// SecretStore stores generated internal tokens and operator credentials.
type SecretStore interface {
	EnsureGenerated(name string) (string, error)
	Lookup(name string) (string, error)
	Set(name string, value string) error
	Delete(name string) error
}

// KeyringSecretStore stores provisioning credentials in the OS keyring.
type KeyringSecretStore struct {
	service string
}

// DefaultSecretStore returns the production OS keyring credential store.
func DefaultSecretStore() KeyringSecretStore {
	return KeyringSecretStore{service: configpath.AppConfigDirName}
}

// NewKeyringSecretStore creates a keyring credential store.
func NewKeyringSecretStore(service string) KeyringSecretStore {
	return KeyringSecretStore{service: service}
}

// EnsureGenerated returns an existing token or creates and stores one.
func (s KeyringSecretStore) EnsureGenerated(name string) (string, error) {
	name, err := cleanCredentialName(name)
	if err != nil {
		return "", err
	}
	if value, err := s.Lookup(name); err == nil {
		return value, nil
	}
	value, err := randomToken()
	if err != nil {
		return "", err
	}
	if err := keyring.Set(s.serviceName(), name, value); err != nil {
		return "", fmt.Errorf("store generated credential %q: %w", name, err)
	}
	return value, nil
}

// Lookup reads one credential from the OS keyring.
func (s KeyringSecretStore) Lookup(name string) (string, error) {
	name, err := cleanCredentialName(name)
	if err != nil {
		return "", err
	}
	value, err := keyring.Get(s.serviceName(), name)
	if err != nil {
		return "", fmt.Errorf("read credential %q: %w", name, err)
	}
	if strings.TrimSpace(value) == "" {
		return "", fmt.Errorf("credential %q is empty", name)
	}
	return strings.TrimSpace(value), nil
}

// Set writes one operator-provided credential to the OS keyring.
func (s KeyringSecretStore) Set(name string, value string) error {
	name, err := cleanCredentialName(name)
	if err != nil {
		return err
	}
	value = strings.TrimSpace(value)
	if value == "" {
		return fmt.Errorf("credential %q value is required", name)
	}
	if err := keyring.Set(s.serviceName(), name, value); err != nil {
		return fmt.Errorf("store credential %q: %w", name, err)
	}
	return nil
}

// Delete removes one credential from the OS keyring.
func (s KeyringSecretStore) Delete(name string) error {
	name, err := cleanCredentialName(name)
	if err != nil {
		return err
	}
	if err := keyring.Delete(s.serviceName(), name); errors.Is(err, keyring.ErrNotFound) {
		return nil
	} else if err != nil {
		return fmt.Errorf("delete credential %q: %w", name, err)
	}
	return nil
}

// serviceName returns the keyring service name.
func (s KeyringSecretStore) serviceName() string {
	if strings.TrimSpace(s.service) == "" {
		return configpath.AppConfigDirName
	}
	return strings.TrimSpace(s.service)
}

// CredentialName returns the stable keyring credential name for one agent token.
func CredentialName(agentID string, tokenName string) string {
	return "provision/" + strings.TrimSpace(agentID) + "/" + strings.TrimSpace(tokenName)
}

// cleanCredentialName validates a keyring credential name.
func cleanCredentialName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", fmt.Errorf("credential name is required")
	}
	return name, nil
}

// randomToken returns a URL-safe generated secret token.
func randomToken() (string, error) {
	data := make([]byte, generatedTokenBytes)
	if _, err := rand.Read(data); err != nil {
		return "", fmt.Errorf("generate token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}
