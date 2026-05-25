// This file tests live validation runtime adaptation.
package app

import (
	"context"
	"iter"
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	runtimecfg "agentawesome/internal/runtime"
	"agentawesome/internal/services/agentvalidation"
	adkagent "google.golang.org/adk/agent"
	"google.golang.org/adk/model"
	adksession "google.golang.org/adk/session"
	"google.golang.org/genai"
)

// TestRespondWithRuntimeConfigCapturesRuntimeEvidence verifies live evidence.
func TestRespondWithRuntimeConfigCapturesRuntimeEvidence(t *testing.T) {
	rootAgent, err := adkagent.New(adkagent.Config{
		Name: "validator",
		Run:  runtimeEvidenceAgentRun,
	})
	if err != nil {
		t.Fatalf("agent.New() error = %v", err)
	}
	cfg := &runtimecfg.Config{
		AgentLoader:    adkagent.NewSingleLoader(rootAgent),
		SessionService: adksession.InMemoryService(),
	}

	response, err := respondWithRuntimeConfig(context.Background(), agentvalidation.Request{
		Validation: schema.AgentValidation{ID: "uses_search"},
		Prompt:     "Find TODO references.",
	}, cfg)
	if err != nil {
		t.Fatalf("respondWithRuntimeConfig() error = %v", err)
	}
	if response.Text != "Found TODO references." {
		t.Fatalf("response text = %q, want final text", response.Text)
	}
	if len(response.ToolCalls) != 1 {
		t.Fatalf("tool calls = %#v, want one captured tool call", response.ToolCalls)
	}
	call := response.ToolCalls[0]
	if call.ID != "call-1" || call.Name != "command_execute" || call.Arguments["template_id"] != "rg.search_text" {
		t.Fatalf("tool call = %#v, want command_execute rg.search_text", call)
	}
}

// TestValidationPromptIncludesStructuredData verifies live prompts get fixtures.
func TestValidationPromptIncludesStructuredData(t *testing.T) {
	prompt := validationPrompt(agentvalidation.Request{
		Prompt: "Answer with the configured data.",
		Input:  map[string]any{"topic": "milk"},
		Fixtures: map[string]any{
			"memory": []any{map[string]any{"content": "Buy milk"}},
		},
	})

	for _, want := range []string{
		"Answer with the configured data.",
		"Validation data:",
		`"topic":"milk"`,
		`"content":"Buy milk"`,
	} {
		if !strings.Contains(prompt, want) {
			t.Fatalf("prompt = %q, want %q", prompt, want)
		}
	}
}

// runtimeEvidenceAgentRun returns a tool-call event followed by final text.
func runtimeEvidenceAgentRun(ctx adkagent.InvocationContext) iter.Seq2[*adksession.Event, error] {
	return func(yield func(*adksession.Event, error) bool) {
		toolEvent := adksession.NewEvent(ctx.InvocationID())
		toolEvent.LLMResponse = model.LLMResponse{
			Content: &genai.Content{
				Role: genai.RoleModel,
				Parts: []*genai.Part{{
					FunctionCall: &genai.FunctionCall{
						ID:   "call-1",
						Name: "command_execute",
						Args: map[string]any{
							"template_id": "rg.search_text",
						},
					},
				}},
			},
		}
		if !yield(toolEvent, nil) {
			return
		}
		textEvent := adksession.NewEvent(ctx.InvocationID())
		textEvent.LLMResponse = model.LLMResponse{
			Content: genai.NewContentFromText("Found TODO references.", genai.RoleModel),
		}
		yield(textEvent, nil)
	}
}
