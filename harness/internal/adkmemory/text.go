// This file sanitizes ADK chat text before storage or memory search.
package adkmemory

import (
	"strings"

	"google.golang.org/genai"
)

// contentText extracts sanitized text from all textual content parts.
func contentText(content *genai.Content) string {
	if content == nil {
		return ""
	}
	parts := make([]string, 0, len(content.Parts))
	for _, part := range content.Parts {
		if part == nil || strings.TrimSpace(part.Text) == "" {
			continue
		}
		text := cleanSessionText(part.Text)
		if text != "" {
			parts = append(parts, text)
		}
	}
	return strings.Join(parts, "\n\n")
}

// cleanSessionText removes harness-only control blocks from user-visible text.
func cleanSessionText(text string) string {
	text = strings.TrimSpace(text)
	for {
		switch {
		case text == "":
			return ""
		case strings.HasPrefix(text, "[[AURORA_HIDDEN_RUNTIME_MESSAGE]]"):
			return ""
		case strings.HasPrefix(text, "[[AURORA_RUNTIME_POLICY:"):
			text = trimLeadingControlBlock(text)
		case strings.HasPrefix(text, "[[AURORA_SESSION_CONTEXT:"):
			text = trimLeadingControlBlock(text)
		default:
			return strings.TrimSpace(text)
		}
	}
}

// trimLeadingControlBlock removes one leading double-bracket control block.
func trimLeadingControlBlock(text string) string {
	end := strings.Index(text, "]]")
	if end < 0 {
		return ""
	}
	return strings.TrimSpace(text[end+len("]]"):])
}
