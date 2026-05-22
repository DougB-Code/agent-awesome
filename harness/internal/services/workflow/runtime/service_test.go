// This file tests durable pipe graph workflow runtime behavior.
package runtime

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/policy"
	"agentawesome/internal/services/workflow/store"
)

// TestPipeGraphHumanNodeWaitsForSignal verifies pending user items resume by signal.
func TestPipeGraphHumanNodeWaitsForSignal(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	dbPath := filepath.Join(t.TempDir(), "workflow.db")
	writeTestDefinition(t, definitionsDir, "approval.yaml", `
kind: workflow
id: approval
name: Approval
nodes:
  - id: review
    type: human
    with:
      prompt: Approve this action?
      payload:
        operation: archive
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   dbPath,
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

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
		return err == nil && run.Status == statusWaiting
	})
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
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	items, err := service.Inbox(ctx)
	if err != nil {
		t.Fatalf("Inbox() error = %v", err)
	}
	if len(items) != 0 {
		t.Fatalf("Inbox() = %#v, want completed pending items hidden", items)
	}
}

// TestWorkflowEventsRedactSignalPayload verifies audit events do not expose credentials.
func TestWorkflowEventsRedactSignalPayload(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "redact.yaml", `
kind: workflow
id: redact_signal
name: Redact Signal
nodes:
  - id: review
    type: human
    with:
      prompt: Approve?
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "redact_signal", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		items, err := service.Inbox(ctx)
		return err == nil && len(items) == 1
	})
	if _, err := service.Signal(ctx, started.ID, "approved", map[string]any{"approved": true, "api_token": "raw-secret"}); err != nil {
		t.Fatalf("Signal() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	events, err := service.History(ctx, started.ID)
	if err != nil {
		t.Fatalf("History() error = %v", err)
	}
	for _, event := range events {
		if event.Type != "signal_received" {
			continue
		}
		payload, _ := event.Data["payload"].(map[string]any)
		if payload["api_token"] != "[REDACTED]" {
			t.Fatalf("signal event payload = %#v, want redacted api_token", payload)
		}
		return
	}
	t.Fatalf("signal_received event not found in %#v", events)
}

// TestContainsSensitiveKeyDetectsCredentials verifies pending payload filtering.
func TestContainsSensitiveKeyDetectsCredentials(t *testing.T) {
	payload := map[string]any{
		"form": map[string]any{
			"username_field": "email",
			"password":       "raw-secret",
		},
	}

	if !policy.ContainsSensitiveKey(payload) {
		t.Fatalf("ContainsSensitiveKey() = false, want credential-like key detected")
	}
}

// TestPipeGraphToolCallUsesHarnessContextAPI verifies tool.call stays harness-owned.
func TestPipeGraphToolCallUsesHarnessContextAPI(t *testing.T) {
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
kind: workflow
id: tool_workflow
name: Tool Workflow
nodes:
  - id: call
    type: tool
    tool: mock_tool
    with:
      arguments:
        subject: hello
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "tool_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if received.Load() != 1 {
		t.Fatalf("tool calls = %d, want 1", received.Load())
	}
}

