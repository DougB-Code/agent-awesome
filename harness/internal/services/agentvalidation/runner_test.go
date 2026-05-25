// This file tests portable agent-package validation execution.
package agentvalidation

import (
	"context"
	"errors"
	"testing"

	"agentawesome/internal/config/schema"
)

// TestRunMockedAgentResponsePasses verifies mocked response assertions.
func TestRunMockedAgentResponsePasses(t *testing.T) {
	agent := schema.Agent{
		Name:        "research",
		Instruction: "Research carefully.",
		Validations: []schema.AgentValidation{{
			ID:     "answers_briefly",
			Prompt: "Summarize the task.",
			Mocks: map[string]any{
				"agent.response": map[string]any{
					"text": "Use the configured tool and summarize briefly.",
				},
			},
			Assertions: []schema.ValidationAssertion{{
				Type:     "response-contains",
				Contains: "summarize briefly",
			}},
		}},
	}

	result := NewRunner().RunAll(context.Background(), agent)
	if result.Total != 1 || result.Passed != 1 || result.Failed != 0 {
		t.Fatalf("RunAll() = %#v, want one passing validation", result)
	}
}

// TestRunMockedAgentToolCallPasses verifies tool selection assertions.
func TestRunMockedAgentToolCallPasses(t *testing.T) {
	validation := schema.AgentValidation{
		ID:     "uses_search",
		Prompt: "Find the matching file.",
		Mocks: map[string]any{
			"agent.response": map[string]any{
				"text": "I will search the workspace.",
				"tool_calls": []any{
					map[string]any{
						"name": "rg.search_text",
						"arguments": map[string]any{
							"pattern": "needle",
						},
					},
				},
			},
		},
		Assertions: []schema.ValidationAssertion{
			{Type: "tool-call", Equals: "command:rg.search_text"},
			{Type: "json-path", Path: "response.tool_calls.0.arguments.pattern", Equals: "needle"},
		},
	}

	result := NewRunner().Run(context.Background(), validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() = %#v, want passed", result)
	}
}

// TestRunMockedAgentToolCallPassesTemplateID verifies command_execute calls.
func TestRunMockedAgentToolCallPassesTemplateID(t *testing.T) {
	validation := schema.AgentValidation{
		ID:     "uses_template",
		Prompt: "Find the matching file.",
		Mocks: map[string]any{
			"agent.response": map[string]any{
				"tool_calls": []any{
					map[string]any{
						"name": "command_execute",
						"arguments": map[string]any{
							"template_id": "rg.search_text",
							"parameters": map[string]any{
								"pattern": "needle",
							},
						},
					},
				},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:   "tool-call",
			Equals: "command:rg.search_text",
		}},
	}

	result := NewRunner().Run(context.Background(), validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() = %#v, want template-id tool call assertion to pass", result)
	}
}

// TestRunAllReportsToolCallReferences verifies suite-level tool evidence.
func TestRunAllReportsToolCallReferences(t *testing.T) {
	agent := schema.Agent{
		Name:        "research",
		Instruction: "Research carefully.",
		Validations: []schema.AgentValidation{{
			ID:     "uses_search",
			Prompt: "Find the matching file.",
			Mocks: map[string]any{
				"agent.response": map[string]any{
					"tool_calls": []any{
						map[string]any{
							"id":   "command:rg.search_text",
							"name": "rg.search_text",
							"arguments": map[string]any{
								"template_id": "rg.search_text",
								"parameters": map[string]any{
									"pattern": "needle",
								},
							},
						},
					},
				},
			},
			Assertions: []schema.ValidationAssertion{{
				Type:   "tool-call",
				Equals: "command:rg.search_text",
			}},
		}},
	}

	result := NewRunner().RunAll(context.Background(), agent)
	if result.Passed != 1 || len(result.ToolCallReferences) != 1 || result.ToolCallReferences[0] != "command:rg.search_text" {
		t.Fatalf("RunAll() = %#v, want one deduped command tool-call reference", result)
	}
}

// TestRunAllSkipsFailedToolCallAssertionReferences verifies failed expectations are not evidence.
func TestRunAllSkipsFailedToolCallAssertionReferences(t *testing.T) {
	agent := schema.Agent{
		Name:        "research",
		Instruction: "Research carefully.",
		Validations: []schema.AgentValidation{{
			ID:     "does_not_use_search",
			Prompt: "Find the matching file.",
			Mocks: map[string]any{
				"agent.response": map[string]any{"text": "I cannot search."},
			},
			Assertions: []schema.ValidationAssertion{{
				Type:   "tool-call",
				Equals: "command:rg.search_text",
			}},
		}},
	}

	result := NewRunner().RunAll(context.Background(), agent)
	if result.Failed != 1 || len(result.ToolCallReferences) != 0 {
		t.Fatalf("RunAll() = %#v, want no proved tool-call reference from failed assertion", result)
	}
}

