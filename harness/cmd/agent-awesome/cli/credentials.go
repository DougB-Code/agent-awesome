package cli

import (
	"io"
	"os"

	"agent-awesome.com/harnessinternal/secrets"
	"github.com/spf13/cobra"
)

// NewCredentialsCommand creates the top-level credentials command using real
// process stdio and the OS keyring.
func NewCredentialsCommand() *cobra.Command {
	return newCredentialsCommandWithActions(secretActions{}, os.Stdin, os.Stdout)
}

// credentialActions describes the internal credential behavior used by Cobra
// handlers.
type credentialActions interface {
	SetFromInput(stdin io.Reader, stdout io.Writer, name, value string) error
	Remove(stdout io.Writer, name string) error
}

// secretActions adapts the internal secrets package to credentialActions.
type secretActions struct{}

// SetFromInput delegates credential storage to the internal secrets package.
func (secretActions) SetFromInput(stdin io.Reader, stdout io.Writer, name, value string) error {
	return secrets.SetFromInput(stdin, stdout, name, value)
}

// Remove delegates credential removal to the internal secrets package.
func (secretActions) Remove(stdout io.Writer, name string) error {
	return secrets.RemoveAndReport(stdout, name)
}

// newCredentialsCommandWithActions creates a credentials command with
// injectable actions so command tests avoid touching the real keyring.
func newCredentialsCommandWithActions(actions credentialActions, stdin io.Reader, stdout io.Writer) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "credentials",
		Short: "Manage provider credentials in the OS keyring",
	}
	cmd.AddCommand(newCredentialsSetCommand(actions, stdin, stdout))
	cmd.AddCommand(newCredentialsRemoveCommand(actions, stdout))
	return cmd
}

// newCredentialsSetCommand creates the subcommand that stores a credential.
func newCredentialsSetCommand(actions credentialActions, stdin io.Reader, stdout io.Writer) *cobra.Command {
	var value string
	cmd := &cobra.Command{
		Use:   "set NAME",
		Short: "Store a provider credential in the OS keyring",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return actions.SetFromInput(stdin, stdout, args[0], value)
		},
	}
	cmd.Flags().StringVar(&value, "value", "", "credential value; if omitted, prompts securely when possible")
	return cmd
}

// newCredentialsRemoveCommand creates the subcommand that removes a credential.
func newCredentialsRemoveCommand(actions credentialActions, stdout io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:     "remove NAME",
		Aliases: []string{"rm", "delete"},
		Short:   "Remove a provider credential from the OS keyring",
		Args:    cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return actions.Remove(stdout, args[0])
		},
	}
}
