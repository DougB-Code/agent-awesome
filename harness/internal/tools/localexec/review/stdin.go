// This file summarizes stdin for local command review prompts.
package review

import (
	"fmt"
	"strings"
)

const stdinPreviewLimit = 4096

// StdinPreview describes stdin without forcing the UI to render unbounded input.
type StdinPreview struct {
	Bytes     int    `json:"bytes"`
	Preview   string `json:"preview"`
	Truncated bool   `json:"truncated"`
}

// NewStdinPreview creates a bounded stdin preview for approval payloads.
func NewStdinPreview(stdin string) *StdinPreview {
	if stdin == "" {
		return nil
	}
	preview := &StdinPreview{
		Bytes:   len(stdin),
		Preview: stdin,
	}
	if len(preview.Preview) > stdinPreviewLimit {
		preview.Preview = preview.Preview[:stdinPreviewLimit]
		preview.Truncated = true
	}
	return preview
}

// AppendStdinPromptSection adds a bounded stdin preview to a text prompt.
func AppendStdinPromptSection(b *strings.Builder, stdin string) {
	preview := NewStdinPreview(stdin)
	if preview == nil {
		return
	}
	b.WriteString("\n\nStdin")
	if preview.Truncated {
		fmt.Fprintf(b, " preview (%d bytes, truncated)", preview.Bytes)
	} else {
		fmt.Fprintf(b, " (%d bytes)", preview.Bytes)
	}
	b.WriteString(":\n")
	b.WriteString(indentBlock(preview.Preview))
	if preview.Truncated {
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
