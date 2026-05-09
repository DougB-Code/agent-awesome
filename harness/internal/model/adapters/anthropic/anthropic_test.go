// This file tests Anthropic adapter request and response handling.
package anthropic

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

func TestAnthropicGenerateBuildsMessagesRequest(t *testing.T) {
	var decoded anthropicRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got, want := r.Header.Get("x-api-key"), "test-key"; got != want {
			t.Fatalf("x-api-key header = %q, want %q", got, want)
		}
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"content":[{"type":"text","text":"pong"}]}`))
	}))
	defer server.Close()

	model := &anthropicModel{
		apiKey:   "test-key",
		endpoint: server.URL,
		client:   server.Client(),
		name:     "claude-test",
		provider: "test-anthropic",
	}
	got, err := model.generate(context.Background(), &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			SystemInstruction: genai.NewContentFromText("be terse", genai.RoleUser),
		},
		Contents: []*genai.Content{
			genai.NewContentFromText("ping", genai.RoleUser),
			genai.NewContentFromText("thinking", genai.RoleModel),
		},
	})
	if err != nil {
		t.Fatalf("generate() error = %v", err)
	}
	if got.Content == nil || len(got.Content.Parts) != 1 || got.Content.Parts[0].Text != "pong" {
		t.Fatalf("generate() content = %#v, want pong text", got.Content)
	}
	if got, want := decoded.Model, "claude-test"; got != want {
		t.Fatalf("request model = %q, want %q", got, want)
	}
	if got, want := decoded.System, "be terse"; got != want {
		t.Fatalf("request system = %q, want %q", got, want)
	}
	if len(decoded.Messages) != 2 {
		t.Fatalf("request messages len = %d, want 2", len(decoded.Messages))
	}
	if got, want := decoded.Messages[1].Role, "assistant"; got != want {
		t.Fatalf("model role mapped to %q, want %q", got, want)
	}
}

func TestAnthropicNon2xxErrorIsSanitized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"secret account detail"}`, http.StatusInternalServerError)
	}))
	defer server.Close()

	model := &anthropicModel{
		endpoint: server.URL,
		client:   server.Client(),
		name:     "claude-test",
		provider: "test-anthropic",
	}
	_, err := model.generate(context.Background(), &llmapi.LLMRequest{
		Contents: []*genai.Content{genai.NewContentFromText("ping", genai.RoleUser)},
	})
	if err == nil {
		t.Fatalf("generate() error = nil, want provider error")
	}
	var providerErr *adapter.ProviderError
	if !errors.As(err, &providerErr) {
		t.Fatalf("generate() error = %T, want ProviderError", err)
	}
	if !providerErr.Retryable {
		t.Fatalf("ProviderError.Retryable = false, want true")
	}
	if strings.Contains(err.Error(), "secret account detail") {
		t.Fatalf("error leaked provider body: %v", err)
	}
}

