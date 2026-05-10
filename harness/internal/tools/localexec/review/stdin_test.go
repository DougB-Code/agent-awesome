// This file tests shared stdin review payload and prompt rendering.
package review

import (
	"strings"
	"testing"
)

// TestNewStdinPreviewTruncatesLongInput verifies bounded stdin payloads.
func TestNewStdinPreviewTruncatesLongInput(t *testing.T) {
	stdin := strings.Repeat("a", stdinPreviewLimit+1)

	preview := NewStdinPreview(stdin)
	if preview == nil {
		t.Fatalf("NewStdinPreview() = nil, want preview")
	}
	if preview.Bytes != len(stdin) {
		t.Fatalf("Bytes = %d, want %d", preview.Bytes, len(stdin))
	}
	if len(preview.Preview) != stdinPreviewLimit {
		t.Fatalf("preview length = %d, want %d", len(preview.Preview), stdinPreviewLimit)
	}
	if !preview.Truncated {
		t.Fatalf("Truncated = false, want true")
	}
}

// TestAppendStdinPromptSectionRendersIndentedPreview verifies prompt output.
func TestAppendStdinPromptSectionRendersIndentedPreview(t *testing.T) {
	var b strings.Builder

	AppendStdinPromptSection(&b, "one\ntwo")

	got := b.String()
	if !strings.Contains(got, "Stdin (7 bytes)") {
		t.Fatalf("prompt = %q, want byte count", got)
	}
	if !strings.Contains(got, "  one\n  two") {
		t.Fatalf("prompt = %q, want indented preview", got)
	}
}
