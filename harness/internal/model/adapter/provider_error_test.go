// This file tests sanitized provider error diagnostics.
package adapter

import (
	"strings"
	"testing"
)

// TestProviderErrorDetailIncludesSafeProviderMessage verifies useful API errors survive.
func TestProviderErrorDetailIncludesSafeProviderMessage(t *testing.T) {
	detail := ProviderErrorDetail([]byte(`{"error":{"message":"The model is not available for this project.","type":"invalid_request_error","code":"model_not_found","param":"model"}}`))
	if !strings.Contains(detail, "The model is not available for this project.") {
		t.Fatalf("detail = %q, want provider message", detail)
	}
	if !strings.Contains(detail, "type=invalid_request_error") {
		t.Fatalf("detail = %q, want provider type", detail)
	}
	if !strings.Contains(detail, "code=model_not_found") {
		t.Fatalf("detail = %q, want provider code", detail)
	}
}

// TestProviderErrorDetailDropsSensitiveProviderMessage verifies secrets stay out.
func TestProviderErrorDetailDropsSensitiveProviderMessage(t *testing.T) {
	detail := ProviderErrorDetail([]byte(`{"error":{"message":"Incorrect API key provided: sk-test-secret.","type":"authentication_error","code":"invalid_api_key"}}`))
	if strings.Contains(detail, "sk-test-secret") || strings.Contains(strings.ToLower(detail), "api key") {
		t.Fatalf("detail leaked sensitive message: %q", detail)
	}
	if !strings.Contains(detail, "type=authentication_error") {
		t.Fatalf("detail = %q, want safe provider type", detail)
	}
}