// TestRunAllReportsObservedToolCallReferences verifies captured calls remain evidence.
func TestRunAllReportsObservedToolCallReferences(t *testing.T) {
	agent := schema.Agent{
		Name:        "research",
		Instruction: "Research carefully.",
		Validations: []schema.AgentValidation{{
			ID:     "uses_search_but_bad_summary",
			Prompt: "Find the matching file.",
			Mocks: map[string]any{
				"agent.response": map[string]any{
					"text": "I searched.",
					"tool_calls": []any{
						map[string]any{
							"name": "rg.search_text",
							"arguments": map[string]any{
								"pattern": "needle",
							},
						},
					},
				},
			},
			Assertions: []schema.ValidationAssertion{{
				Type:     "response-contains",
				Contains: "summarized result",
			}},
		}},
	}

	result := NewRunner().RunAll(context.Background(), agent)
	if result.Failed != 1 || len(result.ToolCallReferences) != 1 || result.ToolCallReferences[0] != "command:rg.search_text" {
		t.Fatalf("RunAll() = %#v, want observed tool-call reference from response", result)
	}
}

// TestRunMockedAgentValidationExposesInputAndFixtures verifies scenario metadata.
func TestRunMockedAgentValidationExposesInputAndFixtures(t *testing.T) {
	validation := schema.AgentValidation{
		ID:     "uses_context",
		Prompt: "Summarize the remembered task.",
		Input: map[string]any{
			"topic": "milk",
		},
		Fixtures: map[string]any{
			"memory": []any{
				map[string]any{"content": "Buy milk"},
			},
		},
		Mocks: map[string]any{
			"agent.response": map[string]any{
				"text": "The remembered task is to buy milk.",
			},
		},
		Assertions: []schema.ValidationAssertion{
			{Type: "json-path", Path: "input.topic", Equals: "milk"},
			{Type: "json-path", Path: "fixtures.memory.0.content", Contains: "milk"},
		},
	}

	result := NewRunner().Run(context.Background(), validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() = %#v, want passed", result)
	}
	if result.Input["topic"] != "milk" || len(result.Fixtures) != 1 {
		t.Fatalf("Run() result metadata = input %#v fixtures %#v, want copied scenario metadata", result.Input, result.Fixtures)
	}
}

// TestRunMockedAgentResponseFailsMissingMock verifies mocked boundaries are explicit.
func TestRunMockedAgentResponseFailsMissingMock(t *testing.T) {
	result := NewRunner().Run(context.Background(), schema.AgentValidation{
		ID:     "missing_mock",
		Prompt: "Answer.",
	})

	if result.Status != StatusFailed || len(result.Diagnostics) != 1 {
		t.Fatalf("Run() = %#v, want missing mock failure", result)
	}
}

// TestRunMockedAgentResponseFailsEmptyContains verifies assertions prove behavior.
func TestRunMockedAgentResponseFailsEmptyContains(t *testing.T) {
	result := NewRunner().Run(context.Background(), schema.AgentValidation{
		ID:     "empty_contains",
		Prompt: "Answer.",
		Mocks: map[string]any{
			"agent.response": map[string]any{"text": "anything"},
		},
		Assertions: []schema.ValidationAssertion{{
			Type: "response-contains",
		}},
	})

	if result.Status != StatusFailed || len(result.Assertions) != 1 || result.Assertions[0].Passed {
		t.Fatalf("Run() = %#v, want empty contains assertion failure", result)
	}
}

// TestRunMockedAgentToolCallFailsEmptyExpected verifies tool assertions are concrete.
func TestRunMockedAgentToolCallFailsEmptyExpected(t *testing.T) {
	result := NewRunner().Run(context.Background(), schema.AgentValidation{
		ID:     "empty_tool_call",
		Prompt: "Search.",
		Mocks: map[string]any{
			"agent.response": map[string]any{
				"tool_calls": []any{
					map[string]any{"id": "command:rg.search_text"},
				},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type: "tool-call",
		}},
	})

	if result.Status != StatusFailed || len(result.Assertions) != 1 || result.Assertions[0].Passed {
		t.Fatalf("Run() = %#v, want empty tool-call assertion failure", result)
	}
}

// TestRunMockedAgentFailsUnsupportedExpectedKey verifies shortcut typos fail.
func TestRunMockedAgentFailsUnsupportedExpectedKey(t *testing.T) {
	result := NewRunner().Run(context.Background(), schema.AgentValidation{
		ID:     "typo_expected",
		Prompt: "Answer.",
		Mocks: map[string]any{
			"agent.response": map[string]any{"text": "done"},
		},
		Expected: map[string]any{
			"respones_contains": "done",
		},
	})

	if result.Status != StatusFailed || len(result.Assertions) != 1 || result.Assertions[0].Type != "expected" {
		t.Fatalf("Run() = %#v, want unsupported expected key failure", result)
	}
}

