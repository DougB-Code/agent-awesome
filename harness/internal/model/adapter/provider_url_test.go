// This file tests provider endpoint template resolution.
package adapter

import (
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
)

func TestResolveProviderURLExpandsEnvironment(t *testing.T) {
	provider := schema.Provider{URL: "${TEST_GATEWAY_URL}"}
	got, err := ResolveProviderURL(provider, staticEnvLookup(map[string]string{
		"TEST_GATEWAY_URL": "https://gateway.example.test/v1/chat/completions",
	}))
	if err != nil {
		t.Fatalf("ResolveProviderURL() error = %v", err)
	}
	if want := "https://gateway.example.test/v1/chat/completions"; got != want {
		t.Fatalf("ResolveProviderURL() = %q, want %q", got, want)
	}
}

func TestResolveProviderURLRejectsMissingEnvironment(t *testing.T) {
	provider := schema.Provider{URL: "${TEST_MISSING_GATEWAY_URL}"}
	_, err := ResolveProviderURL(provider, staticEnvLookup(nil))
	if err == nil {
		t.Fatalf("ResolveProviderURL() error = nil, want missing environment error")
	}
	if !strings.Contains(err.Error(), "TEST_MISSING_GATEWAY_URL") {
		t.Fatalf("ResolveProviderURL() error = %v, want missing variable name", err)
	}
}

// staticEnvLookup adapts a map into an EnvLookup for tests.
func staticEnvLookup(values map[string]string) EnvLookup {
	return func(name string) (string, bool) {
		value, ok := values[name]
		return value, ok
	}
}
