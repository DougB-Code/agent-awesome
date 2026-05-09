// This file sanitizes ADK chat text before storage or memory search.
package adkmemory

import (
	"strings"

	"google.golang.org/genai"
)

var runtimeHiddenPrefixes = []string{
	"[[AGENT_AWESOME_HIDDEN_RUNTIME_MESSAGE]]",
}

var runtimeControlPrefixes = []string{
	"[[AGENT_AWESOME_RUNTIME_POLICY:",
	"[[AGENT_AWESOME_SESSION_CONTEXT:",
}

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
		case hasAnyPrefix(text, runtimeHiddenPrefixes):
			return ""
		case hasAnyPrefix(text, runtimeControlPrefixes):
			text = trimLeadingControlBlock(text)
		default:
			return strings.TrimSpace(text)
		}
	}
}

// hasAnyPrefix reports whether text starts with one of the given prefixes.
func hasAnyPrefix(text string, prefixes []string) bool {
	for _, prefix := range prefixes {
		if strings.HasPrefix(text, prefix) {
			return true
		}
	}
	return false
}

// trimLeadingControlBlock removes one leading double-bracket control block.
func trimLeadingControlBlock(text string) string {
	end := strings.Index(text, "]]")
	if end < 0 {
		return ""
	}
	return strings.TrimSpace(text[end+len("]]"):])
}
