// This file tests model factory registration and validation.
package model

import (
	"context"
	"iter"
	"testing"

	"agent-awesome.com/harnessinternal/config/schema"
	"agent-awesome.com/harnessinternal/model/adapter"
	llmapi "google.golang.org/adk/model"
)

type recordingFactory struct {
	called bool
}

func (f *recordingFactory) Create(context.Context, schema.ProviderSelection) (llmapi.LLM, error) {
	f.called = true
	return nilLLM{}, nil
}

func (f *recordingFactory) ValidateProvider(string, schema.Provider) error {
	return nil
}

func TestFactoryUsesProviderAdapter(t *testing.T) {
	provider := &recordingFactory{}
	factory := &Factory{providers: map[string]adapter.ProviderFactory{}}
	factory.Register("openai", provider)

	_, err := factory.Create(context.Background(), schema.ProviderSelection{
		Name:     "cloudflare-gateway",
		Provider: schema.Provider{Adapter: "openai"},
		Model:    schema.Model{ID: "model-alias", Model: "workers-ai/model"},
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	if !provider.called {
		t.Fatalf("registered provider factory was not called")
	}
}

func TestNewFactoryRegistersAnthropic(t *testing.T) {
	factory := NewFactory()
	if _, ok := factory.providers["anthropic"]; !ok {
		t.Fatalf("anthropic factory is not registered")
	}
}

func TestFactoryValidateConfigRejectsUnsupportedAdapter(t *testing.T) {
	cfg := &schema.ModelConfig{
		Providers: map[string]schema.Provider{
			"example": {
				Adapter: "imaginary",
				Models:  []schema.Model{{ID: "model", Model: "provider/model"}},
			},
		},
	}

	if err := NewFactory().ValidateConfig(cfg); err == nil {
		t.Fatalf("ValidateConfig() error = nil, want unsupported adapter error")
	}
}

func TestFactoryValidateConfigUsesProviderValidation(t *testing.T) {
	cfg := &schema.ModelConfig{
		Providers: map[string]schema.Provider{
			"anthropic": {
				Adapter: "anthropic",
				URL:     "https://api.anthropic.com/v1/messages",
				Models:  []schema.Model{{ID: "test", Model: "claude-test"}},
			},
		},
	}

	if err := NewFactory().ValidateConfig(cfg); err == nil {
		t.Fatalf("ValidateConfig() error = nil, want provider validation error")
	}
}

type nilLLM struct{}

func (nilLLM) Name() string { return "" }

func (nilLLM) GenerateContent(context.Context, *llmapi.LLMRequest, bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {}
}