// TestPipeGraphRecordsObservedContracts verifies successful node outputs become reviewable contracts.
func TestPipeGraphRecordsObservedContracts(t *testing.T) {
	ctx := context.Background()
	var total atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		next := total.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{
			"customer": map[string]any{"email": "billing@example.test"},
			"total":    float64(next),
		}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "observe.yaml", `
kind: workflow
id: observe_contract
name: Observe Contract
nodes:
  - id: fetch
    type: tool
    tool: fetch_invoice
    with:
      arguments: {}
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	for i := 0; i < 3; i++ {
		started, err := service.StartWorkflow(ctx, "observe_contract", map[string]any{})
		if err != nil {
			t.Fatalf("StartWorkflow() error = %v", err)
		}
		waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	}
	observed, err := service.ListObservedContracts(ctx, ObservedContractQuery{
		DefinitionID: "observe_contract",
		NodeID:       "fetch",
	})
	if err != nil {
		t.Fatalf("ListObservedContracts() error = %v", err)
	}
	if len(observed) != 1 {
		t.Fatalf("observed contracts = %#v, want one merged shape", observed)
	}
	if observed[0].Occurrences != 3 || !observed[0].ReviewRecommended {
		t.Fatalf("observed = %#v, want three occurrences and review recommendation", observed[0])
	}
	if len(observed[0].ObservedFields) == 0 {
		t.Fatalf("observed fields empty, want inferred field paths")
	}
}

// TestPipeGraphLLMNodeRequiresStructuredSchema verifies model nodes stay schema-constrained.
func TestPipeGraphLLMNodeRequiresStructuredSchema(t *testing.T) {
	ctx := context.Background()
	llm := &recordingWorkflowLLM{response: map[string]any{
		"status": "succeeded",
		"result": map[string]any{"summary": "invoice"},
	}}
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "llm.yaml", `
kind: workflow
id: llm_workflow
name: LLM Workflow
nodes:
  - id: classify
    type: llm
    with:
      prompt: "Classify ${body.value.subject}"
      output_schema:
        type: object
        required:
          - status
          - result
        properties:
          status:
            type: string
          result:
            type: object
    output:
      schema:
        type: object
        required:
          - status
          - result
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		LLMClient:      llm,
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "llm_workflow", map[string]any{"subject": "Invoice", "api_token": "raw-secret"})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if len(llm.requests) != 1 {
		t.Fatalf("llm requests = %d, want 1", len(llm.requests))
	}
	if llm.requests[0].Prompt != "Classify Invoice" {
		t.Fatalf("prompt = %q, want resolved input reference", llm.requests[0].Prompt)
	}
	if len(llm.requests[0].OutputSchema) == 0 {
		t.Fatalf("output schema was not passed to LLM boundary")
	}
	encodedInput, err := json.Marshal(llm.requests[0].Input)
	if err != nil {
		t.Fatalf("Marshal(input) error = %v", err)
	}
	if strings.Contains(string(encodedInput), "raw-secret") {
		t.Fatalf("LLM input contains unredacted secret: %s", encodedInput)
	}
}

// TestPipeGraphMappingAdapterFeedsToolArguments verifies node outputs flow through deterministic mappings.
func TestPipeGraphMappingAdapterFeedsToolArguments(t *testing.T) {
	ctx := context.Background()
	var sawRecipient atomic.Bool
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		switch body["name"] {
		case "fetch_customer":
			writeJSON(w, map[string]any{"structuredContent": map[string]any{
				"customer": map[string]any{"email": "billing@example.test"},
			}})
		case "send_email":
			arguments, _ := body["arguments"].(map[string]any)
			if arguments["recipient"] == "billing@example.test" {
				sawRecipient.Store(true)
			}
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"sent": true}})
		default:
			http.Error(w, "unexpected tool", http.StatusBadRequest)
		}
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "pipe_mapping.yaml", `
kind: workflow
id: pipe_mapping
name: Pipe Mapping
nodes:
  - id: fetch
    type: tool
    tool: fetch_customer
    with:
      arguments: {}
  - id: send
    type: tool
    tool: send_email
    with:
      arguments: "${body.value}"
edges:
  - from:
      node: fetch
    to:
      node: send
    adapter:
      kind: mapping
      mapping:
        name: customer-to-recipient
        steps:
          - set:
              target: recipient
              value:
                path: input.body.value.customer.email
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "pipe_mapping", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if !sawRecipient.Load() {
		t.Fatalf("send_email did not receive mapped recipient")
	}
}

// TestPipeGraphDecisionNodeSkipsInactiveBranch verifies ordered route choices activate one branch.
func TestPipeGraphDecisionNodeSkipsInactiveBranch(t *testing.T) {
	ctx := context.Background()
	var managerCalls atomic.Int64
	var autoCalls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		switch body["name"] {
		case "manager_tool":
			managerCalls.Add(1)
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"approved_by": "manager"}})
		case "auto_tool":
			autoCalls.Add(1)
			writeJSON(w, map[string]any{"structuredContent": map[string]any{"approved_by": "auto"}})
		default:
			http.Error(w, "unexpected tool", http.StatusBadRequest)
		}
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "decision.yaml", `
kind: workflow
id: decision_workflow
name: Decision Workflow
nodes:
  - id: choose
    type: decision
    with:
      rules:
        - id: manager_amount
          route: manager
          when:
            expr: input.body.value.amount > 1000
      default: auto
  - id: manager
    type: tool
    tool: manager_tool
    with:
      arguments: {}
  - id: auto
    type: tool
    tool: auto_tool
    with:
      arguments: {}
