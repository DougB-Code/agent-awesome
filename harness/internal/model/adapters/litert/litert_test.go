// This file tests local LiteRT-LM adapter request and tool-call handling.
package litert

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/genai"
)

func TestGenerateContentTranslatesGemmaTaskMarkupToFunctionCall(t *testing.T) {
	executable := writeExecutable(t, `#!/bin/sh
echo '<|tool_call>call:task_tool{action: "create", details: { "description": "Buy milk" }, idempotency_key: "personal_pilot:session:"}<tool_call|>'
`)
	modelPath := writeFile(t, "model.litertlm", "model")
	llm, err := NewFactory().Create(context.Background(), schema.ProviderSelection{
		Name: "local",
		Provider: schema.Provider{
			Adapter:    "litert",
			Executable: executable,
		},
		Model: schema.Model{
			ID:    "gemma",
			Model: "gemma",
			Path:  modelPath,
		},
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	var got *llmapi.LLMResponse
	for response, err := range llm.GenerateContent(context.Background(), &llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("Remember that I need to buy milk", "user"),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{
							Name:        "create_task",
							Description: "Create a task.",
							ParametersJsonSchema: map[string]any{
								"type": "object",
								"properties": map[string]any{
									"title":           map[string]any{"type": "string"},
									"description":     map[string]any{"type": "string"},
									"idempotency_key": map[string]any{"type": "string"},
								},
							},
						},
					},
				},
			},
		},
	}, false) {
		if err != nil {
			t.Fatalf("GenerateContent() error = %v", err)
		}
		got = response
	}

	if got == nil || got.Content == nil || len(got.Content.Parts) != 1 {
		t.Fatalf("response content = %#v, want one function call part", got)
	}
	call := got.Content.Parts[0].FunctionCall
	if call == nil {
		t.Fatalf("part = %#v, want function call", got.Content.Parts[0])
	}
	if call.Name != "create_task" {
		t.Fatalf("call.Name = %q, want create_task", call.Name)
	}
	if call.Args["title"] != "Buy milk" {
		t.Fatalf("call.Args[title] = %#v, want Buy milk", call.Args["title"])
	}
	if call.Args["idempotency_key"] != "personal_pilot:session:" {
		t.Fatalf("call.Args[idempotency_key] = %#v", call.Args["idempotency_key"])
	}
}

// TestValidateProviderRejectsStreamingCapability prevents unsupported local
// model streaming declarations from passing startup validation.
func TestValidateProviderRejectsStreamingCapability(t *testing.T) {
	err := NewFactory().ValidateProvider("local", schema.Provider{
		Models: []schema.Model{
			{
				ID:   "gemma",
				Path: "/tmp/model.litertlm",
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

// TestToolCallFromTextAcceptsUnterminatedGemmaCreateTaskMarkup covers leaked Gemma calls.
func TestToolCallFromTextAcceptsUnterminatedGemmaCreateTaskMarkup(t *testing.T) {
	req := &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{Name: "create_task", Description: "Create a task."},
					},
				},
			},
		},
	}
	text := `<|tool_call>call:create_task{actor: "user", confidence: 0.9, context: "Need to buy milk.", description: "Purchase milk.", due_at: null, effort: 5, energy_required: 1, estimate_minutes: 10, idempotency_key: "personal_pilot:a1bce6ac-f46c-4606-b82d-d76c3411808e:buy_milk", location: "Grocery store", memory_links: [], person: "user", priority: "medium", project: "Groceries", risk: 0.1, scheduled_at: null, status: "pending", title: "Buy Milk", topics: ["groceries", "errand"], urgency: "low", value: 10, view: "list", work_breakdown: ["Go to store", "Select milk", "Pay"]}`

	call := toolCallFromText(text, req)
	if call == nil {
		t.Fatalf("toolCallFromText() = nil, want create_task call")
	}
	if call.Name != "create_task" {
		t.Fatalf("call.Name = %q, want create_task", call.Name)
	}
	if call.Args["title"] != "Buy Milk" {
		t.Fatalf("call.Args[title] = %#v, want Buy Milk", call.Args["title"])
	}
	if call.Args["description"] != "Purchase milk." {
		t.Fatalf("call.Args[description] = %#v, want Purchase milk.", call.Args["description"])
	}
	if got := call.Args["topics"]; got == nil {
		t.Fatalf("call.Args[topics] = nil, want parsed list")
	}
}

