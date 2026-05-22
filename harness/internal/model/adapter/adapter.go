// This file defines shared model adapter contracts and helpers.
package adapter

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
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
	Detail     string
	StatusCode int
	Retryable  bool
}

// Error renders a provider error without exposing secrets.
func (e *ProviderError) Error() string {
	if e == nil {
		return ""
	}
	message := ""
	if e.Provider != "" && e.Model != "" {
		message = fmt.Sprintf("provider %q model %q request failed: %s", e.Provider, e.Model, e.Status)
	} else if e.Provider != "" {
		message = fmt.Sprintf("provider %q request failed: %s", e.Provider, e.Status)
	} else {
		message = fmt.Sprintf("model request failed: %s", e.Status)
	}
	if e.Detail != "" {
		message += ": " + e.Detail
	}
	return message
}

// NewProviderErrorWithDetail builds a provider error with safe diagnostic detail.
func NewProviderErrorWithDetail(provider, model string, statusCode int, status string, detail string) *ProviderError {
	return &ProviderError{
		Provider:   provider,
		Model:      model,
		Status:     status,
		Detail:     safeProviderErrorDetail(detail),
		StatusCode: statusCode,
		Retryable:  statusCode == 429 || statusCode >= 500,
	}
}

// ProviderErrorDetail extracts safe, bounded JSON provider diagnostics.
func ProviderErrorDetail(body []byte) string {
	var envelope struct {
		Error struct {
			Message string `json:"message"`
			Type    string `json:"type"`
			Code    string `json:"code"`
			Param   string `json:"param"`
		} `json:"error"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil {
		return ""
	}
	parts := make([]string, 0, 4)
	if detail := safeProviderErrorDetail(envelope.Error.Message); detail != "" {
		parts = append(parts, detail)
	}
	if detail := safeProviderErrorLabel("type", envelope.Error.Type); detail != "" {
		parts = append(parts, detail)
	}
	if detail := safeProviderErrorLabel("code", envelope.Error.Code); detail != "" {
		parts = append(parts, detail)
	}
	if detail := safeProviderErrorLabel("param", envelope.Error.Param); detail != "" {
		parts = append(parts, detail)
	}
	return strings.Join(parts, "; ")
}

// safeProviderErrorLabel formats one low-risk provider error field.
func safeProviderErrorLabel(name string, value string) string {
	value = safeProviderErrorDetail(value)
	if value == "" {
		return ""
	}
	return name + "=" + value
}

// safeProviderErrorDetail removes provider details that may contain credentials.
func safeProviderErrorDetail(value string) string {
	value = strings.TrimSpace(value)
	if value == "" || providerDetailLooksSensitive(value) {
		return ""
	}
	const maxProviderErrorDetailBytes = 500
	if len(value) > maxProviderErrorDetailBytes {
		return value[:maxProviderErrorDetailBytes] + "..."
	}
	return value
}

// providerDetailLooksSensitive reports whether a provider detail may leak a secret.
func providerDetailLooksSensitive(value string) bool {
	lower := strings.ToLower(value)
	for _, marker := range []string{
		"api key",
		"authorization",
		"bearer",
		"secret",
		"token",
		"sk-",
		"xox",
	} {
		if strings.Contains(lower, marker) {
			return true
		}
	}
	return false
}

// NewStreamingUnsupportedError explains that the selected provider cannot
// serve streaming model responses.
func NewStreamingUnsupportedError(provider string) error {
	if provider == "" {
		return fmt.Errorf("configured model provider does not support streaming responses; disable streaming or select a streaming-capable provider")
	}
	return fmt.Errorf("provider %q does not support streaming responses; disable streaming or select a streaming-capable provider", provider)
}

// ValidateNoStreamingModels rejects streaming capability declarations for
// adapters that only implement non-streaming completions.
func ValidateNoStreamingModels(providerName string, provider schema.Provider, adapterName string) error {
	if adapterName == "" {
		adapterName = "selected"
	}
	for _, model := range provider.Models {
		if model.Capabilities.Streaming {
			return fmt.Errorf("provider %q model %q declares capabilities.streaming, but the %s adapter does not support streaming; remove capabilities.streaming or choose a streaming-capable provider", providerName, model.ID, adapterName)
		}
	}
	return nil
}

// ResolveCredential resolves a named credential through the provided resolver.
func ResolveCredential(resolver CredentialResolver, name string) (string, error) {
	if resolver == nil {
		return "", fmt.Errorf("credential resolver is nil")
	}
	return resolver.ResolveCredential(name)
}

// NewDefaultHTTPClient returns a provider HTTP client with the standard timeout.
func NewDefaultHTTPClient() *http.Client {
	return &http.Client{Timeout: defaultHTTPTimeout}
}

// NewProviderHTTPClient returns an injected HTTP client or a default timed
// client.
func NewProviderHTTPClient(factory HTTPClientFactory) *http.Client {
	if factory == nil {
		return NewDefaultHTTPClient()
	}
	return factory.NewHTTPClient()
}
