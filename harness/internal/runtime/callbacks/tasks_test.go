// This file tests ADK task callback normalization.
package callbacks

import (
	"context"
	"testing"

	"google.golang.org/adk/agent"
	"google.golang.org/adk/memory"
	"google.golang.org/adk/session"
	"google.golang.org/adk/tool/toolconfirmation"
	"google.golang.org/genai"
)

// TestNormalizeCreateTaskFillsSessionScopedIdempotency verifies canonical keys.
func TestNormalizeCreateTaskFillsSessionScopedIdempotency(t *testing.T) {
	args := map[string]any{"title": "Buy milk"}

	if result, err := NormalizeCreateTask(
		testToolContext{Context: context.Background(), sessionID: "session-live"},
		testTool{name: "create_task"},
		args,
	); result != nil || err != nil {
		t.Fatalf("NormalizeCreateTask() = (%#v, %v), want nil result and nil error", result, err)
	}

	if args["description"] != "" {
		t.Fatalf("description = %#v, want normalized empty string", args["description"])
	}
	if args["idempotency_key"] != "agent_awesome:session-live:buy_milk" {
		t.Fatalf("idempotency_key = %#v, want canonical key", args["idempotency_key"])
	}
}

// TestNormalizeCreateTaskDerivesTitleFromDescription covers terse model calls.
func TestNormalizeCreateTaskDerivesTitleFromDescription(t *testing.T) {
	args := map[string]any{"description": "Buy milk"}

	if _, err := NormalizeCreateTask(
		testToolContext{Context: context.Background(), sessionID: "session-live"},
		testTool{name: "create_task"},
		args,
	); err != nil {
		t.Fatalf("NormalizeCreateTask() error = %v", err)
	}

	if args["title"] != "Buy milk" {
		t.Fatalf("title = %#v, want derived title", args["title"])
	}
	if args["idempotency_key"] != "agent_awesome:session-live:buy_milk" {
		t.Fatalf("idempotency_key = %#v, want canonical key", args["idempotency_key"])
	}
}

// TestNormalizeCreateTaskPreservesExplicitIdempotency respects callers.
func TestNormalizeCreateTaskPreservesExplicitIdempotency(t *testing.T) {
	args := map[string]any{"title": "Buy milk", "idempotency_key": "external-key"}

	if _, err := NormalizeCreateTask(
		testToolContext{Context: context.Background(), sessionID: "session-live"},
		testTool{name: "create_task"},
		args,
	); err != nil {
		t.Fatalf("NormalizeCreateTask() error = %v", err)
	}

	if args["idempotency_key"] != "external-key" {
		t.Fatalf("idempotency_key = %#v, want explicit key", args["idempotency_key"])
	}
}

// TestNormalizeCreateTaskIgnoresOtherTools keeps non-task calls untouched.
func TestNormalizeCreateTaskIgnoresOtherTools(t *testing.T) {
	args := map[string]any{"title": "Buy milk"}

	if _, err := NormalizeCreateTask(
		testToolContext{Context: context.Background(), sessionID: "session-live"},
		testTool{name: "remember"},
		args,
	); err != nil {
		t.Fatalf("NormalizeCreateTask() error = %v", err)
	}

	if _, ok := args["idempotency_key"]; ok {
		t.Fatalf("idempotency_key = %#v, want no task key for non-task tool", args["idempotency_key"])
	}
}

type testTool struct {
	name string
}

// Name returns the configured test tool name.
func (t testTool) Name() string { return t.name }

// Description returns a placeholder description for the test tool.
func (t testTool) Description() string { return "test tool" }

// IsLongRunning reports that the test tool is synchronous.
func (t testTool) IsLongRunning() bool { return false }

type testToolContext struct {
	context.Context
	sessionID string
}

// UserContent returns no originating content for callback unit tests.
func (c testToolContext) UserContent() *genai.Content { return nil }

// InvocationID returns a stable test invocation identifier.
func (c testToolContext) InvocationID() string { return "invocation-test" }

// AgentName returns a stable test agent name.
func (c testToolContext) AgentName() string { return "agent_test" }

// ReadonlyState returns no session state for callback unit tests.
func (c testToolContext) ReadonlyState() session.ReadonlyState { return nil }

// UserID returns a stable test user identifier.
func (c testToolContext) UserID() string { return "doug" }

// AppName returns the canonical app identifier.
func (c testToolContext) AppName() string { return "agent_awesome" }

// SessionID returns the configured test session identifier.
func (c testToolContext) SessionID() string { return c.sessionID }

// Branch returns no branch for callback unit tests.
func (c testToolContext) Branch() string { return "" }

// Artifacts returns no artifact store for callback unit tests.
func (c testToolContext) Artifacts() agent.Artifacts { return nil }

// State returns no mutable state for callback unit tests.
func (c testToolContext) State() session.State { return nil }

// FunctionCallID returns a stable test function-call identifier.
func (c testToolContext) FunctionCallID() string { return "function-call-test" }

// Actions returns no event actions for callback unit tests.
func (c testToolContext) Actions() *session.EventActions { return nil }

// SearchMemory returns no memory search results for callback unit tests.
func (c testToolContext) SearchMemory(context.Context, string) (*memory.SearchResponse, error) {
	return nil, nil
}

// ToolConfirmation returns no confirmation state for callback unit tests.
func (c testToolContext) ToolConfirmation() *toolconfirmation.ToolConfirmation { return nil }

// RequestConfirmation accepts no confirmation requests in callback unit tests.
func (c testToolContext) RequestConfirmation(string, any) error { return nil }
