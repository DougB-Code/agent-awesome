// This file tests OpenAI-compatible adapter request and response handling.
package openai

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

	"agent-awesome.com/harnessinternal/config/schema"
	"agent-awesome.com/harnessinternal/model/adapter"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

func TestOpenAICompatibleGenerateBuildsChatRequest(t *testing.T) {
	var decoded openAIChatRequest
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
	if got, want := decoded.Messages[0], (openAIMessage{Role: "system", Content: "be terse"}); !reflect.DeepEqual(got, want) {
		t.Fatalf("system message = %#v, want %#v", got, want)
	}
	if got, want := decoded.Messages[1], (openAIMessage{Role: "user", Content: "ping"}); !reflect.DeepEqual(got, want) {
		t.Fatalf("user message = %#v, want %#v", got, want)
	}
}

func TestOpenAICompatibleNon2xxErrorIsSanitized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"secret account detail"}`, http.StatusTooManyRequests)
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
	var decoded openAIChatRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call-1","type":"function","function":{"name":"local_exec","arguments":"{\"command\":\"git_status\"}"}}]}}]}`))
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
	if len(decoded.Tools) != 1 || decoded.Tools[0].Function.Name != "local_exec" {
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

func TestOpenAIMessagesSerializesToolResponses(t *testing.T) {
	messages, err := openAIMessages(&llmapi.LLMRequest{
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
		t.Fatalf("openAIMessages() error = %v", err)
	}
	want := []openAIMessage{{Role: "tool", ToolCallID: "call-1", Content: `{"stdout":"ok"}`}}
	if !reflect.DeepEqual(messages, want) {
		t.Fatalf("openAIMessages() = %#v, want %#v", messages, want)
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

func TestOpenAICompatibleRejectsUnsupportedContentParts(t *testing.T) {
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
	if len(messages) != 1 || len(messages[0].ToolCalls) != 1 {
		t.Fatalf("openAIMessages() = %#v, want assistant tool call", messages)
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
