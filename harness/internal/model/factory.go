// This file owns provider adapter registration and model construction.
package model

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	"agentawesome/internal/model/adapters/anthropic"
	"agentawesome/internal/model/adapters/google"
	"agentawesome/internal/model/adapters/openai"
	"agentawesome/internal/secrets"
	llmapi "google.golang.org/adk/model"
)

// This file owns provider adapter registration and model construction.

var (
	_ adapter.ProviderFactory = anthropic.NewFactory(nil, nil)
	_ adapter.ProviderFactory = google.NewFactory(nil)
	_ adapter.ProviderFactory = openai.NewFactory(nil, nil)
)

// Factory owns registered provider adapters and shared adapter dependencies.
type Factory struct {
	providers   map[string]adapter.ProviderFactory
	credentials adapter.CredentialResolver
	httpClients adapter.HTTPClientFactory
}

// NewFactory builds a provider factory with all built-in adapters registered.
func NewFactory() *Factory {
	return NewFactoryWithDependencies(secretCredentialResolver{}, defaultHTTPClientFactory{})
}

// NewFactoryWithDependencies builds a provider factory using injectable
// infrastructure dependencies for provider adapters.
func NewFactoryWithDependencies(credentials adapter.CredentialResolver, httpClients adapter.HTTPClientFactory) *Factory {
	if credentials == nil {
		credentials = secretCredentialResolver{}
	}
	if httpClients == nil {
		httpClients = defaultHTTPClientFactory{}
	}
	factory := &Factory{
		providers:   make(map[string]adapter.ProviderFactory),
		credentials: credentials,
		httpClients: httpClients,
	}
	factory.Register("anthropic", anthropic.NewFactory(credentials, httpClients))
	factory.Register("google", google.NewFactory(credentials))
	factory.Register("openai", openai.NewFactory(credentials, httpClients))
	return factory
}

// Register associates an adapter name with a provider implementation.
func (f *Factory) Register(adapterName string, provider adapter.ProviderFactory) {
	f.providers[normalizeAdapter(adapterName)] = provider
}

// Create selects the configured adapter and creates the corresponding runtime
// LLM implementation.
func (f *Factory) Create(ctx context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	adapter := normalizeAdapter(selection.Adapter())
	provider, ok := f.providers[adapter]
	if !ok {
		return nil, fmt.Errorf("provider %q model id %q uses unsupported adapter %q", selection.Name, selection.Model.ID, selection.Adapter())
	}
	return provider.Create(ctx, selection)
}

// ValidateConfig applies adapter-specific validation for all configured
// providers. Generic YAML and model-selection validation stays in schema.
func (f *Factory) ValidateConfig(cfg *schema.ModelConfig) error {
	if cfg == nil {
		return fmt.Errorf("config is nil")
	}
	for name, provider := range cfg.Providers {
		adapter := normalizeAdapter(provider.Adapter)
		registered, ok := f.providers[adapter]
		if !ok {
			return fmt.Errorf("provider %q uses unsupported adapter %q", name, provider.Adapter)
		}
		if err := registered.ValidateProvider(name, provider); err != nil {
			return err
		}
	}
	return nil
}

// normalizeAdapter makes adapter matching case- and whitespace-insensitive.
func normalizeAdapter(adapter string) string {
	return strings.TrimSpace(strings.ToLower(adapter))
}

type secretCredentialResolver struct{}

// ResolveCredential resolves model provider credentials through internal
// secret lookup.
func (secretCredentialResolver) ResolveCredential(name string) (string, error) {
	secret, err := secrets.Lookup(name)
	if err != nil {
		return "", err
	}
	return secret.Value, nil
}

type defaultHTTPClientFactory struct{}

// NewHTTPClient returns the default provider HTTP client.
func (defaultHTTPClientFactory) NewHTTPClient() *http.Client {
	return defaultHTTPClient()
}