edges:
  - from:
      node: choose
    to:
      node: manager
    when:
      expr: input.facets["decision.route"] == "manager"
  - from:
      node: choose
    to:
      node: auto
    when:
      expr: input.facets["decision.route"] == "auto"
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "decision_workflow", map[string]any{"amount": float64(1500)})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if managerCalls.Load() != 1 || autoCalls.Load() != 0 {
		t.Fatalf("calls manager=%d auto=%d, want only manager branch", managerCalls.Load(), autoCalls.Load())
	}
	states, err := service.store.ListNodeStates(ctx, started.ID)
	if err != nil {
		t.Fatalf("ListNodeStates() error = %v", err)
	}
	statuses := nodeStatusByID(states)
	if statuses["manager"].Status != statusSucceeded || statuses["auto"].Status != statusSkipped {
		t.Fatalf("branch statuses manager=%q auto=%q, want succeeded/skipped", statuses["manager"].Status, statuses["auto"].Status)
	}
	dot, ok := service.DefinitionDOT("decision_workflow")
	if !ok || !strings.Contains(dot, `"choose" -> "manager"`) || !strings.Contains(dot, `decision.route`) {
		t.Fatalf("DefinitionDOT() = %q ok=%v, want decision graph", dot, ok)
	}
}

// TestPipeGraphRateLimitBlocksExcessInvocations verifies runtime rate policy is enforced.
func TestPipeGraphRateLimitBlocksExcessInvocations(t *testing.T) {
	ctx := context.Background()
	var calls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "rate_limit.yaml", `
kind: workflow
id: rate_limit_workflow
name: Rate Limit Workflow
nodes:
  - id: first
    type: tool
    tool: shared_tool
    runtime:
      rate_limit_per_minute: 1
    with:
      arguments: {}
  - id: second
    type: tool
    tool: shared_tool
    runtime:
      rate_limit_per_minute: 1
    with:
      arguments: {}
edges:
  - from:
      node: first
    to:
      node: second
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "rate_limit_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
	if calls.Load() != 1 {
		t.Fatalf("tool calls = %d, want one invocation before rate block", calls.Load())
	}
}

// TestPipeGraphRejectsSandboxBoundaryMismatch verifies runtime policy cannot claim a false sandbox.
func TestPipeGraphRejectsSandboxBoundaryMismatch(t *testing.T) {
	ctx := context.Background()
	var calls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "sandbox_mismatch.yaml", `
kind: workflow
id: sandbox_mismatch
name: Sandbox Mismatch
nodes:
  - id: call
    type: tool
    tool: network_tool
    runtime:
      sandbox: aa-runtime
    with:
      arguments: {}
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "sandbox_mismatch", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
	if calls.Load() != 0 {
		t.Fatalf("tool calls = %d, want sandbox mismatch to block before invocation", calls.Load())
	}
}

// TestPipeGraphRetryDelayWaitsBetweenAttempts verifies fixed retry_delay policy.
func TestPipeGraphRetryDelayWaitsBetweenAttempts(t *testing.T) {
	ctx := context.Background()
	var attempts atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if attempts.Add(1) == 1 {
			http.Error(w, "not ready", http.StatusBadGateway)
			return
		}
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "retry.yaml", `
kind: workflow
id: retry_workflow
name: Retry Workflow
nodes:
  - id: call
    type: tool
    tool: mock_tool
    retry: 1
    retry_delay: 50ms
    with:
      arguments: {}
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	start := time.Now()
	started, err := service.StartWorkflow(ctx, "retry_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if attempts.Load() != 2 {
		t.Fatalf("tool attempts = %d, want 2", attempts.Load())
	}
	if elapsed := time.Since(start); elapsed < 45*time.Millisecond {
		t.Fatalf("elapsed = %s, want retry delay honored", elapsed)
	}
}

// TestPipeGraphRunsIndependentBranchesConcurrently verifies ready branches fan out.
func TestPipeGraphRunsIndependentBranchesConcurrently(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(150 * time.Millisecond)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "parallel.yaml", `
kind: workflow
id: parallel_workflow
name: Parallel Workflow
nodes:
  - id: first
    type: tool
    tool: first_tool
    with:
      arguments: {}
  - id: second
    type: tool
    tool: second_tool
    with:
      arguments: {}
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	start := time.Now()
	started, err := service.StartWorkflow(ctx, "parallel_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if elapsed := time.Since(start); elapsed > 280*time.Millisecond {
		t.Fatalf("elapsed = %s, want independent nodes to run concurrently", elapsed)
	}
}

