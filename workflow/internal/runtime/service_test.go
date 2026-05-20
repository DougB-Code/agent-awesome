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

	"workflow/internal/store"
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
		if err != nil || len(items) != 1 || items[0].RunID != started.ID {
			return false
		}
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusWaiting && run.State == "review"
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

// TestProcessStateAutoTransitionsUsePriorOutputs verifies lifecycle states can advance and pass context.
func TestProcessStateAutoTransitionsUsePriorOutputs(t *testing.T) {
	ctx := context.Background()
	var secondSawPrepare atomic.Bool
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		switch body["name"] {
		case "prepare_tool":
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"worktree_path": "/tmp/worktree"}})
		case "implement_tool":
			arguments, _ := body["arguments"].(map[string]any)
			prepareOutput, _ := arguments["prepare_worktree"].(map[string]any)
			if prepareOutput["worktree_path"] == "/tmp/worktree" {
				secondSawPrepare.Store(true)
			}
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
		default:
			http.Error(w, "unexpected tool", http.StatusBadRequest)
		}
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "lifecycle.yaml", `
kind: state_machine
id: coding_lifecycle
name: Coding Lifecycle
initial: prepare
states:
  - id: prepare
    on_entry:
      - id: prepare_worktree
        uses: tool.call
        with:
          name: prepare_tool
          arguments: {}
    transitions:
      - trigger: succeeded
        to: implement
      - trigger: failed
        to: blocked
  - id: implement
    on_entry:
      - id: implement_change
        uses: tool.call
        with:
          name: implement_tool
          arguments: {}
    transitions:
      - trigger: succeeded
        to: done
      - trigger: failed
        to: blocked
  - id: blocked
  - id: done
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

	started, err := service.StartWorkflow(ctx, "coding_lifecycle", map[string]any{"change_request": "ship it"})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "done"
	})
	if !secondSawPrepare.Load() {
		t.Fatalf("implement state did not receive prepare state output")
	}
}

// TestProcessStateFailureTransition verifies failed entry actions can enter recovery states.
func TestProcessStateFailureTransition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "failure_lifecycle.yaml", `
kind: state_machine
id: failure_lifecycle
name: Failure Lifecycle
initial: check
states:
  - id: check
    on_entry:
      - id: assert_ready
        uses: data.assert
        with:
          path: workflow_input.ready
          mode: equals
          value: true
    transitions:
      - trigger: succeeded
        to: done
      - trigger: failed
        to: blocked
  - id: blocked
  - id: done
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "failure_lifecycle", map[string]any{"ready": false})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "blocked"
	})
	run, err := service.Status(ctx, started.ID)
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if run.Output["error"] == nil {
		t.Fatalf("run output = %#v, want failure error captured", run.Output)
	}
}

// TestHierarchicalStateMachineUsesInitialChildTransition verifies composite targets enter child states.
func TestHierarchicalStateMachineUsesInitialChildTransition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "hierarchy_initial.yaml", `
kind: state_machine
id: hierarchy_initial
name: Hierarchy Initial
initial: intake
states:
  - id: intake
    on_entry:
      - id: assert_intake
        uses: data.assert
        with:
          path: workflow_input.ready
          mode: equals
          value: true
    transitions:
      - trigger: succeeded
        to: change
  - id: change
    initial: implement
    states:
      - id: implement
        on_entry:
          - id: assert_change
            uses: data.assert
            with:
              path: workflow_input.ready
              mode: equals
              value: true
        transitions:
          - trigger: succeeded
            to: done
  - id: done
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "hierarchy_initial", map[string]any{"ready": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "done"
	})
	events, err := service.History(ctx, started.ID)
	if err != nil {
		t.Fatalf("History() error = %v", err)
	}
	if !historyTransitionedTo(events, "implement") {
		t.Fatalf("history = %#v, want transition into composite initial child", events)
	}
}

// TestHierarchicalStateMachineInheritsPhaseTransition verifies child states inherit parent exits.
func TestHierarchicalStateMachineInheritsPhaseTransition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "hierarchy_inherited.yaml", `
kind: state_machine
id: hierarchy_inherited
name: Hierarchy Inherited
initial: quality
states:
  - id: quality
    initial: test
    transitions:
      - trigger: succeeded
        to: publish
      - trigger: failed
        to: blocked
    states:
      - id: test
        on_entry:
          - id: assert_tests
            uses: data.assert
            with:
              path: workflow_input.tests_passed
              mode: equals
              value: true
  - id: publish
  - id: blocked
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "hierarchy_inherited", map[string]any{"tests_passed": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "publish"
	})
}

