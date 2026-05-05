// This file tests console rendering and confirmation prompts.
package console

import (
	"bytes"
	"context"
	"iter"
	"strings"
	"testing"

	"google.golang.org/adk/agent"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/adk/session"
	"google.golang.org/adk/tool/toolconfirmation"
	"google.golang.org/genai"
)

func TestConsoleRunTurnPrintsRunnerResponse(t *testing.T) {
	var out bytes.Buffer
	c := NewConsole(strings.NewReader(""), &out)
	r := fakeConsoleRunner{
		events: []*session.Event{
			{
				LLMResponse: llmapi.LLMResponse{
					Content: genai.NewContentFromText("hello", genai.RoleModel),
				},
			},
		},
	}

	err := c.RunTurn(context.Background(), r, "user", "session", genai.NewContentFromText("hi", genai.RoleUser), agent.StreamingModeNone)
	if err != nil {
		t.Fatalf("RunTurn() error = %v", err)
	}
	if got, want := out.String(), "\nAgent -> hello"; got != want {
		t.Fatalf("output = %q, want %q", got, want)
	}
}

func TestConsolePromptForConfirmationUsesInjectedIO(t *testing.T) {
	var out bytes.Buffer
	c := NewConsole(strings.NewReader("2\n"), &out)
	call := genai.NewPartFromFunctionCall(toolconfirmation.FunctionCallName, map[string]any{
		"toolConfirmation": map[string]any{
			"hint": "Run the command?",
			"payload": map[string]any{
				"options": []map[string]any{
					{"action": "deny", "label": "Deny"},
					{"action": "approve_once", "label": "Approve once"},
				},
			},
		},
	}).FunctionCall
	call.ID = "call-1"

	response, err := c.PromptForConfirmation(call)
	if err != nil {
		t.Fatalf("PromptForConfirmation() error = %v", err)
	}
	if !strings.Contains(out.String(), "Run the command?") {
		t.Fatalf("output = %q, want confirmation hint", out.String())
	}
	part := response.Parts[0]
	if got := part.FunctionResponse.Response["confirmed"]; got != true {
		t.Fatalf("confirmed = %v, want true", got)
	}
	payload, ok := part.FunctionResponse.Response["payload"].(map[string]any)
	if !ok {
		t.Fatalf("payload = %T, want map[string]any", part.FunctionResponse.Response["payload"])
	}
	if got := payload["action"]; got != "approve_once" {
		t.Fatalf("action = %v, want approve_once", got)
	}
}

type fakeConsoleRunner struct {
	events []*session.Event
	err    error
}

func (r fakeConsoleRunner) Run(context.Context, string, string, *genai.Content, agent.RunConfig) iter.Seq2[*session.Event, error] {
	return func(yield func(*session.Event, error) bool) {
		for _, event := range r.events {
			if !yield(event, nil) {
				return
			}
		}
		if r.err != nil {
			yield(nil, r.err)
		}
	}
}