// TestPipeGraphResumeSkipsCompletedNodes verifies completed nodes are not rerun.
func TestPipeGraphResumeSkipsCompletedNodes(t *testing.T) {
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
kind: workflow
id: resume_workflow
name: Resume Workflow
nodes:
  - id: first
    type: tool
    tool: first_tool
    with:
      arguments: {}
  - id: second
    type: tool
    tool: second_tool
    with:
      arguments: {}
edges:
  - from:
      node: first
    to:
      node: second
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "resume_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
	if _, err := service.store.DB().ExecContext(ctx, `DELETE FROM workflow_node_states WHERE run_id = ? AND state_id = 'second'`, started.ID); err != nil {
		t.Fatalf("delete interrupted node state = %v", err)
	}
	if err := service.store.UpdateRunState(ctx, started.ID, statusRunning, statusRunning, map[string]any{}); err != nil {
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

// TestPipeGraphDataAssertGatesOnParentOutput verifies generic data gates use envelope input.
func TestPipeGraphDataAssertGatesOnParentOutput(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{
			"plan": map[string]any{"status": "approved"},
		}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "gate.yaml", `
kind: workflow
id: gated_workflow
name: Gated Workflow
nodes:
  - id: plan
    type: tool
    tool: plan_tool
    with:
      arguments: {}
  - id: assert_plan
    type: assert
    with:
      checks:
        - path: body.value.plan.status
          mode: equals
          value: approved
        - path: body.value.plan
          mode: schema
          schema:
            type: object
            required:
              - status
            properties:
              status:
                type: string
edges:
  - from:
      node: plan
    to:
      node: assert_plan
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "gated_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
}

// TestPipeGraphDataAssertFailureFailsRun verifies failed data gates stop progression.
func TestPipeGraphDataAssertFailureFailsRun(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "gate_fail.yaml", `
kind: workflow
id: failed_gate_workflow
name: Failed Gate Workflow
nodes:
  - id: assert_plan
    type: assert
    with:
      path: body.value.status
      mode: equals
      value: approved
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "failed_gate_workflow", map[string]any{"status": "rejected"})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
}

// TestPipeGraphContractsRejectMissingFacet verifies declared contracts gate unsafe composition.
func TestPipeGraphContractsRejectMissingFacet(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "contract_gate.yaml", `
kind: workflow
id: contract_gate
name: Contract Gate
nodes:
  - id: source
    type: tool
    tool: source_tool
    with:
      arguments: {}
  - id: target
    type: tool
    tool: target_tool
    input:
      required_facets:
        - customer.email
    with:
      arguments: {}
edges:
  - from:
      node: source
    to:
      node: target
    adapter:
      kind: direct
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "contract_gate", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
}

// TestPipeGraphPolicyBlocksUntrustedNetworkEffects verifies edge safety is enforced before invocation.
func TestPipeGraphPolicyBlocksUntrustedNetworkEffects(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{
			"facets": map[string]any{"trust.level": "untrusted"},
		}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "policy_gate.yaml", `
kind: workflow
id: policy_gate
name: Policy Gate
nodes:
  - id: source
    uses: data.assert
    with:
      path: body.value.ready
      mode: equals
      value: true
  - id: target
    type: tool
    tool: network_tool
    effects:
      network:
        allowed_hosts:
          - example.com
    with:
      arguments: {}
edges:
  - from:
      node: source
    to:
      node: target
    adapter:
      kind: mapping
      mapping:
        name: trust-marker
        steps:
          - set:
              target: output.facets.trust.level
              value:
                value: untrusted
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "policy_gate", map[string]any{"ready": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
}

// TestPipeGraphPolicyApprovalGatePausesBeforeEffects verifies confirmation-required effects wait.
func TestPipeGraphPolicyApprovalGatePausesBeforeEffects(t *testing.T) {
	ctx := context.Background()
	var calls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"sent": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "approval_gate.yaml", `
kind: workflow
id: approval_gate
name: Approval Gate
nodes:
  - id: send
    type: tool
    tool: send_email
    effects:
      user_confirmation:
        required_for:
          - send_email
    with:
      arguments: {}
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "approval_gate", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		items, inboxErr := service.Inbox(ctx)
		return err == nil && inboxErr == nil && run.Status == statusWaiting && len(items) == 1 && calls.Load() == 0
	})
	if _, err := service.Signal(ctx, started.ID, "approved", map[string]any{"approved": true}); err != nil {
		t.Fatalf("Signal() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	if calls.Load() != 1 {
		t.Fatalf("tool calls = %d, want one call after approval", calls.Load())
	}
}

// TestPipeGraphRuntimeMaxInputBytesBlocksInvocation verifies runtime input limits.
func TestPipeGraphRuntimeMaxInputBytesBlocksInvocation(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"called": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "input_limit.yaml", `
kind: workflow
id: input_limit
name: Input Limit
nodes:
  - id: gate
    uses: data.assert
    runtime:
      max_input_bytes: 10
    with:
      path: body.value.payload
      mode: exists
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "input_limit", map[string]any{"payload": "this input is too large"})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
}

// TestPipeGraphRuntimeMaxArtifactBytesBlocksOversizedOutput verifies artifact limits.
func TestPipeGraphRuntimeMaxArtifactBytesBlocksOversizedOutput(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{
			"meta": map[string]any{
				"schema_ref": "aa.workflow.envelope.v1",
				"created_at": "2026-05-22T00:00:00Z",
			},
			"body": map[string]any{"kind": "file", "value": map[string]any{"uri": "file:///tmp/big.pdf"}},
			"artifacts": []any{
				map[string]any{"id": "big_pdf", "media_type": "application/pdf", "size": float64(64), "uri": "file:///tmp/big.pdf"},
			},
			"control": map[string]any{"status": "succeeded"},
		}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "artifact_limit.yaml", `
kind: workflow
id: artifact_limit
name: Artifact Limit
nodes:
  - id: fetch
    type: tool
    tool: fetch_pdf
    runtime:
      max_artifact_bytes: 16
    with:
      arguments: {}
`)
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "artifact_limit", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
}