// TestHierarchicalStateMachineWaitsForInheritedManualTransition verifies phase exits keep child states nonterminal.
func TestHierarchicalStateMachineWaitsForInheritedManualTransition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "hierarchy_manual_exit.yaml", `
kind: state_machine
id: hierarchy_manual_exit
name: Hierarchy Manual Exit
initial: approval
states:
  - id: approval
    initial: await_review
    transitions:
      - trigger: approved
        to: done
      - trigger: rejected
        to: blocked
    states:
      - id: await_review
        on_entry:
          - id: assert_ready
            uses: data.assert
            with:
              path: workflow_input.ready
              mode: equals
              value: true
  - id: done
  - id: blocked
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "hierarchy_manual_exit", map[string]any{"ready": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusWaiting && run.State == "await_review"
	})
	if _, err := service.Signal(ctx, started.ID, "approved", map[string]any{"approved": true}); err != nil {
		t.Fatalf("Signal() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "done"
	})
}

// TestHierarchicalStateMachineDoesNotReenterSharedParent verifies sibling transitions skip parent entry.
func TestHierarchicalStateMachineDoesNotReenterSharedParent(t *testing.T) {
	ctx := context.Background()
	var phaseEntries atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if body["name"] == "phase_tool" {
			phaseEntries.Add(1)
		}
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "hierarchy_parent_entry.yaml", `
kind: state_machine
id: hierarchy_parent_entry
name: Hierarchy Parent Entry
initial: change
states:
  - id: change
    initial: implement
    on_entry:
      - id: phase_entry
        uses: tool.call
        with:
          name: phase_tool
          arguments: {}
    states:
      - id: implement
        on_entry:
          - id: implement_entry
            uses: tool.call
            with:
              name: implement_tool
              arguments: {}
        transitions:
          - trigger: succeeded
            to: review
      - id: review
        on_entry:
          - id: review_entry
            uses: tool.call
            with:
              name: review_tool
              arguments: {}
        transitions:
          - trigger: succeeded
            to: done
  - id: done
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

	started, err := service.StartWorkflow(ctx, "hierarchy_parent_entry", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded && run.State == "done"
	})
	if phaseEntries.Load() != 1 {
		t.Fatalf("phase entry calls = %d, want 1", phaseEntries.Load())
	}
}

