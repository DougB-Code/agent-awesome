// This file tests model capability validation.
package model

import (
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
)

func TestValidateRequestedCapabilitiesRejectsUndeclaredStreaming(t *testing.T) {
	err := ValidateRequestedCapabilities(schema.ModelCapabilities{Streaming: true}, schema.ProviderSelection{
		Name:  "cloudflare",
		Model: schema.Model{ID: "gemma"},
	})
	if err == nil {
		t.Fatalf("ValidateRequestedCapabilities() error = nil, want streaming capability error")
	}
	if !strings.Contains(err.Error(), "does not declare streaming support") {
		t.Fatalf("error = %q, want streaming capability message", err)
	}
}

func TestValidateRequestedCapabilitiesAllowsDeclaredStreaming(t *testing.T) {
	err := ValidateRequestedCapabilities(schema.ModelCapabilities{Streaming: true}, schema.ProviderSelection{
		Name: "google",
		Model: schema.Model{
			ID: "gemini-flash",
			Capabilities: schema.ModelCapabilities{
				Streaming: true,
			},
		},
	})
	if err != nil {
		t.Fatalf("ValidateRequestedCapabilities() error = %v", err)
	}
}
