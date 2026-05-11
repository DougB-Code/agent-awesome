// Package main validates and reads provisioning credentials.
package main

import (
	"fmt"
	"io"
	"os"
	"strings"

	"agentprovision/internal/state"
	"golang.org/x/term"
)

// credentialEnvironment resolves apply-time secrets from keyring then environment.
type credentialEnvironment struct {
	store state.KeyringSecretStore
}

// Lookup returns one external credential needed by a deployment.
func (e credentialEnvironment) Lookup(name string) (string, error) {
	if value, err := e.store.Lookup(name); err == nil {
		return value, nil
	}
	value := strings.TrimSpace(os.Getenv(name))
	if value != "" {
		return value, nil
	}
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", fmt.Errorf("credential %s is required; set it with `agent-awesome-provision credentials set %s` or export %s", name, name, name)
	}
	value, err := readHiddenCredential(os.Stdin, os.Stderr, name)
	if err != nil {
		return "", err
	}
	if err := e.store.Set(name, value); err != nil {
		return "", err
	}
	return value, nil
}

// externalCredentialName validates a user-managed provider credential name.
func externalCredentialName(name string) (string, error) {
	name = strings.ToUpper(strings.TrimSpace(name))
	if name == "" {
		return "", fmt.Errorf("credential name is required")
	}
	if name == "AGENTAWESOME_GATEWAY_TOKEN" || name == "AGENTAWESOME_PERSISTENCE_TOKEN" {
		return "", fmt.Errorf("%s is generated per agent by cloudflare apply", name)
	}
	for _, current := range name {
		if (current >= 'A' && current <= 'Z') || (current >= '0' && current <= '9') || current == '_' {
			continue
		}
		return "", fmt.Errorf("credential name %q must use uppercase letters, numbers, and underscores", name)
	}
	return name, nil
}

// readCredentialValue reads one secret value from a flag, terminal line, or pipe.
func readCredentialValue(explicit string, input *os.File, output io.Writer, name string) (string, error) {
	if strings.TrimSpace(explicit) != "" {
		return strings.TrimSpace(explicit), nil
	}
	if term.IsTerminal(int(input.Fd())) {
		return readHiddenCredential(input, output, name)
	}
	data, err := io.ReadAll(input)
	if err != nil {
		return "", fmt.Errorf("read credential: %w", err)
	}
	return nonEmptyCredentialValue(name, string(data))
}

// readHiddenCredential reads one secret from a terminal without echoing it.
func readHiddenCredential(input *os.File, output io.Writer, name string) (string, error) {
	fmt.Fprintf(output, "Enter %s: ", name)
	data, err := term.ReadPassword(int(input.Fd()))
	fmt.Fprintln(output)
	if err != nil {
		return "", fmt.Errorf("read credential: %w", err)
	}
	return nonEmptyCredentialValue(name, string(data))
}

// nonEmptyCredentialValue trims and validates one secret value.
func nonEmptyCredentialValue(name string, value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", fmt.Errorf("credential %s value is required", name)
	}
	return value, nil
}
