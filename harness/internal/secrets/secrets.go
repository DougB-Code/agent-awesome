// This file resolves and stores provider credentials.
package secrets

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"agentawesome/internal/config/schema"
	"github.com/zalando/go-keyring"
)

// SourceKeyring means the value came from the OS keyring.
const SourceKeyring = "keyring"

// SourceEnv means the value came from an environment variable.
const SourceEnv = "env"

// Secret is a resolved credential value along with the place it came from.
type Secret struct {
	Value  string
	Source string
}

// ServiceName returns the OS keyring service name used by Agent Awesome.
func ServiceName() string {
	return schema.AppConfigDirName
}

// Lookup resolves a credential by name. Keyring values win over environment
// variables so local installs can avoid exporting long-lived secrets in shells.
func Lookup(name string) (Secret, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Secret{}, fmt.Errorf("credential name is required")
	}

	value, keyringErr := keyring.Get(ServiceName(), name)
	if keyringErr == nil && strings.TrimSpace(value) != "" {
		return Secret{Value: strings.TrimSpace(value), Source: SourceKeyring}, nil
	}
	if keyringErr != nil && errors.Is(keyringErr, keyring.ErrNotFound) {
		keyringErr = nil
	}

	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return Secret{Value: value, Source: SourceEnv}, nil
	}

	if keyringErr != nil {
		return Secret{}, fmt.Errorf("credential %q not found in keyring or environment variable %q; keyring lookup failed: %w", name, name, keyringErr)
	}
	return Secret{}, fmt.Errorf("credential %q not found in keyring or environment variable %q", name, name)
}

// Set stores a non-empty credential in the OS keyring.
func Set(name, value string) error {
	name = strings.TrimSpace(name)
	value = strings.TrimSpace(value)
	if name == "" {
		return fmt.Errorf("credential name is required")
	}
	if value == "" {
		return fmt.Errorf("credential value is required")
	}
	if err := keyring.Set(ServiceName(), name, value); err != nil {
		return fmt.Errorf("store credential %q in keyring: %w", name, err)
	}
	return nil
}

// Remove deletes a credential from the OS keyring. Missing credentials are not
// treated as errors so repeated cleanup commands remain idempotent.
func Remove(name string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return fmt.Errorf("credential name is required")
	}
	err := keyring.Delete(ServiceName(), name)
	if err != nil && !errors.Is(err, keyring.ErrNotFound) {
		return fmt.Errorf("remove credential %q from keyring: %w", name, err)
	}
	return nil
}