// TestToolCallFromTextNormalizesGemmaQuoteMarkers covers LiteRT quote sentinels.
func TestToolCallFromTextNormalizesGemmaQuoteMarkers(t *testing.T) {
	req := &llmapi.LLMRequest{
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{Name: "create_task", Description: "Create a task."},
					},
				},
			},
		},
	}
	text := `<|tool_call>call:create_task{title:<|"|>Buy milk<|"|>, description:<|"|>Buy milk<|"|>, idempotency_key:<|"|>personal_pilot:session:<|"|>}<tool_call|>`

	call := toolCallFromText(text, req)
	if call == nil {
		t.Fatalf("toolCallFromText() = nil, want create_task call")
	}
	if call.Args["title"] != "Buy milk" {
		t.Fatalf("call.Args[title] = %#v, want Buy milk", call.Args["title"])
	}
	if call.Args["description"] != "Buy milk" {
		t.Fatalf("call.Args[description] = %#v, want Buy milk", call.Args["description"])
	}
	if call.Args["idempotency_key"] != "personal_pilot:session:" {
		t.Fatalf("call.Args[idempotency_key] = %#v, want personal_pilot:session:", call.Args["idempotency_key"])
	}
}

func TestToolCallFromTextAddsCreateTaskIdempotency(t *testing.T) {
	req := createTaskRequestWithSession("session-123")
	text := `<|tool_call>call:create_task{title: "Buy milk", description: "Buy milk"}<tool_call|>`

	call := toolCallFromText(text, req)
	if call == nil {
		t.Fatalf("toolCallFromText() = nil, want create_task call")
	}
	if call.Args["idempotency_key"] != "personal_pilot:session-123:buy_milk" {
		t.Fatalf("call.Args[idempotency_key] = %#v", call.Args["idempotency_key"])
	}
}

func TestContentFromLocalTextStopsRepeatedCreateTaskAfterSuccess(t *testing.T) {
	req := createTaskRequestWithSession("session-123")
	req.Contents = append(req.Contents, &genai.Content{
		Role: genai.RoleUser,
		Parts: []*genai.Part{
			{
				FunctionResponse: &genai.FunctionResponse{
					ID:       "call-local",
					Name:     "create_task",
					Response: map[string]any{"output": map[string]any{"title": "Buy milk"}},
				},
			},
		},
	})
	text := `<|tool_call>call:create_task{title: "Buy milk", description: "Buy milk"}<tool_call|>`

	content := contentFromLocalText(text, req)
	if content == nil || len(content.Parts) != 1 || content.Parts[0].Text == "" {
		t.Fatalf("content = %#v, want final text", content)
	}
	if content.Parts[0].FunctionCall != nil {
		t.Fatalf("content part = %#v, want no repeated function call", content.Parts[0])
	}
	if !strings.Contains(content.Parts[0].Text, "Buy milk") {
		t.Fatalf("content text = %q, want task title", content.Parts[0].Text)
	}
}

func TestPromptIncludesAvailableToolNames(t *testing.T) {
	prompt, err := promptFromRequest(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("hello", "user"),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{Name: "create_task", Description: "Create a task."},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if !strings.Contains(prompt, "create_task") {
		t.Fatalf("prompt = %q, want tool name", prompt)
	}
}

func createTaskRequestWithSession(sessionID string) *llmapi.LLMRequest {
	return &llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText(
				`[[AGENT_AWESOME_SESSION_CONTEXT: Current chat session id is "`+sessionID+`".]]`+"\nMake a reminder to buy milk",
				"user",
			),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{Name: "create_task", Description: "Create a task."},
					},
				},
			},
		},
	}
}

func writeExecutable(t *testing.T, content string) string {
	t.Helper()
	path := writeFile(t, "litert-lm", content)
	if runtime.GOOS == "windows" {
		return path
	}
	if err := os.Chmod(path, 0o755); err != nil {
		t.Fatalf("chmod: %v", err)
	}
	return path
}

func writeFile(t *testing.T, name string, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	return path
}
