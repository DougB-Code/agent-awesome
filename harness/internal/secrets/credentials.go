// This file handles interactive credential storage and removal flows.
package secrets

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"golang.org/x/term"
)

// SetFromInput stores a named credential. The value parameter supports
// automation; when it is blank the value is read from stdin.
func SetFromInput(stdin io.Reader, stdout io.Writer, name, value string) error {
	name = strings.TrimSpace(name)
	secret := value
	if strings.TrimSpace(secret) == "" {
		var err error
		secret, err = readSecret(stdin, stdout, name)
		if err != nil {
			return err
		}
	}
	if err := Set(name, secret); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Stored credential %q in the OS keyring.\n", name)
	return nil
}

// RemoveAndReport deletes a named credential and reports success to stdout.
func RemoveAndReport(stdout io.Writer, name string) error {
	name = strings.TrimSpace(name)
	if err := Remove(name); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Removed credential %q from the OS keyring.\n", name)
	return nil
}

// readSecret reads a credential value either as a hidden terminal prompt or as
// one line from non-interactive stdin.
func readSecret(stdin io.Reader, stdout io.Writer, name string) (string, error) {
	// Terminal input can hide the value as the user types. Piped input cannot, so
	// automation reads the first line instead.
	if file, ok := stdin.(*os.File); ok && term.IsTerminal(int(file.Fd())) {
		fmt.Fprintf(stdout, "Credential %s: ", name)
		password, err := term.ReadPassword(int(file.Fd()))
		fmt.Fprintln(stdout)
		if err != nil {
			return "", fmt.Errorf("read credential: %w", err)
		}
		return strings.TrimSpace(string(password)), nil
	}

	line, err := bufio.NewReader(stdin).ReadString('\n')
	if err != nil && err != io.EOF {
		return "", fmt.Errorf("read credential from stdin: %w", err)
	}
	return strings.TrimSpace(line), nil
}
