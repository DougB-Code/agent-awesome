// This file tests application runtime option handling.
package app

import (
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
)

func TestValidateSelectedModelCapabilitiesRejectsUndeclaredStreaming(t *testing.T) {
	selection := schema.ProviderSelection{
		Name:  "cloudflare",
		Model: schema.Model{ID: "gemma"},
	}

	err := validateSelectedModelCapabilities([]string{"console", "-streaming_mode", "sse"}, selection)
	if err == nil {
		t.Fatalf("validateSelectedModelCapabilities() error = nil, want streaming capability error")
	}
	if !strings.Contains(err.Error(), "does not declare streaming support") {
		t.Fatalf("error = %q, want streaming capability message", err)
	}
}

func TestValidateSelectedModelCapabilitiesAllowsDeclaredStreaming(t *testing.T) {
	selection := schema.ProviderSelection{
		Name: "google",
		Model: schema.Model{
			ID: "gemini-flash",
			Capabilities: schema.ModelCapabilities{
				Streaming: true,
			},
		},
	}

	if err := validateSelectedModelCapabilities([]string{"console", "-streaming_mode", "sse"}, selection); err != nil {
		t.Fatalf("validateSelectedModelCapabilities() error = %v", err)
	}
}

func TestValidateSelectedModelCapabilitiesIgnoresOtherEntrypoints(t *testing.T) {
	selection := schema.ProviderSelection{
		Name:  "cloudflare",
		Model: schema.Model{ID: "gemma"},
	}

	if err := validateSelectedModelCapabilities([]string{"web", "--port", "8080"}, selection); err != nil {
		t.Fatalf("validateSelectedModelCapabilities() error = %v", err)
	}
}
