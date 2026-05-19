// This file tests durable workflow runtime behavior.
package runtime

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

// TestStateMachineWaitsForHumanSignal verifies pending user items resume by signal.
func TestStateMachineWaitsForHumanSignal(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	dbPath := filepath.Join(t.TempDir(), "workflow.db")
	writeTestDefinition(t, definitionsDir, "approval.yaml", `
kind: state_machine
id: approval
name: Approval
initial: review
states:
  - id: review
    on_entry:
      - id: ask
        uses: human.request
        with:
          prompt: Approve this action?
          payload:
            operation: archive
    transitions:
      - trigger: approve
        to: done
  - id: done
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   dbPath,
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "approval", map[string]any{"subject": "hello"})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}

	eventually(t, func() bool {
		items, err := service.Inbox(ctx)
		return err == nil && len(items) == 1 && items[0].RunID == started.ID
	})
	waiting, err := service.Status(ctx, started.ID)
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if waiting.Status != statusWaiting || waiting.State != "review" {
		t.Fatalf("waiting run = %#v, want waiting review state", waiting)
	}

	if err := service.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
	service, err = Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   dbPath,
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("reopen Open() error = %v", err)
	}
	defer service.Close()

	if _, err := service.Signal(ctx, started.ID, "approve", map[string]any{"approved": true}); err != nil {
		t.Fatalf("Signal() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "done"
	})
	items, err := service.Inbox(ctx)
	if err != nil {
		t.Fatalf("Inbox() error = %v", err)
	}
	if len(items) != 0 {
		t.Fatalf("Inbox() = %#v, want completed pending items hidden", items)
	}
}

// TestContainsSensitiveKeyDetectsCredentials verifies pending payload filtering.
func TestContainsSensitiveKeyDetectsCredentials(t *testing.T) {
	payload := map[string]any{
		"form": map[string]any{
			"username_field": "email",
			"password":       "raw-secret",
		},
	}

	if !containsSensitiveKey(payload) {
		t.Fatalf("containsSensitiveKey() = false, want credential-like key detected")
	}
}

// TestDAGToolCallUsesHarnessContextAPI verifies tool.call stays harness-owned.
func TestDAGToolCallUsesHarnessContextAPI(t *testing.T) {
	ctx := context.Background()
	var received atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/context/tools/call" {
			t.Fatalf("request path = %q, want /api/context/tools/call", r.URL.Path)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		if body["name"] != "mock_tool" {
			t.Fatalf("tool name = %#v, want mock_tool", body["name"])
		}
		received.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "tool.yaml", `
kind: dag
id: tool_dag
name: Tool DAG
nodes:
  - id: call
    uses: tool.call
    with:
      name: mock_tool
      arguments:
        subject: hello
`)
	service, err := Open(ctx, Config{
		DefinitionsDir:        definitionsDir,
		DatabasePath:          filepath.Join(t.TempDir(), "workflow.db"),
		HarnessContextBaseURL: toolServer.URL + "/api/context",
		RequestTimeout:        time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "tool_dag", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded
	})
	if received.Load() != 1 {
		t.Fatalf("tool calls = %d, want 1", received.Load())
	}
}

// TestDAGToolCallReceivesParentOutputs verifies fan-in data reaches child nodes.
func TestDAGToolCallReceivesParentOutputs(t *testing.T) {
	ctx := context.Background()
	var secondSawParent atomic.Bool
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		switch body["name"] {
		case "first_tool":
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"result": "ready"}})
		case "second_tool":
			arguments, _ := body["arguments"].(map[string]any)
			parentOutput, _ := arguments["first"].(map[string]any)
			if parentOutput["result"] == "ready" {
				secondSawParent.Store(true)
			}
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
		default:
			http.Error(w, "unexpected tool", http.StatusBadRequest)
		}
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "fanin.yaml", `
kind: dag
id: fanin_dag
name: Fan-in DAG
nodes:
  - id: first
    uses: tool.call
    with:
      name: first_tool
      arguments: {}
  - id: second
    uses: tool.call
    depends_on:
      - first
    with:
      name: second_tool
      arguments: {}
`)
	service, err := Open(ctx, Config{
		DefinitionsDir:        definitionsDir,
		DatabasePath:          filepath.Join(t.TempDir(), "workflow.db"),
		HarnessContextBaseURL: toolServer.URL + "/api/context",
		RequestTimeout:        time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "fanin_dag", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded
	})
	if !secondSawParent.Load() {
		t.Fatalf("second tool did not receive first node output")
	}
}

// TestDAGRetryDelayWaitsBetweenAttempts verifies fixed retry_delay policy.
func TestDAGRetryDelayWaitsBetweenAttempts(t *testing.T) {
	ctx := context.Background()
	var attempts atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if attempts.Add(1) == 1 {
			http.Error(w, "not ready", http.StatusBadGateway)
			return
		}
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "retry.yaml", `
kind: dag
id: retry_dag
name: Retry DAG
nodes:
  - id: call
    uses: tool.call
    retry: 1
    retry_delay: 50ms
    with:
      name: mock_tool
      arguments: {}
`)
	service, err := Open(ctx, Config{
		DefinitionsDir:        definitionsDir,
		DatabasePath:          filepath.Join(t.TempDir(), "workflow.db"),
		HarnessContextBaseURL: toolServer.URL + "/api/context",
		RequestTimeout:        time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	start := time.Now()
	started, err := service.StartWorkflow(ctx, "retry_dag", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded
	})
	if attempts.Load() != 2 {
		t.Fatalf("tool attempts = %d, want 2", attempts.Load())
	}
	if elapsed := time.Since(start); elapsed < 45*time.Millisecond {
		t.Fatalf("elapsed = %s, want retry delay honored", elapsed)
	}
}

// writeTestDefinition writes one YAML workflow definition for a runtime test.
func writeTestDefinition(t *testing.T, dir string, name string, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
}

// writeJSON encodes a JSON test response.
func writeJSON(w http.ResponseWriter, body map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}

// eventually waits for asynchronous workflow execution to reach a condition.
func eventually(t *testing.T, check func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if check() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("condition was not met before timeout")
}
