// This file adapts Agent Awesome provider config to Gemini models.
package google

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/adk/model/gemini"
	"google.golang.org/genai"
)

// Factory creates Google-backed runtime models.
type Factory struct {
	credentials adapter.CredentialResolver
}

// NewFactory creates a Google provider factory with shared credential
// resolution.
func NewFactory(credentials adapter.CredentialResolver) Factory {
	return Factory{credentials: credentials}
}

// Create builds a Gemini-backed runtime LLM for the selected provider/model.
func (f Factory) Create(ctx context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	clientConfig, err := googleClientConfig(selection.Name, selection.Provider, f.credentials)
	if err != nil {
		return nil, err
	}
	return gemini.NewModel(ctx, selection.ModelName(), clientConfig)
}

// ValidateProvider checks Google provider-specific schema. The Gemini adapter
// does not consume provider URLs; endpoint selection is handled by genai, while
// credentials are optional and may come from api-key or genai-supported defaults.
func (Factory) ValidateProvider(name string, provider schema.Provider) error {
	if strings.TrimSpace(provider.URL) != "" {
		return fmt.Errorf("provider %q does not support url", name)
	}
	return nil
}

// googleClientConfig resolves the optional configured API key and builds the
// Gemini client schema.
func googleClientConfig(providerName string, provider schema.Provider, credentials adapter.CredentialResolver) (*genai.ClientConfig, error) {
	clientConfig := &genai.ClientConfig{Backend: genai.BackendGeminiAPI}
	if apiKeyEnv := strings.TrimSpace(provider.APIKeyEnv); apiKeyEnv != "" {
		apiKey, err := adapter.ResolveCredential(credentials, apiKeyEnv)
		if err != nil {
			return nil, fmt.Errorf("provider %q API key %q: %w", providerName, apiKeyEnv, err)
		}
		clientConfig.APIKey = apiKey
	}
	return clientConfig, nil
}
