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
echo '<|tool_call>call:task_tool{action: "create", details: { "description": "Buy milk" }, idempotency_key: "agent_awesome:session:"}<tool_call|>'
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
	if call.Args["idempotency_key"] != "agent_awesome:session:" {
		t.Fatalf("call.Args[idempotency_key] = %#v", call.Args["idempotency_key"])
	}
}

func TestGenerateContentIncludesLiteRTStderrOnCommandFailure(t *testing.T) {
	executable := writeExecutable(t, `#!/bin/sh
echo 'prompt parser rejected token' >&2
exit 1
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

	var got error
	for _, err := range llm.GenerateContent(context.Background(), &llmapi.LLMRequest{
		Contents: []*genai.Content{genai.NewContentFromText("hello", "user")},
	}, false) {
		got = err
	}

	if got == nil {
		t.Fatalf("GenerateContent() error = nil, want subprocess failure")
	}
	if !strings.Contains(got.Error(), "prompt parser rejected token") {
		t.Fatalf("GenerateContent() error = %v, want LiteRT stderr", got)
	}
}

// TestCreateDefersMissingExecutableUntilGeneration keeps tool APIs available at startup.
func TestCreateDefersMissingExecutableUntilGeneration(t *testing.T) {
	modelPath := writeFile(t, "model.litertlm", "model")
	missing := filepath.Join(t.TempDir(), "missing-litert-lm")
	llm, err := NewFactory().Create(context.Background(), schema.ProviderSelection{
		Name: "local",
		Provider: schema.Provider{
			Adapter:    "litert",
			Executable: missing,
		},
		Model: schema.Model{
			ID:    "gemma",
			Model: "gemma",
			Path:  modelPath,
		},
	})
	if err != nil {
		t.Fatalf("Create() error = %v, want deferred executable lookup", err)
	}

	var got error
	for _, err := range llm.GenerateContent(context.Background(), &llmapi.LLMRequest{
		Contents: []*genai.Content{genai.NewContentFromText("hello", "user")},
	}, false) {
		got = err
	}

	if got == nil || !strings.Contains(got.Error(), "LiteRT-LM executable") {
		t.Fatalf("GenerateContent() error = %v, want missing executable error", got)
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
	text := `<|tool_call>call:create_task{actor: "user", confidence: 0.9, context: "Need to buy milk.", description: "Purchase milk.", due_at: null, effort: 5, energy_required: 1, estimate_minutes: 10, idempotency_key: "agent_awesome:a1bce6ac-f46c-4606-b82d-d76c3411808e:buy_milk", location: "Grocery store", memory_links: [], person: "user", priority: "medium", project: "Groceries", risk: 0.1, scheduled_at: null, status: "pending", title: "Buy Milk", topics: ["groceries", "errand"], urgency: "low", value: 10, view: "list", work_breakdown: ["Go to store", "Select milk", "Pay"]}`

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
	text := `<|tool_call>call:create_task{title:<|"|>Buy milk<|"|>, description:<|"|>Buy milk<|"|>, idempotency_key:<|"|>agent_awesome:session:<|"|>}<tool_call|>`

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
	if call.Args["idempotency_key"] != "agent_awesome:session:" {
		t.Fatalf("call.Args[idempotency_key] = %#v, want agent_awesome:session:", call.Args["idempotency_key"])
	}
}

// TestToolCallFromTextAcceptsGemmaNestedToolCallWrapper covers Gemma's wrapper.
func TestToolCallFromTextAcceptsGemmaNestedToolCallWrapper(t *testing.T) {
	req := createTaskRequest()
	text := `<|tool_call>call:tool_call{create_task{description:<|"|>Buy milk<|"|>,title:<|"|>Buy Milk<|"|>}}<tool_call|>`

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
	if call.Args["description"] != "Buy milk" {
		t.Fatalf("call.Args[description] = %#v, want Buy milk", call.Args["description"])
	}
	if _, ok := call.Args["idempotency_key"]; ok {
		t.Fatalf("call.Args[idempotency_key] = %#v, want parser to leave idempotency to ADK callback", call.Args["idempotency_key"])
	}
}

// TestContentFromLocalTextSuppressesInvalidToolMarkup keeps control text hidden.
func TestContentFromLocalTextSuppressesInvalidToolMarkup(t *testing.T) {
	content := contentFromLocalText("<|tool_call>call:create_task{broken<tool_call|>", createTaskRequest())
	if content == nil || len(content.Parts) != 1 || content.Parts[0].Text == "" {
		t.Fatalf("content = %#v, want safe text response", content)
	}
	if strings.Contains(content.Parts[0].Text, "<|tool_call>") {
		t.Fatalf("content text leaked tool markup: %q", content.Parts[0].Text)
	}
}

func TestToolCallFromTextLeavesIdempotencyToRuntimeCallback(t *testing.T) {
	req := createTaskRequest()
	text := `<|tool_call>call:create_task{title: "Buy milk", description: "Buy milk"}<tool_call|>`

	call := toolCallFromText(text, req)
	if call == nil {
		t.Fatalf("toolCallFromText() = nil, want create_task call")
	}
	if _, ok := call.Args["idempotency_key"]; ok {
		t.Fatalf("call.Args[idempotency_key] = %#v, want parser to leave idempotency to ADK callback", call.Args["idempotency_key"])
	}
}

func TestContentFromLocalTextStopsRepeatedCreateTaskAfterSuccess(t *testing.T) {
	req := createTaskRequest()
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
	if !strings.Contains(prompt, "<|tool>declaration:create_task") {
		t.Fatalf("prompt = %q, want Gemma tool declaration", prompt)
	}
	if !strings.Contains(prompt, `type:<|"|>OBJECT<|"|>`) {
		t.Fatalf("prompt = %q, want Gemma upper-case schema type", prompt)
	}
	if !strings.HasSuffix(prompt, "<|turn>model") {
		t.Fatalf("prompt = %q, want Gemma generation turn", prompt)
	}
}

func TestPromptSerializesToolHistoryForGemma(t *testing.T) {
	req := createTaskRequest()
	req.Contents = []*genai.Content{
		genai.NewContentFromText("Make a reminder to buy milk", "user"),
		{
			Role: genai.RoleModel,
			Parts: []*genai.Part{
				genai.NewPartFromFunctionCall("create_task", map[string]any{"title": "Buy milk"}),
			},
		},
		{
			Role: genai.RoleUser,
			Parts: []*genai.Part{
				genai.NewPartFromFunctionResponse("create_task", map[string]any{"ok": true}),
			},
		},
	}
	req.Contents[1].Parts[0].FunctionCall.ID = "call-local"
	req.Contents[2].Parts[0].FunctionResponse.ID = "call-local"

	prompt, err := promptFromRequest(req)
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if !strings.Contains(prompt, `<|tool_call>call:create_task{title:<|"|>Buy milk<|"|>}<tool_call|><|tool_response>`) {
		t.Fatalf("prompt = %q, want Gemma tool call followed by response block", prompt)
	}
	if !strings.Contains(prompt, `response:create_task{ok:true}<tool_response|><turn|>`) {
		t.Fatalf("prompt = %q, want Gemma tool response", prompt)
	}
	if !strings.HasSuffix(prompt, "<|turn>model") {
		t.Fatalf("prompt = %q, want final model generation turn", prompt)
	}
}

func TestPromptSerializesGenAISchemaToolDeclarationForGemma(t *testing.T) {
	prompt, err := promptFromRequest(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("hello", "user"),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{
				{
					FunctionDeclarations: []*genai.FunctionDeclaration{
						{
							Name:        "remember",
							Description: "Save a memory.",
							Parameters: &genai.Schema{
								Type: genai.TypeObject,
								Properties: map[string]*genai.Schema{
									"text": {Type: genai.TypeString, Description: "Memory text."},
								},
								Required: []string{"text"},
							},
						},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if !strings.Contains(prompt, `<|tool>declaration:remember`) {
		t.Fatalf("prompt = %q, want remember declaration", prompt)
	}
	if !strings.Contains(prompt, `required:[<|"|>text<|"|>]`) {
		t.Fatalf("prompt = %q, want required text schema", prompt)
	}
}

func TestPromptOmitsIrrelevantLargeToolCatalogForGemma(t *testing.T) {
	prompt, err := promptFromRequest(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("hello", "user"),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{{FunctionDeclarations: largeToolCatalog()}},
		},
	})
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if strings.Contains(prompt, "<|tool>declaration:") {
		t.Fatalf("prompt = %q, want irrelevant large tool catalog omitted", prompt)
	}
}

func TestPromptSelectsCreateTaskFromLargeToolCatalogForGemma(t *testing.T) {
	prompt, err := promptFromRequest(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("Make a reminder to buy milk", "user"),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{{FunctionDeclarations: largeToolCatalog()}},
		},
	})
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if !strings.Contains(prompt, "<|tool>declaration:create_task") {
		t.Fatalf("prompt = %q, want create_task declaration", prompt)
	}
	if strings.Contains(prompt, "<|tool>declaration:search_sources") {
		t.Fatalf("prompt = %q, want unrelated search_sources declaration omitted", prompt)
	}
}

// TestPromptSelectsExecutiveSummaryFromLargeToolCatalogForGemma verifies Today prompts keep the summary tool.
func TestPromptSelectsExecutiveSummaryFromLargeToolCatalogForGemma(t *testing.T) {
	prompt, err := promptFromRequest(&llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("Brief me on what needs my attention today", "user"),
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{{FunctionDeclarations: largeToolCatalog()}},
		},
	})
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if !strings.Contains(prompt, "<|tool>declaration:project_executive_summary") {
		t.Fatalf("prompt = %q, want project_executive_summary declaration", prompt)
	}
}

func TestPromptKeepsToolHistoryDeclarationInLargeCatalogForGemma(t *testing.T) {
	req := &llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("Thanks", "user"),
			{
				Role: genai.RoleModel,
				Parts: []*genai.Part{
					genai.NewPartFromFunctionCall("create_task", map[string]any{"title": "Buy milk"}),
				},
			},
		},
		Config: &genai.GenerateContentConfig{
			Tools: []*genai.Tool{{FunctionDeclarations: largeToolCatalog()}},
		},
	}

	prompt, err := promptFromRequest(req)
	if err != nil {
		t.Fatalf("promptFromRequest() error = %v", err)
	}
	if !strings.Contains(prompt, "<|tool>declaration:create_task") {
		t.Fatalf("prompt = %q, want create_task declaration preserved for tool history", prompt)
	}
}

func TestToolCallFromTextAcceptsGemmaOfficialToolCallTurn(t *testing.T) {
	text := `<|turn>model
<|tool_call>call:create_task{title:<|"|>Buy milk<|"|>,description:<|"|>Buy milk<|"|>}<tool_call|><|tool_response>`

	call := toolCallFromText(text, createTaskRequest())
	if call == nil {
		t.Fatalf("toolCallFromText() = nil, want create_task call")
	}
	if call.Name != "create_task" {
		t.Fatalf("call.Name = %q, want create_task", call.Name)
	}
	if call.Args["title"] != "Buy milk" {
		t.Fatalf("call.Args[title] = %#v, want Buy milk", call.Args["title"])
	}
}

func largeToolCatalog() []*genai.FunctionDeclaration {
	return []*genai.FunctionDeclaration{
		{Name: "remember", Description: "Store one small memory nugget."},
		{Name: "save_memory_candidate", Description: "Advanced memory capture."},
		{Name: "search_memory", Description: "Search memory metadata."},
		{Name: "search_sources", Description: "Search source content."},
		{Name: "load_entity_page", Description: "Load an entity page."},
		{Name: "load_timeline", Description: "Load a timeline."},
		{Name: "query_context_graph", Description: "Execute a graph query."},
		{
			Name:        "create_task",
			Description: "Create a graph-backed operational task or todo.",
			ParametersJsonSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"title":       map[string]any{"type": "string"},
					"description": map[string]any{"type": "string"},
				},
				"required": []string{"title"},
			},
		},
		{Name: "list_tasks", Description: "List graph-backed tasks."},
		{Name: "project_executive_summary", Description: "Read the canonical Today executive summary projection."},
		{Name: "explain_executive_summary_item", Description: "Explain why one Today projection item was surfaced."},
		{Name: "update_task", Description: "Patch a graph-backed task."},
		{Name: "complete_task", Description: "Mark a graph-backed task done."},
		{Name: "delete_task", Description: "Delete a graph-backed task."},
	}
}

func createTaskRequest() *llmapi.LLMRequest {
	return &llmapi.LLMRequest{
		Contents: []*genai.Content{
			genai.NewContentFromText("Make a reminder to buy milk", "user"),
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
