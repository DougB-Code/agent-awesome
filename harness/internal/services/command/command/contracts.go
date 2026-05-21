// This file defines structured CLI contract data exposed by command templates.
package command

import "strings"

const (
	outputSourceStdout   = "stdout"
	outputSourceStderr   = "stderr"
	outputSourceCombined = "combined"
	outputFormatJSON     = "json"
	outputFormatText     = "text"
	outputFormatPlain    = "plain"
)

// OutputContract declares the shape a CLI promises for completed output.
type OutputContract struct {
	Format string `json:"format,omitempty"`
	Source string `json:"source,omitempty"`
}

// Diagnostic describes parser or validation information from a completed command.
type Diagnostic struct {
	Severity string `json:"severity,omitempty"`
	Message  string `json:"message"`
}

// Artifact describes one file emitted by a command.
type Artifact struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
}

// ValidationResult reports whether parsed command output satisfied a schema.
type ValidationResult struct {
	Checked bool     `json:"checked"`
	Valid   bool     `json:"valid"`
	Errors  []string `json:"errors,omitempty"`
}

// normalizeOutputFormat returns a stable lower-case output format name.
func normalizeOutputFormat(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

// normalizeOutputSource returns the configured output stream with a stdout default.
func normalizeOutputSource(source string, contract OutputContract) string {
	trimmed := strings.ToLower(strings.TrimSpace(source))
	if trimmed == "" {
		trimmed = strings.ToLower(strings.TrimSpace(contract.Source))
	}
	switch trimmed {
	case outputSourceStderr, outputSourceCombined:
		return trimmed
	default:
		return outputSourceStdout
	}
}
