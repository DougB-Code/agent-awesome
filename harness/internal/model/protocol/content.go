// This file converts runtime content into provider-friendly text and roles.
package protocol

import (
	"fmt"
	"strings"

	"google.golang.org/genai"
)

// This file contains shared content conversion helpers used by provider
// adapters.

// ContentText joins supported text parts and rejects part types the current
// provider adapters do not know how to serialize.
// @TODO This is silently dropping parts, which will be a hard to find bug.
func ContentText(content *genai.Content) (string, error) {
	if content == nil {
		return "", nil
	}

	parts := make([]string, 0, len(content.Parts))
	for i, part := range content.Parts {
		if part == nil {
			continue
		}
		if unsupported := UnsupportedPartTypes(part); len(unsupported) > 0 {
			return "", fmt.Errorf("unsupported content part at index %d: %s", i, strings.Join(unsupported, ", "))
		}
		if part.Text != "" {
			parts = append(parts, part.Text)
		}
	}
	return strings.Join(parts, "\n"), nil
}

// UnsupportedPartTypes names non-text/function content fields that should fail
// fast instead of being silently dropped.
func UnsupportedPartTypes(part *genai.Part) []string {
	var unsupported []string
	if part.MediaResolution != nil {
		unsupported = append(unsupported, "media resolution")
	}
	if part.CodeExecutionResult != nil {
		unsupported = append(unsupported, "code execution result")
	}
	if part.ExecutableCode != nil {
		unsupported = append(unsupported, "executable code")
	}
	if part.FileData != nil {
		unsupported = append(unsupported, "file data")
	}
	if part.InlineData != nil {
		unsupported = append(unsupported, "inline data")
	}
	if part.VideoMetadata != nil {
		unsupported = append(unsupported, "video metadata")
	}
	if part.ToolCall != nil {
		unsupported = append(unsupported, "tool call")
	}
	if part.ToolResponse != nil {
		unsupported = append(unsupported, "tool response")
	}
	return unsupported
}
