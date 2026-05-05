// This file defines shared model adapter contracts and helpers.
package adapter

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"agentawesome/internal/config/schema"
	llmapi "google.golang.org/adk/model"
)

const defaultHTTPTimeout = 60 * time.Second

// ProviderFactory validates and creates one Agent Awesome model implementation
// from provider schema.
type ProviderFactory interface {
	Create(context.Context, schema.ProviderSelection) (llmapi.LLM, error)
	ValidateProvider(name string, provider schema.Provider) error
}

// CredentialResolver resolves provider credential names into secret values.
type CredentialResolver interface {
	ResolveCredential(name string) (string, error)
}

// HTTPClientFactory creates HTTP clients for provider adapters.
type HTTPClientFactory interface {
	NewHTTPClient() *http.Client
}

// ProviderError describes a sanitized provider HTTP failure.
type ProviderError struct {
	Provider   string
	Model      string
	Status     string
	StatusCode int
	Retryable  bool
}

// Error renders a provider error without exposing response bodies or secrets.
func (e *ProviderError) Error() string {
	if e == nil {
		return ""
	}
	if e.Provider != "" && e.Model != "" {
		return fmt.Sprintf("provider %q model %q request failed: %s", e.Provider, e.Model, e.Status)
	}
	if e.Provider != "" {
		return fmt.Sprintf("provider %q request failed: %s", e.Provider, e.Status)
	}
	return fmt.Sprintf("model request failed: %s", e.Status)
}

// NewProviderError builds a provider error and marks retryable status codes.
func NewProviderError(provider, model string, statusCode int, status string) *ProviderError {
	return &ProviderError{
		Provider:   provider,
		Model:      model,
		Status:     status,
		StatusCode: statusCode,
		Retryable:  statusCode == 429 || statusCode >= 500,
	}
}

// ResolveCredential resolves a named credential through the provided resolver.
func ResolveCredential(resolver CredentialResolver, name string) (string, error) {
	if resolver == nil {
		return "", fmt.Errorf("credential resolver is nil")
	}
	return resolver.ResolveCredential(name)
}

// NewProviderHTTPClient returns an injected HTTP client or a default timed
// client.
func NewProviderHTTPClient(factory HTTPClientFactory) *http.Client {
	if factory == nil {
		return &http.Client{Timeout: defaultHTTPTimeout}
	}
	return factory.NewHTTPClient()
}
