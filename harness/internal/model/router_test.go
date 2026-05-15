// This file tests per-request model routing across configured providers.
package model

import (
	"context"
	"fmt"
	"iter"
	"testing"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	llmapi "google.golang.org/adk/model"
)

type routerRecordingFactory struct {
	llms    map[string]*routerRecordingLLM
	creates map[string]int
}

// Create records one created provider/model client for router assertions.
func (f *routerRecordingFactory) Create(_ context.Context, selection schema.ProviderSelection) (llmapi.LLM, error) {
	if f.llms == nil {
		f.llms = make(map[string]*routerRecordingLLM)
	}
	if f.creates == nil {
		f.creates = make(map[string]int)
	}
	llm := &routerRecordingLLM{name: selection.ModelName()}
	ref := ModelRef(selection)
	f.creates[ref]++
	f.llms[ref] = llm
	return llm, nil
}

// ValidateProvider accepts all fake providers used by router tests.
func (f *routerRecordingFactory) ValidateProvider(string, schema.Provider) error {
	return nil
}

type routerRecordingLLM struct {
	name     string
	requests []llmapi.LLMRequest
}

// Name returns the provider-native fake model name.
func (m *routerRecordingLLM) Name() string {
	return m.name
}

// GenerateContent records the delegated request and yields one empty response.
func (m *routerRecordingLLM) GenerateContent(_ context.Context, req *llmapi.LLMRequest, _ bool) iter.Seq2[*llmapi.LLMResponse, error] {
	return func(yield func(*llmapi.LLMResponse, error) bool) {
		if req != nil {
			m.requests = append(m.requests, *req)
		}
		yield(&llmapi.LLMResponse{}, nil)
	}
}

// TestRoutingLLMUsesRequestedModelRef verifies non-default refs select clients.
func TestRoutingLLMUsesRequestedModelRef(t *testing.T) {
	cfg := routerTestModelConfig()
	recording := &routerRecordingFactory{}
	factory := routerTestFactory(recording)
	defaultSelection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	llm, err := factory.CreateRouter(context.Background(), cfg, defaultSelection)
	if err != nil {
		t.Fatalf("CreateRouter() error = %v", err)
	}

	response := collectRouterResponse(t, llm, &llmapi.LLMRequest{Model: "smart:pro"})

	requested := recording.llms["smart:pro"]
	if requested == nil {
		t.Fatalf("requested model client was not created")
	}
	if got := requested.requests[0].Model; got != "" {
		t.Fatalf("delegated request Model = %q, want empty provider-native request", got)
	}
	if got, want := response.ModelVersion, "smart:pro"; got != want {
		t.Fatalf("response ModelVersion = %q, want %q", got, want)
	}
	if got, want := response.CustomMetadata[routeMetadataModelNameKey], "wire-pro"; got != want {
		t.Fatalf("response model metadata = %q, want %q", got, want)
	}
}

// TestRoutingLLMDefaultsToStartupSelection verifies ADK's default model ref.
func TestRoutingLLMDefaultsToStartupSelection(t *testing.T) {
	cfg := routerTestModelConfig()
	recording := &routerRecordingFactory{}
	factory := routerTestFactory(recording)
	defaultSelection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	llm, err := factory.CreateRouter(context.Background(), cfg, defaultSelection)
	if err != nil {
		t.Fatalf("CreateRouter() error = %v", err)
	}

	collectRouterResponse(t, llm, &llmapi.LLMRequest{Model: llm.Name()})

	defaultLLM := recording.llms["fast:mini"]
	if defaultLLM == nil {
		t.Fatalf("default model client was not created")
	}
	if len(defaultLLM.requests) != 1 {
		t.Fatalf("default model requests = %d, want 1", len(defaultLLM.requests))
	}
}

// TestRoutingLLMRejectsInvalidModelRef verifies invalid override diagnostics.
func TestRoutingLLMRejectsInvalidModelRef(t *testing.T) {
	cfg := routerTestModelConfig()
	factory := routerTestFactory(&routerRecordingFactory{})
	defaultSelection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	llm, err := factory.CreateRouter(context.Background(), cfg, defaultSelection)
	if err != nil {
		t.Fatalf("CreateRouter() error = %v", err)
	}

	gotErr := firstRouterError(llm, &llmapi.LLMRequest{Model: "missing"})
	if gotErr == nil {
		t.Fatalf("GenerateContent() error = nil, want invalid ref error")
	}
}

// TestRoutingLLMRefreshesCredentialBackedClients avoids stale API keys.
func TestRoutingLLMRefreshesCredentialBackedClients(t *testing.T) {
	cfg := routerTestModelConfig()
	smart := cfg.Providers["smart"]
	smart.APIKeyEnv = "OPENAI_API_KEY"
	cfg.Providers["smart"] = smart
	recording := &routerRecordingFactory{}
	factory := routerTestFactory(recording)
	defaultSelection, err := cfg.ResolveProvider("", "")
	if err != nil {
		t.Fatalf("ResolveProvider() error = %v", err)
	}
	llm, err := factory.CreateRouter(context.Background(), cfg, defaultSelection)
	if err != nil {
		t.Fatalf("CreateRouter() error = %v", err)
	}

	collectRouterResponse(t, llm, &llmapi.LLMRequest{Model: "smart:pro"})
	collectRouterResponse(t, llm, &llmapi.LLMRequest{Model: "smart:pro"})

	if got := recording.creates["smart:pro"]; got != 2 {
		t.Fatalf("credential-backed client creates = %d, want 2", got)
	}
}

// routerTestFactory builds a model factory with one fake adapter.
func routerTestFactory(provider adapter.ProviderFactory) *Factory {
	factory := &Factory{providers: map[string]adapter.ProviderFactory{}}
	factory.Register("fake", provider)
	return factory
}

// routerTestModelConfig returns two selectable fake providers.
func routerTestModelConfig() *schema.ModelConfig {
	return &schema.ModelConfig{
		Default: "fast:mini",
		Providers: map[string]schema.Provider{
			"fast": {
				Name:    "Fast",
				Adapter: "fake",
				Default: "mini",
				Models: []schema.Model{
					{ID: "mini", Model: "wire-mini"},
				},
			},
			"smart": {
				Name:    "Smart",
				Adapter: "fake",
				Default: "pro",
				Models: []schema.Model{
					{ID: "pro", Model: "wire-pro"},
				},
			},
		},
	}
}

// collectRouterResponse consumes one router response stream and fails on error.
func collectRouterResponse(t *testing.T, llm llmapi.LLM, req *llmapi.LLMRequest) *llmapi.LLMResponse {
	t.Helper()
	for response, err := range llm.GenerateContent(context.Background(), req, false) {
		if err != nil {
			t.Fatalf("GenerateContent() error = %v", err)
		}
		return response
	}
	t.Fatalf("GenerateContent() yielded no response")
	return nil
}

// firstRouterError returns the first error yielded by a router response stream.
func firstRouterError(llm llmapi.LLM, req *llmapi.LLMRequest) error {
	for _, err := range llm.GenerateContent(context.Background(), req, false) {
		if err != nil {
			return err
		}
		return nil
	}
	return fmt.Errorf("no response yielded")
}