// TestRunLiveAgentValidationUnsupported verifies live checks are honest.
func TestRunLiveAgentValidationUnsupported(t *testing.T) {
	result := NewRunner().Run(context.Background(), schema.AgentValidation{
		ID:     "live_agent",
		Mode:   "live",
		Prompt: "Answer.",
	})

	if result.Status != StatusUnsupported {
		t.Fatalf("Run() = %#v, want unsupported live validation", result)
	}
}

// TestRunLiveAgentValidationUsesHost verifies live checks use the injected boundary.
func TestRunLiveAgentValidationUsesHost(t *testing.T) {
	host := recordingHost{
		response: Response{
			Text: "I can help with the live request.",
			ToolCalls: []ToolCall{{
				ID:   "command:rg.search_text",
				Name: "rg.search_text",
				Arguments: map[string]any{
					"pattern": "TODO",
				},
			}},
		},
	}
	agent := schema.Agent{
		Name:        "agent",
		Instruction: "Work.",
		Validations: []schema.AgentValidation{{
			ID:     "live_tool",
			Mode:   "live",
			Prompt: "Find TODO references.",
			Input: map[string]any{
				"pattern": "TODO",
			},
			Assertions: []schema.ValidationAssertion{
				{Type: "response-contains", Contains: "live request"},
				{Type: "tool-call", Equals: "command:rg.search_text"},
			},
		}},
	}

	result := NewRunnerWithHost(&host).RunAll(context.Background(), agent)
	if result.Total != 1 || result.Passed != 1 {
		t.Fatalf("RunAll() = %#v, want one live pass", result)
	}
	if host.request.Agent.Name != "agent" || host.request.Prompt != "Find TODO references." || host.request.Input["pattern"] != "TODO" {
		t.Fatalf("host request = %#v, want agent, prompt, and input", host.request)
	}
}

// TestRunLiveAgentValidationFailsHostError verifies host errors fail cases.
func TestRunLiveAgentValidationFailsHostError(t *testing.T) {
	result := NewRunnerWithHost(&recordingHost{err: errors.New("runtime failed")}).Run(context.Background(), schema.AgentValidation{
		ID:     "live_error",
		Mode:   "live",
		Prompt: "Answer.",
	})

	if result.Status != StatusFailed || len(result.Diagnostics) != 1 {
		t.Fatalf("Run() = %#v, want host error failure", result)
	}
}

// TestRunSelectedReportsMissingValidationIDs verifies row-level selection errors.
func TestRunSelectedReportsMissingValidationIDs(t *testing.T) {
	agent := schema.Agent{
		Name:        "agent",
		Instruction: "Work.",
		Validations: []schema.AgentValidation{{
			ID:     "known",
			Prompt: "Answer.",
			Mocks: map[string]any{
				"agent.response": map[string]any{"text": "ok"},
			},
		}},
	}

	result, err := NewRunner().RunSelected(context.Background(), agent, []string{"known", "missing"})
	if result.Total != 1 || result.Passed != 1 {
		t.Fatalf("RunSelected() result = %#v, want known validation result", result)
	}
	if _, ok := err.(MissingValidationError); !ok {
		t.Fatalf("RunSelected() error = %T %v, want MissingValidationError", err, err)
	}
}

// TestRunSelectedModesFiltersLiveValidations verifies portable CI selection.
func TestRunSelectedModesFiltersLiveValidations(t *testing.T) {
	agent := schema.Agent{
		Name:        "agent",
		Instruction: "Work.",
		Validations: []schema.AgentValidation{
			{
				ID:     "mocked_case",
				Mode:   "mocked",
				Prompt: "Answer.",
				Mocks: map[string]any{
					"agent.response": map[string]any{"text": "ok"},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:     "response-contains",
					Contains: "ok",
				}},
			},
			{
				ID:     "live_case",
				Mode:   "live",
				Prompt: "Answer live.",
			},
		},
	}

	result, err := NewRunner().RunSelectedModes(context.Background(), agent, nil, "mocked")
	if err != nil {
		t.Fatalf("RunSelectedModes() error = %v", err)
	}
	if result.Total != 1 || result.Passed != 1 || result.Results[0].ID != "mocked_case" {
		t.Fatalf("RunSelectedModes() = %#v, want mocked case only", result)
	}
}

// recordingHost records one live validation request for tests.
type recordingHost struct {
	request  Request
	response Response
	err      error
}

// Respond captures the live request and returns a configured response.
func (h *recordingHost) Respond(_ context.Context, req Request) (Response, error) {
	h.request = req
	return h.response, h.err
}
