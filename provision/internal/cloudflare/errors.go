package cloudflare

import (
	"fmt"
	"strings"
)

const maxCommandOutputLength = 2000

// CommandFailureError stores an external command failure with safe diagnostics.
type CommandFailureError struct {
	Command string
	Output  string
	Err     error
}

// Error returns a concise operator-facing command failure.
func (e CommandFailureError) Error() string {
	var builder strings.Builder
	builder.WriteString(e.Command)
	builder.WriteString(" failed")
	if e.Err != nil {
		builder.WriteString(": ")
		builder.WriteString(e.Err.Error())
	}
	if diagnosis := diagnoseCommandOutput(e.Output); diagnosis != "" {
		builder.WriteString("\n")
		builder.WriteString(diagnosis)
	}
	if output := trimmedCommandOutput(e.Output); output != "" {
		builder.WriteString("\ncommand output:\n")
		builder.WriteString(output)
	}
	return builder.String()
}

// Unwrap returns the underlying command error.
func (e CommandFailureError) Unwrap() error {
	return e.Err
}

// commandFailure builds a command error without exposing stdin secret values.
func commandFailure(command Command, result CommandResult, err error) error {
	return CommandFailureError{
		Command: commandName(command),
		Output:  result.Output,
		Err:     err,
	}
}

// diagnoseCommandOutput returns known remediation guidance for command output.
func diagnoseCommandOutput(output string) string {
	lower := strings.ToLower(output)
	switch {
	case strings.Contains(lower, "requires at least node.js"):
		return "diagnosis: Wrangler requires a newer Node.js runtime. Install Node.js 22 or newer, then rerun the command."
	case strings.Contains(lower, "not logged in") || strings.Contains(lower, "not authenticated") || strings.Contains(lower, "authentication error"):
		return "diagnosis: Wrangler is not authenticated. Run `npx wrangler login` or configure a Cloudflare API token with the required permissions."
	case strings.Contains(lower, "permission") || strings.Contains(lower, "unauthorized") || strings.Contains(lower, "forbidden"):
		return "diagnosis: the Cloudflare credential is missing a required permission for this resource."
	case strings.Contains(lower, "not empty") || strings.Contains(lower, "must be empty"):
		return "diagnosis: the R2 bucket still contains objects. Remove the remaining user-memory objects, then rerun delete."
	default:
		return ""
	}
}

// trimmedCommandOutput returns bounded command output for actionable failures.
func trimmedCommandOutput(output string) string {
	output = strings.TrimSpace(output)
	if output == "" {
		return ""
	}
	if len(output) <= maxCommandOutputLength {
		return output
	}
	return fmt.Sprintf("...%s", output[len(output)-maxCommandOutputLength:])
}