func TestFactoryUsesInjectedDependencies(t *testing.T) {
	client := &http.Client{Timeout: 123 * time.Millisecond}
	clients := &recordingHTTPClientFactory{client: client}

	llm, err := NewFactory(
		staticCredentialResolver{"ANTHROPIC_TEST_API_KEY": "test-key"},
		clients,
	).Create(context.Background(), schema.ProviderSelection{
		Name: "anthropic",
		Provider: schema.Provider{
			Adapter:   "anthropic",
			APIKeyEnv: "ANTHROPIC_TEST_API_KEY",
			URL:       "https://api.anthropic.com/v1/messages",
		},
		Model: schema.Model{ID: "test", Model: "claude-test"},
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	model, ok := llm.(*anthropicModel)
	if !ok {
		t.Fatalf("Create() returned %T, want *anthropicModel", llm)
	}
	if model.client != client {
		t.Fatalf("client = %p, want injected client %p", model.client, client)
	}
	if model.apiKey != "test-key" {
		t.Fatalf("apiKey = %q, want injected credential", model.apiKey)
	}
	if !clients.called {
		t.Fatalf("HTTP client factory was not called")
	}
}

// TestValidateProviderRejectsOptionalAuth verifies Anthropic always needs auth.
func TestValidateProviderRejectsOptionalAuth(t *testing.T) {
	err := (Factory{}).ValidateProvider("anthropic", schema.Provider{
		Auth:      schema.ProviderAuthOptional,
		APIKeyEnv: "ANTHROPIC_API_KEY",
		URL:       "https://api.anthropic.com/v1/messages",
	})
	if err == nil || !strings.Contains(err.Error(), "does not support auth: optional") {
		t.Fatalf("ValidateProvider() error = %v, want optional auth rejection", err)
	}
}

// TestValidateProviderRejectsStreamingCapability prevents unsupported model
// capabilities from reaching runtime startup.
func TestValidateProviderRejectsStreamingCapability(t *testing.T) {
	err := (Factory{}).ValidateProvider("anthropic", schema.Provider{
		APIKeyEnv: "ANTHROPIC_API_KEY",
		URL:       "https://api.anthropic.com/v1/messages",
		Models: []schema.Model{
			{
				ID:    "claude",
				Model: "claude-example",
				Capabilities: schema.ModelCapabilities{
					Streaming: true,
				},
			},
		},
	})
	if err == nil || !strings.Contains(err.Error(), "does not support streaming") {
		t.Fatalf("ValidateProvider() error = %v, want streaming capability rejection", err)
	}
}

type staticCredentialResolver map[string]string

func (r staticCredentialResolver) ResolveCredential(name string) (string, error) {
	return r[name], nil
}

type recordingHTTPClientFactory struct {
	client *http.Client
	called bool
}

func (f *recordingHTTPClientFactory) NewHTTPClient() *http.Client {
	f.called = true
	return f.client
}

func TestAnthropicSendsToolsAndParsesToolUse(t *testing.T) {
	var decoded anthropicRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"content":[{"type":"tool_use","id":"call-1","name":"local_exec","input":{"command":"git_status"}}]}`))
	}))
	defer server.Close()

	model := &anthropicModel{
		apiKey:   "test-key",
		endpoint: server.URL,
		client:   server.Client(),
		name:     "claude-test",
		provider: "test-anthropic",
	}
	got, err := model.generate(context.Background(), &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{
							Name:        "local_exec",
							Description: "Run a command.",
							ParametersJsonSchema: map[string]any{
								"type": "object",
							},
						},
					},
				},
			},
		},
		Contents: []*genai.Content{genai.NewContentFromText("status", genai.RoleUser)},
	})
	if err != nil {
		t.Fatalf("generate() error = %v", err)
	}
	if len(decoded.Tools) != 1 || decoded.Tools[0].Name != "local_exec" {
		t.Fatalf("request tools = %#v, want local_exec", decoded.Tools)
	}
	if got.Content == nil || len(got.Content.Parts) != 1 || got.Content.Parts[0].FunctionCall == nil {
		t.Fatalf("generate() content = %#v, want function call", got.Content)
	}
	call := got.Content.Parts[0].FunctionCall
	if call.ID != "call-1" || call.Name != "local_exec" || call.Args["command"] != "git_status" {
		t.Fatalf("function call = %#v, want local_exec git_status", call)
	}
}

func TestAnthropicMessagesSerializesToolResponses(t *testing.T) {
	messages, err := anthropicMessages(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			{
				Role: genai.RoleUser,
				Parts: []*genai.Part{
					{
						FunctionResponse: &genai.FunctionResponse{
							ID:       "call-1",
							Name:     "local_exec",
							Response: map[string]any{"stdout": "ok"},
						},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("anthropicMessages() error = %v", err)
	}
	want := []anthropicMessage{
		{
			Role: "user",
			Content: []anthropicContentBlock{
				{Type: "tool_result", ToolUseID: "call-1", Content: `{"stdout":"ok"}`},
			},
		},
	}
	if !reflect.DeepEqual(messages, want) {
		t.Fatalf("anthropicMessages() = %#v, want %#v", messages, want)
	}
}

func TestAnthropicRejectsStreaming(t *testing.T) {
	model := &anthropicModel{provider: "test-anthropic"}
	for _, err := range model.GenerateContent(context.Background(), &llmapi.LLMRequest{}, true) {
		if err == nil || !strings.Contains(err.Error(), "does not support streaming") {
			t.Fatalf("GenerateContent() error = %v, want streaming unsupported", err)
		}
		return
	}
	t.Fatalf("GenerateContent() yielded nothing")
}

func TestAnthropicRejectsUnsupportedRole(t *testing.T) {
	_, err := anthropicMessages(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromParts([]*genai.Part{genai.NewPartFromText("tool result")}, "tool"),
		},
	})
	if err == nil || !strings.Contains(err.Error(), "unsupported Anthropic role") {
		t.Fatalf("anthropicMessages() error = %v, want unsupported role", err)
	}
}