// openTestService opens a workflow service for runtime tests.
func openTestService(t *testing.T, ctx context.Context, definitionsDir string, contextURL string) *Service {
	t.Helper()
	service, err := Open(ctx, Config{
		DefinitionsDir:        definitionsDir,
		DatabasePath:          filepath.Join(t.TempDir(), "workflow.db"),
		HarnessContextBaseURL: contextURL,
		RequestTimeout:        time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	return service
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

// waitForRunStatus waits for a workflow run to reach one status and reports history on failure.
func waitForRunStatus(t *testing.T, ctx context.Context, service *Service, runID string, want string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	var run store.RunRecord
	var err error
	for time.Now().Before(deadline) {
		run, err = service.Status(ctx, runID)
		if err == nil && run.Status == want {
			return
		}
		if err == nil && (run.Status == statusFailed || run.Status == statusCanceled) {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	events, _ := service.History(ctx, runID)
	t.Fatalf("run status = %#v err=%v, want %q; history=%#v", run, err, want, events)
}

// recordingWorkflowLLM captures schema-constrained model requests for runtime tests.
type recordingWorkflowLLM struct {
	requests []actions.LLMRequest
	response map[string]any
}

// GenerateWorkflowJSON records a model request and returns fixed JSON output.
func (l *recordingWorkflowLLM) GenerateWorkflowJSON(_ context.Context, req actions.LLMRequest) (map[string]any, error) {
	l.requests = append(l.requests, req)
	return l.response, nil
}
