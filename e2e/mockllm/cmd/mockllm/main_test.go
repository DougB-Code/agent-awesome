// This file verifies deterministic mock-provider responses for release E2E.
package main

import "testing"

// TestChatCompletionResponseForEchoesNormalPrompt verifies plain chat behavior.
func TestChatCompletionResponseForEchoesNormalPrompt(t *testing.T) {
	response := chatCompletionResponseFor(map[string]any{
		"messages": []any{
			map[string]any{"role": "user", "content": "hello release"},
		},
	})

	message := firstChoiceMessage(t, response)
	if got, want := message["content"], "mock llm e2e response: hello release"; got != want {
		t.Fatalf("content = %q, want %q", got, want)
	}
}

// TestChatCompletionResponseForTaskToolFlow verifies create_task tool flow.
func TestChatCompletionResponseForTaskToolFlow(t *testing.T) {
	first := chatCompletionResponseFor(map[string]any{
		"messages": []any{
			map[string]any{
				"role":    "user",
				"content": "please create release e2e task",
			},
		},
	})

	message := firstChoiceMessage(t, first)
	toolCalls, ok := message["tool_calls"].([]map[string]any)
	if !ok || len(toolCalls) != 1 {
		t.Fatalf("tool_calls = %#v, want one call", message["tool_calls"])
	}
	if got := toolCalls[0]["id"]; got != taskToolCallID {
		t.Fatalf("tool call id = %q, want %q", got, taskToolCallID)
	}
	function, ok := toolCalls[0]["function"].(map[string]string)
	if !ok {
		t.Fatalf("function = %#v, want map", toolCalls[0]["function"])
	}
	if function["name"] != "create_task" {
		t.Fatalf("function name = %q, want create_task", function["name"])
	}

	final := chatCompletionResponseFor(map[string]any{
		"messages": []any{
			map[string]any{
				"role":    "user",
				"content": "please create release e2e task",
			},
			map[string]any{"role": "tool", "tool_call_id": taskToolCallID},
		},
	})
	message = firstChoiceMessage(t, final)
	if got, want := message["content"], taskResponseText; got != want {
		t.Fatalf("content = %q, want %q", got, want)
	}
}

// firstChoiceMessage returns the first assistant message from a mock response.
func firstChoiceMessage(t *testing.T, response map[string]any) map[string]any {
	t.Helper()
	choices, ok := response["choices"].([]map[string]any)
	if !ok || len(choices) == 0 {
		t.Fatalf("choices = %#v, want at least one choice", response["choices"])
	}
	message, ok := choices[0]["message"].(map[string]any)
	if !ok {
		t.Fatalf("message = %#v, want map", choices[0]["message"])
	}
	return message
}