// TestTaskStateToolCallUsesHarnessContextAPI verifies tool.call stays harness-owned.
func TestTaskStateToolCallUsesHarnessContextAPI(t *testing.T) {
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
kind: state_machine
id: tool_task_graph
name: Tool Task Graph
states:
  - id: call
    type: task
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

	started, err := service.StartWorkflow(ctx, "tool_task_graph", map[string]any{})
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

// TestTaskStateToolCallReceivesParentOutputs verifies fan-in data reaches child states.
func TestTaskStateToolCallReceivesParentOutputs(t *testing.T) {
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
kind: state_machine
id: fanin_task_graph
name: Fan-in Task Graph
states:
  - id: first
    type: task
    uses: tool.call
    with:
      name: first_tool
      arguments: {}
  - id: second
    type: task
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

	started, err := service.StartWorkflow(ctx, "fanin_task_graph", map[string]any{})
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

// TestTaskStateRetryDelayWaitsBetweenAttempts verifies fixed retry_delay policy.
func TestTaskStateRetryDelayWaitsBetweenAttempts(t *testing.T) {
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
kind: state_machine
id: retry_task_graph
name: Retry Task Graph
states:
  - id: call
    type: task
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
	started, err := service.StartWorkflow(ctx, "retry_task_graph", map[string]any{})
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

// TestTaskStatesRunIndependentBranchesConcurrently verifies ready branches fan out.
func TestTaskStatesRunIndependentBranchesConcurrently(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(150 * time.Millisecond)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "parallel.yaml", `
kind: state_machine
id: parallel_task_graph
name: Parallel Task Graph
states:
  - id: first
    type: task
    uses: tool.call
    with:
      name: first_tool
      arguments: {}
  - id: second
    type: task
    uses: tool.call
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

	start := time.Now()
	started, err := service.StartWorkflow(ctx, "parallel_task_graph", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded
	})
	if elapsed := time.Since(start); elapsed > 280*time.Millisecond {
		t.Fatalf("elapsed = %s, want independent states to run concurrently", elapsed)
	}
}

// TestTaskStateResumeSkipsCompletedSteps verifies completed task states are not rerun.
func TestTaskStateResumeSkipsCompletedSteps(t *testing.T) {
	ctx := context.Background()
	var firstCalls atomic.Int64
	var secondCalls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		switch body["name"] {
		case "first_tool":
			firstCalls.Add(1)
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
		case "second_tool":
			if secondCalls.Add(1) == 1 {
				http.Error(w, "interrupted", http.StatusBadGateway)
				return
			}
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
		default:
			http.Error(w, "unexpected tool", http.StatusBadRequest)
		}
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "resume.yaml", `
kind: state_machine
id: resume_task_graph
name: Resume Task Graph
states:
  - id: first
    type: task
    uses: tool.call
    with:
      name: first_tool
      arguments: {}
  - id: second
    type: task
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

	started, err := service.StartWorkflow(ctx, "resume_task_graph", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusFailed
	})
	if _, err := service.store.DB().ExecContext(ctx, `DELETE FROM workflow_task_states WHERE run_id = ? AND state_id = 'second'`, started.ID); err != nil {
		t.Fatalf("delete interrupted task state = %v", err)
	}
	if err := service.store.UpdateRunState(ctx, started.ID, statusRunning, "running", map[string]any{}); err != nil {
		t.Fatalf("UpdateRunState() error = %v", err)
	}
	service.executeRun(ctx, started.ID)
	run, err := service.Status(ctx, started.ID)
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if run.Status != statusSucceeded {
		t.Fatalf("run status = %q, want succeeded", run.Status)
	}
	if firstCalls.Load() != 1 || secondCalls.Load() != 2 {
		t.Fatalf("calls first=%d second=%d, want first skipped and second retried", firstCalls.Load(), secondCalls.Load())
	}
}

// TestTaskStateDataAssertGatesOnParentOutput verifies generic data gates use task input.
func TestTaskStateDataAssertGatesOnParentOutput(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{
			"plan": map[string]any{"status": "approved"},
		}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "gate.yaml", `
kind: state_machine
id: gated_task_graph
name: Gated Task Graph
states:
  - id: plan
    type: task
    uses: tool.call
    with:
      name: plan_tool
      arguments: {}
  - id: assert_plan
    type: task
    uses: data.assert
    depends_on:
      - plan
    with:
      checks:
        - path: plan.plan.status
          mode: equals
          value: approved
        - path: plan.plan
          mode: schema
          schema:
            type: object
            required:
              - status
            properties:
              status:
                type: string
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

	started, err := service.StartWorkflow(ctx, "gated_task_graph", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusSucceeded
	})
}

// TestTaskStateDataAssertFailureFailsRun verifies failed data gates stop progression.
func TestTaskStateDataAssertFailureFailsRun(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "gate_fail.yaml", `
kind: state_machine
id: failed_gate_task_graph
name: Failed Gate Task Graph
states:
  - id: assert_plan
    type: task
    uses: data.assert
    with:
      path: workflow_input.status
      mode: equals
      value: approved
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "failed_gate_task_graph", map[string]any{"status": "rejected"})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusFailed
	})
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

// historyTransitionedTo reports whether transition history reached one target state.
func historyTransitionedTo(events []store.EventRecord, target string) bool {
	for _, event := range events {
		if event.Type != "state_transitioned" {
			continue
		}
		if event.Data["to"] == target {
			return true
		}
	}
	return false
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
