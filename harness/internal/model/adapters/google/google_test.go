// This file tests Google adapter configuration.
package google

import (
	"testing"

	"agentawesome/internal/config/schema"
)

func TestClientConfigUsesCredentialResolver(t *testing.T) {
	clientConfig, err := googleClientConfig("google", schema.Provider{
		Adapter:   "google",
		APIKeyEnv: "GOOGLE_TEST_API_KEY",
	}, staticCredentialResolver{"GOOGLE_TEST_API_KEY": "test-key"})
	if err != nil {
		t.Fatalf("googleClientConfig() error = %v", err)
	}
	if clientConfig.APIKey != "test-key" {
		t.Fatalf("APIKey = %q, want injected credential", clientConfig.APIKey)
	}
}

func TestFactoryValidateProviderRejectsURL(t *testing.T) {
	err := Factory{}.ValidateProvider("google", schema.Provider{
		Adapter: "google",
		URL:     "https://example.test/v1/models",
		Models:  []schema.Model{{ID: "test", Model: "gemini-test"}},
	})
	if err == nil {
		t.Fatalf("ValidateProvider() error = nil, want unsupported url error")
	}
}

// TestFactoryValidateProviderRequiresAPIKeyForRequiredAuth verifies explicit Google auth.
func TestFactoryValidateProviderRequiresAPIKeyForRequiredAuth(t *testing.T) {
	err := Factory{}.ValidateProvider("google", schema.Provider{
		Adapter: "google",
		Auth:    schema.ProviderAuthRequired,
		Models:  []schema.Model{{ID: "test", Model: "gemini-test"}},
	})
	if err == nil {
		t.Fatalf("ValidateProvider() error = nil, want required auth error")
	}
}

type staticCredentialResolver map[string]string

func (r staticCredentialResolver) ResolveCredential(name string) (string, error) {
	return r[name], nil
}
