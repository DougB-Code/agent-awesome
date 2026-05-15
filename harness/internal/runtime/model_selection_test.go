// This file tests per-turn model selection applied before LLM calls.
package runtime

import (
	"context"
	"iter"
	"testing"

	"google.golang.org/adk/agent"
	llmapi "google.golang.org/adk/model"
	"google.golang.org/adk/session"
	"google.golang.org/genai"
)

var _ agent.CallbackContext = modelSelectionTestContext{}

// TestModelSelectionCallbackSetsRequestModelFromState verifies UI state reaches
// the ADK request immediately before model routing.
func TestModelSelectionCallbackSetsRequestModelFromState(t *testing.T) {
	callback := modelSelectionCallback()
	request := &llmapi.LLMRequest{}
	ctx := modelSelectionTestContext{
		Context: context.Background(),
		state: modelSelectionState{
			RuntimeModelRefStateKey: "openai:gpt-mini",
		},
	}

	_, err := callback(ctx, request)
	if err != nil {
		t.Fatalf("modelSelectionCallback() error = %v", err)
	}

	if got, want := request.Model, "openai:gpt-mini"; got != want {
		t.Fatalf("request Model = %q, want %q", got, want)
	}
	if got, want := requestStateValue(t, ctx.state, RuntimeModelRefStateKey), "openai:gpt-mini"; got != want {
		t.Fatalf("state model ref = %q, want %q", got, want)
	}
}

// TestModelSelectionCallbackIgnoresMissingState keeps default routing intact
// when a run does not carry a selected model ref.
func TestModelSelectionCallbackIgnoresMissingState(t *testing.T) {
	callback := modelSelectionCallback()
	request := &llmapi.LLMRequest{Model: "local:mini"}

	_, err := callback(modelSelectionTestContext{
		Context: context.Background(),
		state:   modelSelectionState{},
	}, request)
	if err != nil {
		t.Fatalf("modelSelectionCallback() error = %v", err)
	}

	if got, want := request.Model, "local:mini"; got != want {
		t.Fatalf("request Model = %q, want %q", got, want)
	}
}

type modelSelectionTestContext struct {
	context.Context
	state session.State
}

// UserContent returns no user content for model selection tests.
func (c modelSelectionTestContext) UserContent() *genai.Content { return nil }

// InvocationID returns a stable fake invocation id.
func (c modelSelectionTestContext) InvocationID() string { return "invocation" }

// AgentName returns a stable fake agent name.
func (c modelSelectionTestContext) AgentName() string { return "agent" }

// ReadonlyState returns the fake session state.
func (c modelSelectionTestContext) ReadonlyState() session.ReadonlyState {
	return c.state
}

// UserID returns a stable fake user id.
func (c modelSelectionTestContext) UserID() string { return "user" }

// AppName returns a stable fake app name.
func (c modelSelectionTestContext) AppName() string { return "app" }

// SessionID returns a stable fake session id.
func (c modelSelectionTestContext) SessionID() string { return "session" }

// Branch returns the root branch for model selection tests.
func (c modelSelectionTestContext) Branch() string { return "" }

// Artifacts returns no artifact store for model selection tests.
func (c modelSelectionTestContext) Artifacts() agent.Artifacts { return nil }

// State returns the fake mutable session state.
func (c modelSelectionTestContext) State() session.State { return c.state }

type modelSelectionState map[string]any

// Get returns a state value or the ADK missing-key error.
func (s modelSelectionState) Get(key string) (any, error) {
	value, ok := s[key]
	if !ok {
		return nil, session.ErrStateKeyNotExist
	}
	return value, nil
}

// Set stores a state value for callback tests.
func (s modelSelectionState) Set(key string, value any) error {
	s[key] = value
	return nil
}

// All iterates over all fake state values.
func (s modelSelectionState) All() iter.Seq2[string, any] {
	return func(yield func(string, any) bool) {
		for key, value := range s {
			if !yield(key, value) {
				return
			}
		}
	}
}

// requestStateValue reads a fake state value for callback assertions.
func requestStateValue(t *testing.T, state session.State, key string) string {
	t.Helper()
	value, err := state.Get(key)
	if err != nil {
		t.Fatalf("state Get(%q) error = %v", key, err)
	}
	return modelRefValue(value)
}
