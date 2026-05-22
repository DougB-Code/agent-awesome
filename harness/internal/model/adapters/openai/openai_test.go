// This file tests OpenAI-compatible adapter request and response handling.
package openai

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/model/adapter"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

func TestOpenAICompatibleGenerateBuildsChatRequest(t *testing.T) {
	var decoded struct {
		Model    string `json:"model"`
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got, want := r.Header.Get("authorization"), "Bearer test-key"; got != want {
			t.Fatalf("authorization header = %q, want %q", got, want)
		}
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"pong"}}]}`))
	}))
	defer server.Close()

	model := &openAICompatibleModel{
		apiKey:   "test-key",
		url:      server.URL,
		client:   server.Client(),
		name:     "configured-model",
		provider: "test-openai",
	}
	got, err := model.generate(context.Background(), &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			SystemInstruction: genai.NewContentFromText("be terse", genai.RoleUser),
		},
		Contents: []*genai.Content{
			genai.NewContentFromText("ping", genai.RoleUser),
		},
	})
	if err != nil {
		t.Fatalf("generate() error = %v", err)
	}
	if got.Content == nil || len(got.Content.Parts) != 1 || got.Content.Parts[0].Text != "pong" {
		t.Fatalf("generate() content = %#v, want pong text", got.Content)
	}
	if got, want := decoded.Model, "configured-model"; got != want {
		t.Fatalf("request model = %q, want %q", got, want)
	}
	if len(decoded.Messages) != 2 {
		t.Fatalf("request messages len = %d, want 2", len(decoded.Messages))
	}
	if got, want := decoded.Messages[0].Role, "system"; got != want {
		t.Fatalf("system role = %q, want %q", got, want)
	}
	if got, want := decoded.Messages[0].Content, "be terse"; got != want {
		t.Fatalf("system content = %q, want %q", got, want)
	}
	if got, want := decoded.Messages[1].Role, "user"; got != want {
		t.Fatalf("user role = %q, want %q", got, want)
	}
	if got, want := decoded.Messages[1].Content, "ping"; got != want {
		t.Fatalf("user content = %q, want %q", got, want)
	}
}

func TestOpenAICompatibleNon2xxErrorIsSanitized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("authorization"); got != "" {
			t.Fatalf("authorization header = %q, want empty for anonymous loopback", got)
		}
		w.Header().Set("content-type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`{"error":{"message":"secret account detail","type":"rate_limit_error","code":"rate_limit","param":""}}`))
	}))
	defer server.Close()

	model := &openAICompatibleModel{
		url:      server.URL,
		client:   server.Client(),
		name:     "test-model",
		provider: "test-openai",
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
		staticCredentialResolver{"OPENAI_TEST_API_KEY": "test-key"},
		clients,
	).Create(context.Background(), schema.ProviderSelection{
		Name: "local",
		Provider: schema.Provider{
			Adapter:   "openai",
			APIKeyEnv: "OPENAI_TEST_API_KEY",
			URL:       "http://127.0.0.1:8080/v1/chat/completions",
		},
		Model: schema.Model{ID: "test", Model: "test-model"},
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	model, ok := llm.(*openAICompatibleModel)
	if !ok {
		t.Fatalf("Create() returned %T, want *openAICompatibleModel", llm)
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

// TestValidateProviderRejectsRemoteEndpointWithoutAPIKey protects hosted APIs.
func TestValidateProviderRejectsRemoteEndpointWithoutAPIKey(t *testing.T) {
	err := (Factory{}).ValidateProvider("openai", schema.Provider{
		URL: "https://api.openai.com/v1/chat/completions",
	})
	if err == nil || !strings.Contains(err.Error(), "requires api-key") {
		t.Fatalf("ValidateProvider() error = %v, want api-key requirement", err)
	}
}

// TestValidateProviderRequiresExplicitOptionalAuthForLoopback avoids accidental anonymous providers.
func TestValidateProviderRequiresExplicitOptionalAuthForLoopback(t *testing.T) {
	err := (Factory{}).ValidateProvider("local", schema.Provider{
		URL: "http://127.0.0.1:11434/v1/chat/completions",
	})
	if err == nil || !strings.Contains(err.Error(), "auth: optional") {
		t.Fatalf("ValidateProvider() error = %v, want explicit optional auth", err)
	}
}

// TestValidateProviderAllowsExplicitAnonymousLoopback keeps local model servers supported.
func TestValidateProviderAllowsExplicitAnonymousLoopback(t *testing.T) {
	err := (Factory{}).ValidateProvider("local", schema.Provider{
		Auth: schema.ProviderAuthOptional,
		URL:  "http://127.0.0.1:11434/v1/chat/completions",
	})
	if err != nil {
		t.Fatalf("ValidateProvider() error = %v", err)
	}
}

// TestValidateProviderRejectsStreamingCapability prevents unsupported model
// capabilities from reaching runtime startup.
func TestValidateProviderRejectsStreamingCapability(t *testing.T) {
	err := (Factory{}).ValidateProvider("openai", schema.Provider{
		APIKeyEnv: "OPENAI_API_KEY",
		URL:       "https://api.openai.com/v1/chat/completions",
		Models: []schema.Model{
			{
				ID:    "gpt",
				Model: "gpt-example",
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

func TestOpenAICompatibleSendsToolsAndParsesToolCalls(t *testing.T) {
	var decoded struct {
		Tools []struct {
			Type     string `json:"type"`
			Function struct {
				Name        string         `json:"name"`
				Description string         `json:"description"`
				Parameters  map[string]any `json:"parameters"`
			} `json:"function"`
		} `json:"tools"`
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call-1","type":"function","function":{"name":"city_time","arguments":"{\"city\":\"Lisbon\"}"}}]}}]}`))
	}))
	defer server.Close()

	model := &openAICompatibleModel{
		url:      server.URL,
		client:   server.Client(),
		name:     "test-model",
		provider: "test-openai",
	}
	got, err := model.generate(context.Background(), &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{
							Name:        "city_time",
							Description: "Return the time for a city.",
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
	if len(decoded.Tools) != 1 || decoded.Tools[0].Type != "function" || decoded.Tools[0].Function.Name != "city_time" {
		t.Fatalf("request tools = %#v, want city_time", decoded.Tools)
	}
	if got, want := decoded.Tools[0].Function.Parameters["type"], "object"; got != want {
		t.Fatalf("tool parameter type = %#v, want %q", got, want)
	}
	if got.Content == nil || len(got.Content.Parts) != 1 || got.Content.Parts[0].FunctionCall == nil {
		t.Fatalf("generate() content = %#v, want function call", got.Content)
	}
	call := got.Content.Parts[0].FunctionCall
	if call.ID != "call-1" || call.Name != "city_time" || call.Args["city"] != "Lisbon" {
		t.Fatalf("function call = %#v, want city_time Lisbon", call)
	}
}

func TestOpenAICompatibleNormalizesGenAISchemaTools(t *testing.T) {
	var parameters map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var decoded struct {
			Tools []struct {
				Function struct {
					Parameters map[string]any `json:"parameters"`
				} `json:"function"`
			} `json:"tools"`
		}
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		if len(decoded.Tools) == 1 {
			parameters = decoded.Tools[0].Function.Parameters
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"pong"}}]}`))
	}))
	defer server.Close()

	model := &openAICompatibleModel{
		url:      server.URL,
		client:   server.Client(),
		name:     "test-model",
		provider: "test-openai",
	}
	_, err := model.generate(context.Background(), &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{
							Name: "load_memory",
							Parameters: &genai.Schema{
								Type: genai.TypeObject,
								Properties: map[string]*genai.Schema{
									"query": &genai.Schema{Type: genai.TypeString},
								},
								Required: []string{"query"},
							},
						},
					},
				},
			},
		},
		Contents: []*genai.Content{genai.NewContentFromText("How are you?", genai.RoleUser)},
	})
	if err != nil {
		t.Fatalf("generate() error = %v", err)
	}
	if got, want := parameters["type"], "object"; got != want {
		t.Fatalf("parameters type = %#v, want %q", got, want)
	}
	properties, ok := parameters["properties"].(map[string]any)
	if !ok {
		t.Fatalf("properties = %#v, want object", parameters["properties"])
	}
	query, ok := properties["query"].(map[string]any)
	if !ok {
		t.Fatalf("query property = %#v, want object", properties["query"])
	}
	if got, want := query["type"], "string"; got != want {
		t.Fatalf("query type = %#v, want %q", got, want)
	}
}

func TestOpenAIMessagesSerializesToolResponses(t *testing.T) {
	messages, err := openAIMessages(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			{
				Role: genai.RoleUser,
				Parts: []*genai.Part{
					{
						FunctionResponse: &genai.FunctionResponse{
							ID:       "call-1",
							Name:     "city_time",
							Response: map[string]any{"summary": "ok"},
						},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("openAIMessages() error = %v", err)
	}
	data, err := json.Marshal(messages)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	var decoded []struct {
		Role       string `json:"role"`
		ToolCallID string `json:"tool_call_id"`
		Content    string `json:"content"`
	}
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if len(decoded) != 1 {
		t.Fatalf("messages len = %d, want 1", len(decoded))
	}
	if got, want := decoded[0].Role, "tool"; got != want {
		t.Fatalf("role = %q, want %q", got, want)
	}
	if got, want := decoded[0].ToolCallID, "call-1"; got != want {
		t.Fatalf("tool_call_id = %q, want %q", got, want)
	}
	if got, want := decoded[0].Content, `{"summary":"ok"}`; got != want {
		t.Fatalf("content = %q, want %q", got, want)
	}
}

func TestOpenAICompatibleRejectsStreaming(t *testing.T) {
	model := &openAICompatibleModel{provider: "test-openai"}
	for _, err := range model.GenerateContent(context.Background(), &llmapi.LLMRequest{}, true) {
		if err == nil || !strings.Contains(err.Error(), "does not support streaming") {
			t.Fatalf("GenerateContent() error = %v, want streaming unsupported", err)
		}
		return
	}
	t.Fatalf("GenerateContent() yielded nothing")
}

func TestOpenAIMessagesSerializesToolCalls(t *testing.T) {
	messages, err := openAIMessages(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			{
				Role: genai.RoleModel,
				Parts: []*genai.Part{
					{FunctionCall: &genai.FunctionCall{ID: "call-1", Name: "tool", Args: map[string]any{"city": "Toronto"}}},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("openAIMessages() error = %v", err)
	}
	if len(messages) != 1 {
		t.Fatalf("openAIMessages() = %#v, want assistant tool call", messages)
	}
	data, err := json.Marshal(messages)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	var decoded []struct {
		Role      string `json:"role"`
		ToolCalls []struct {
			ID       string `json:"id"`
			Type     string `json:"type"`
			Function struct {
				Name      string `json:"name"`
				Arguments string `json:"arguments"`
			} `json:"function"`
		} `json:"tool_calls"`
	}
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if len(decoded) != 1 || decoded[0].Role != "assistant" || len(decoded[0].ToolCalls) != 1 {
		t.Fatalf("messages = %#v, want assistant tool call", decoded)
	}
	toolCall := decoded[0].ToolCalls[0]
	if toolCall.ID != "call-1" || toolCall.Type != "function" || toolCall.Function.Name != "tool" {
		t.Fatalf("tool call = %#v, want assistant tool call", toolCall)
	}
	if got, want := toolCall.Function.Arguments, `{"city":"Toronto"}`; got != want {
		t.Fatalf("tool call arguments = %q, want %q", got, want)
	}
}

func TestOpenAICompatibleRejectsUnsupportedRole(t *testing.T) {
	_, err := openAIMessages(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromParts([]*genai.Part{genai.NewPartFromText("tool result")}, "tool"),
		},
	})
	if err == nil || !strings.Contains(err.Error(), "unsupported OpenAI-compatible role") {
		t.Fatalf("openAIMessages() error = %v, want unsupported role", err)
	}
}
