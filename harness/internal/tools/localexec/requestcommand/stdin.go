// This file summarizes request_command stdin for review.
package requestcommand

import (
	"fmt"
	"strings"
)

const stdinPreviewLimit = 4096

// StdinReview describes stdin without forcing the UI to render unbounded input.
type StdinReview struct {
	Bytes     int    `json:"bytes"`
	Preview   string `json:"preview"`
	Truncated bool   `json:"truncated"`
}

// newStdinReview creates a bounded stdin preview for approval prompts.
func newStdinReview(stdin string) *StdinReview {
	if stdin == "" {
		return nil
	}
	review := &StdinReview{
		Bytes:   len(stdin),
		Preview: stdin,
	}
	if len(review.Preview) > stdinPreviewLimit {
		review.Preview = review.Preview[:stdinPreviewLimit]
		review.Truncated = true
	}
	return review
}

// appendStdinReview adds a bounded stdin preview to a human-readable prompt.
func appendStdinReview(b *strings.Builder, stdin string) {
	review := newStdinReview(stdin)
	if review == nil {
		return
	}
	b.WriteString("\n\nStdin")
	if review.Truncated {
		fmt.Fprintf(b, " preview (%d bytes, truncated)", review.Bytes)
	} else {
		fmt.Fprintf(b, " (%d bytes)", review.Bytes)
	}
	b.WriteString(":\n")
	b.WriteString(indentBlock(review.Preview))
	if review.Truncated {
		b.WriteString("\n  ... truncated ...")
	}
}

// indentBlock indents each line of a multi-line prompt section.
func indentBlock(value string) string {
	lines := strings.Split(value, "\n")
	for i, line := range lines {
		lines[i] = "  " + line
	}
	return strings.Join(lines, "\n")
}
