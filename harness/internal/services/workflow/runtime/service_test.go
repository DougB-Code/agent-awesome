// This file tests durable state-machine workflow runtime behavior.
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
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/policy"
	"agentawesome/internal/services/workflow/store"
)

// TestStateMachineHumanActionWaitsForSignal verifies pending user items resume by signal.
func TestStateMachineHumanActionWaitsForSignal(t *testing.T) {
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
      - id: review_request
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

// TestOpenSkipsInvalidDefinitionsWhenConfigured verifies embedded hosts can start while invalid workflow files are quarantined.
func TestOpenSkipsInvalidDefinitionsWhenConfigured(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "old.yaml", `
kind: legacy_state_machine
id: old_flow
initial: start
states:
  - id: start
`)
	writeTestDefinition(t, definitionsDir, "valid.yaml", `
kind: state_machine
id: valid_flow
name: Valid Flow
initial: start
states:
  - id: start
    on_entry:
      - id: assert_input
        type: assert
        with:
          path: workflow_input.ready
          mode: exists
`)
	service, err := Open(ctx, Config{
		DefinitionsDir:         definitionsDir,
		DatabasePath:           filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout:         time.Second,
		SkipInvalidDefinitions: true,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()
	if _, ok := service.DescribeDefinition("valid_flow"); !ok {
		t.Fatalf("valid_flow was not loaded")
	}
	if _, ok := service.DescribeDefinition("old_flow"); ok {
		t.Fatalf("old_flow loaded, want invalid state_machine definition skipped")
	}
	if warnings := service.DefinitionWarnings(); len(warnings) != 1 {
		t.Fatalf("DefinitionWarnings() = %#v, want one skipped definition", warnings)
	}
}

// TestDeleteDraftRemovesMirroredWorkflowFile verifies deleting a workflow file removes it from disk.
func TestDeleteDraftRemovesMirroredWorkflowFile(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	writeTestDefinition(t, definitionsDir, "copied.yaml", `
kind: state_machine
id: copied_workflow
name: Copied Workflow
initial: review
states:
  - id: review
    on_entry:
      - id: review_request
        type: human
        with:
          prompt: Review copied workflow
`)

	defs, err := service.ListDefinitions(ctx)
	if err != nil {
		t.Fatalf("ListDefinitions() error = %v", err)
	}
	if len(defs) != 1 || defs[0].ID != "copied_workflow" {
		t.Fatalf("ListDefinitions() = %#v, want copied_workflow", defs)
	}
	drafts, err := service.ListDrafts(ctx)
	if err != nil {
		t.Fatalf("ListDrafts() error = %v", err)
	}
	if len(drafts) != 1 || drafts[0].ID != "draft_copied_workflow" {
		t.Fatalf("ListDrafts() = %#v, want draft_copied_workflow", drafts)
	}
	if err := service.DeleteDraft(ctx, "draft_copied_workflow"); err != nil {
		t.Fatalf("DeleteDraft() error = %v", err)
	}
	if _, err := os.Stat(filepath.Join(definitionsDir, "copied.yaml")); !os.IsNotExist(err) {
		t.Fatalf("definition file after DeleteDraft() error = %v, want missing", err)
	}
	drafts, err = service.ListDrafts(ctx)
	if err != nil {
		t.Fatalf("ListDrafts() after delete error = %v", err)
	}
	if len(drafts) != 0 {
		t.Fatalf("ListDrafts() after delete = %#v, want no drafts", drafts)
	}
	defs, err = service.ListDefinitions(ctx)
	if err != nil {
		t.Fatalf("ListDefinitions() after delete error = %v", err)
	}
	if len(defs) != 0 {
		t.Fatalf("ListDefinitions() after delete = %#v, want no definitions", defs)
	}
}

// TestListDraftsRemovesStalePublishedDefinitionDrafts verifies deployed files drive the file picker.
func TestListDraftsRemovesStalePublishedDefinitionDrafts(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	writeTestDefinition(t, definitionsDir, "old.yaml", `
kind: state_machine
id: old_workflow
name: Old Workflow
initial: review
states:
  - id: review
    on_entry:
      - id: review_request
        type: human
        with:
          prompt: Review old workflow
`)
	if _, err := service.ListDrafts(ctx); err != nil {
		t.Fatalf("ListDrafts() error = %v", err)
	}
	if err := os.Remove(filepath.Join(definitionsDir, "old.yaml")); err != nil {
		t.Fatalf("Remove() error = %v", err)
	}
	writeTestDefinition(t, definitionsDir, "new.yaml", `
kind: state_machine
id: new_workflow
name: New Workflow
initial: intake
states:
  - id: intake
    on_entry:
      - id: assert_input
        uses: data.assert
        with:
          path: workflow_input.ready
          mode: exists
`)
	drafts, err := service.ListDrafts(ctx)
	if err != nil {
		t.Fatalf("ListDrafts() error = %v", err)
	}
	if len(drafts) != 1 || drafts[0].ID != "draft_new_workflow" {
		t.Fatalf("ListDrafts() = %#v, want only draft_new_workflow", drafts)
	}
	if drafts[0].Kind != draftKindWorkflow {
		t.Fatalf("draft kind = %q, want workflow", drafts[0].Kind)
	}
	if got := strings.TrimSpace(stringFromMap(drafts[0].Body, "kind", "")); got != definition.KindStateMachine {
		t.Fatalf("draft body kind = %q, want state_machine", got)
	}
}

// TestUpdateWorkflowDraftPreservesStateMachineBodyKind verifies authoring kind does not rewrite runtime kind.
func TestUpdateWorkflowDraftPreservesStateMachineBodyKind(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	draft, err := service.CreateDraft(ctx, DraftRequest{
		Kind: draftKindWorkflow,
		Name: "State Machine Workflow",
		Body: map[string]any{
			"kind":    definition.KindStateMachine,
			"id":      "state_machine_workflow",
			"initial": "start",
			"states": []any{
				map[string]any{"id": "start"},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}
	updated, err := service.UpdateDraft(ctx, draft.ID, DraftRequest{
		Kind:        draftKindWorkflow,
		Name:        "Renamed State Machine Workflow",
		Description: draft.Description,
		Body:        draft.Body,
	})
	if err != nil {
		t.Fatalf("UpdateDraft() error = %v", err)
	}
	if updated.Kind != draftKindWorkflow {
		t.Fatalf("draft kind = %q, want workflow", updated.Kind)
	}
	if got := strings.TrimSpace(stringFromMap(updated.Body, "kind", "")); got != definition.KindStateMachine {
		t.Fatalf("draft body kind = %q, want state_machine", got)
	}
}

// TestStartWorkflowReloadsCopiedDefinition verifies copied workflows can run before the UI refreshes.
func TestStartWorkflowReloadsCopiedDefinition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	writeTestDefinition(t, definitionsDir, "runnable.yaml", `
kind: state_machine
id: runnable_copy
name: Runnable Copy
initial: review
states:
  - id: review
    on_entry:
      - id: review_request
        type: human
        with:
          prompt: Review runnable copy
`)

	started, err := service.StartWorkflow(ctx, "runnable_copy", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	if started.DefinitionID != "runnable_copy" {
		t.Fatalf("StartWorkflow() definition = %q, want runnable_copy", started.DefinitionID)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusWaiting
	})
}

// TestRunSetupStartsWorkflowWithMergedInput verifies reusable setup input is applied.
func TestRunSetupStartsWorkflowWithMergedInput(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "setup.yaml", `
kind: state_machine
id: setup_flow
name: Setup Flow
initial: done
states:
  - id: done
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	setup, err := service.CreateRunSetup(ctx, RunSetupRequest{
		DefinitionID: "setup_flow",
		Name:         "Repository setup",
		Input: map[string]any{
			"repository_path": "/repo",
			"remote":          "origin",
		},
	})
	if err != nil {
		t.Fatalf("CreateRunSetup() error = %v", err)
	}
	started, err := service.StartRunSetup(ctx, setup.ID, map[string]any{
		"change_request": "Fix one bug",
	})
	if err != nil {
		t.Fatalf("StartRunSetup() error = %v", err)
	}
	if started.Input["repository_path"] != "/repo" || started.Input["change_request"] != "Fix one bug" {
		t.Fatalf("run input = %#v, want setup and run inputs merged", started.Input)
	}
}

// TestStateMachineRunsNestedEntryActions verifies hierarchical states execute parent and child actions.
func TestStateMachineRunsNestedEntryActions(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "hierarchical.yaml", `
kind: state_machine
id: hierarchical_flow
name: Hierarchical Flow
initial: parent
states:
  - id: parent
    initial: child
    on_entry:
      - id: parent_assert
        uses: data.assert
        with:
          path: workflow_input.ready
          mode: equals
          value: true
    states:
      - id: child
        on_entry:
          - id: child_assert
            uses: data.assert
            with:
              path: parent_assert.passed
              mode: equals
              value: true
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "hierarchical_flow", map[string]any{"ready": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	states, err := service.store.ListNodeStates(ctx, started.ID)
	if err != nil {
		t.Fatalf("ListNodeStates() error = %v", err)
	}
	statuses := nodeStatusByID(states)
	if statuses["parent_assert"].Status != statusSucceeded || statuses["child_assert"].Status != statusSucceeded {
		t.Fatalf("node statuses = %#v, want parent and child succeeded", statuses)
	}
}

// TestStateMachineFollowsSucceededTransitions verifies authored state triggers use public status names.
func TestStateMachineFollowsSucceededTransitions(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "transition.yaml", `
kind: state_machine
id: transition_flow
name: Transition Flow
initial: first
states:
  - id: first
    on_entry:
      - id: first_assert
        uses: data.assert
        with:
          path: workflow_input.ready
          mode: equals
          value: true
    transitions:
      - trigger: succeeded
        to: second
  - id: second
    on_entry:
      - id: second_assert
        uses: data.assert
        with:
          path: first_assert.passed
          mode: equals
          value: true
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "transition_flow", map[string]any{"ready": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	run, err := service.Status(ctx, started.ID)
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if run.State != "second" {
		t.Fatalf("run state = %q, want second", run.State)
	}
	if _, ok, err := service.store.GetNodeState(ctx, started.ID, "second_assert"); err != nil {
		t.Fatalf("GetNodeState() error = %v", err)
	} else if !ok {
		t.Fatalf("second_assert did not execute")
	}
}

// TestStateMachineFollowsDecisionRouteTransitions verifies custom route triggers drive state transitions.
func TestStateMachineFollowsDecisionRouteTransitions(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "decision_transition.yaml", `
kind: state_machine
id: decision_transition_flow
name: Decision Transition Flow
initial: route
states:
  - id: route
    on_entry:
      - id: choose_route
        uses: decision.route
        with:
          default: needs_review
          rules:
            - id: auto_rule
              route: auto_approved
              when:
                path: workflow_input.auto
    transitions:
      - trigger: auto_approved
        to: auto_done
      - trigger: needs_review
        to: review
  - id: auto_done
    on_entry:
      - id: auto_assert
        uses: data.assert
        with:
          path: workflow_input.auto
          mode: equals
          value: true
  - id: review
    on_entry:
      - id: review_assert
        uses: data.assert
        with:
          path: workflow_input.auto
          mode: equals
          value: false
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "decision_transition_flow", map[string]any{"auto": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	run, err := service.Status(ctx, started.ID)
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if run.State != "auto_done" {
		t.Fatalf("run state = %q, want auto_done", run.State)
	}
	if _, ok, err := service.store.GetNodeState(ctx, started.ID, "auto_assert"); err != nil {
		t.Fatalf("GetNodeState(auto_assert) error = %v", err)
	} else if !ok {
		t.Fatalf("auto_assert did not execute")
	}
	if _, ok, err := service.store.GetNodeState(ctx, started.ID, "review_assert"); err != nil {
		t.Fatalf("GetNodeState(review_assert) error = %v", err)
	} else if ok {
		t.Fatalf("review_assert executed on auto_approved route")
	}
}

// TestStateMachineRoutesFromPriorNodeOutput verifies downstream states can inspect earlier action output.
func TestStateMachineRoutesFromPriorNodeOutput(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "node_output_route.yaml", `
kind: state_machine
id: node_output_route_flow
name: Node Output Route Flow
initial: read_yaml
states:
  - id: read_yaml
    on_entry:
      - id: read_yaml
        uses: data.defaults
        with:
          input: {}
          defaults:
            output:
              ok: true
    transitions:
      - trigger: succeeded
        to: route_yaml
  - id: route_yaml
    on_entry:
      - id: choose_yaml_route
        uses: decision.route
        with:
          default: failed
          rules:
            - route: succeeded
              when:
                path: read_yaml.output.ok
    transitions:
      - trigger: succeeded
        to: accepted
      - trigger: failed
        to: rejected
  - id: accepted
    on_entry:
      - id: accepted_assert
        uses: data.assert
        with:
          path: read_yaml.output.ok
          mode: equals
          value: true
  - id: rejected
    on_entry:
      - id: rejected_assert
        uses: data.assert
        with:
          path: read_yaml.output.ok
          mode: equals
          value: false
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "node_output_route_flow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
	run, err := service.Status(ctx, started.ID)
	if err != nil {
		t.Fatalf("Status() error = %v", err)
	}
	if run.State != "accepted" {
		t.Fatalf("run state = %q, want accepted", run.State)
	}
	if _, ok, err := service.store.GetNodeState(ctx, started.ID, "accepted_assert"); err != nil {
		t.Fatalf("GetNodeState(accepted_assert) error = %v", err)
	} else if !ok {
		t.Fatalf("accepted_assert did not execute")
	}
	if _, ok, err := service.store.GetNodeState(ctx, started.ID, "rejected_assert"); err != nil {
		t.Fatalf("GetNodeState(rejected_assert) error = %v", err)
	} else if ok {
		t.Fatalf("rejected_assert executed despite truthy node output")
	}
}

// TestStateMachineResumesWaitingEntryAction verifies pending hierarchical actions resume by signal.
func TestStateMachineResumesWaitingEntryAction(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "waiting.yaml", `
kind: state_machine
id: waiting_flow
name: Waiting Flow
initial: review
states:
  - id: review
    on_entry:
      - id: request_review
        uses: human.request
        with:
          prompt: Continue?
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "waiting_flow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	eventually(t, func() bool {
		run, err := service.Status(ctx, started.ID)
		return err == nil && run.Status == statusWaiting
	})
	if _, err := service.Signal(ctx, started.ID, "approve", map[string]any{"approved": true}); err != nil {
		t.Fatalf("Signal() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
}

// TestStateMachineFailureBlocksPublish verifies failed verification states do not execute publish states.
func TestStateMachineFailureBlocksPublish(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "blocked_publish.yaml", `
kind: state_machine
id: blocked_publish
name: Blocked Publish
initial: verify
states:
  - id: verify
    on_entry:
      - id: verify_change
        uses: data.assert
        with:
          path: workflow_input.ready
          mode: equals
          value: true
    transitions:
      - trigger: succeeded
        to: publish
      - trigger: failed
        to: blocked
  - id: publish
    on_entry:
      - id: publish_change
        uses: data.assert
        with:
          path: workflow_input.publish_allowed
          mode: equals
          value: true
  - id: blocked
    on_entry:
      - id: blocked_gate
        uses: data.assert
        with:
          path: workflow_input.manual_repair
          mode: exists
`)
	service := openTestService(t, ctx, definitionsDir, "")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "blocked_publish", map[string]any{"ready": false, "publish_allowed": true})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusFailed)
	if _, ok, err := service.store.GetNodeState(ctx, started.ID, "publish_change"); err != nil {
		t.Fatalf("GetNodeState() error = %v", err)
	} else if ok {
		t.Fatalf("publish_change executed, want publish blocked")
	}
}

// TestWorkflowEventsRedactSignalPayload verifies audit events do not expose credentials.
func TestWorkflowEventsRedactSignalPayload(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "redact.yaml", `
kind: state_machine
id: redact_signal
name: Redact Signal
initial: review
states:
  - id: review
    on_entry:
      - id: review_request
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

// TestStateMachineToolCallUsesHarnessContextAPI verifies tool.call stays harness-owned.
func TestStateMachineToolCallUsesHarnessContextAPI(t *testing.T) {
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
id: tool_workflow
name: Tool Workflow
initial: call
states:
  - id: call
    on_entry:
      - id: call_tool
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

// TestStateMachineRecordsObservedContracts verifies successful action outputs become reviewable contracts.
func TestStateMachineRecordsObservedContracts(t *testing.T) {
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
kind: state_machine
id: observe_contract
name: Observe Contract
initial: fetch
states:
  - id: fetch
    on_entry:
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

// TestStateMachineLLMActionRequiresStructuredSchema verifies model actions stay schema-constrained.
func TestStateMachineLLMActionRequiresStructuredSchema(t *testing.T) {
	ctx := context.Background()
	llm := &recordingWorkflowLLM{response: map[string]any{
		"status": "succeeded",
		"result": map[string]any{"summary": "invoice"},
	}}
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "llm.yaml", `
kind: state_machine
id: llm_workflow
name: LLM Workflow
initial: classify
states:
  - id: classify
    on_entry:
      - id: classify
        type: llm
        with:
          prompt: "Classify ${body.value.workflow_input.subject}"
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

// TestStateMachineRateLimitBlocksExcessInvocations verifies runtime rate policy is enforced.
func TestStateMachineRateLimitBlocksExcessInvocations(t *testing.T) {
	ctx := context.Background()
	var calls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "rate_limit.yaml", `
kind: state_machine
id: rate_limit_workflow
name: Rate Limit Workflow
initial: first
states:
  - id: first
    on_entry:
      - id: first
        type: tool
        tool: shared_tool
        runtime:
          rate_limit_per_minute: 1
        with:
          arguments: {}
    transitions:
      - trigger: succeeded
        to: second
  - id: second
    on_entry:
      - id: second
        type: tool
        tool: shared_tool
        runtime:
          rate_limit_per_minute: 1
        with:
          arguments: {}
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

// TestStateMachineRejectsSandboxBoundaryMismatch verifies runtime policy cannot claim a false sandbox.
func TestStateMachineRejectsSandboxBoundaryMismatch(t *testing.T) {
	ctx := context.Background()
	var calls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"ok": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "sandbox_mismatch.yaml", `
kind: state_machine
id: sandbox_mismatch
name: Sandbox Mismatch
initial: call
states:
  - id: call
    on_entry:
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

// TestStateMachineRetryDelayWaitsBetweenAttempts verifies fixed retry_delay policy.
func TestStateMachineRetryDelayWaitsBetweenAttempts(t *testing.T) {
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
kind: state_machine
id: retry_workflow
name: Retry Workflow
initial: call
states:
  - id: call
    on_entry:
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

// TestStateMachineResumeSkipsCompletedActions verifies completed actions are not rerun.
func TestStateMachineResumeSkipsCompletedActions(t *testing.T) {
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
id: resume_workflow
name: Resume Workflow
initial: first
states:
  - id: first
    on_entry:
      - id: first
        type: tool
        tool: first_tool
        with:
          arguments: {}
    transitions:
      - trigger: succeeded
        to: second
  - id: second
    on_entry:
      - id: second
        type: tool
        tool: second_tool
        with:
          arguments: {}
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

// TestStateMachineDataAssertGatesOnPriorOutput verifies generic data gates use prior action output.
func TestStateMachineDataAssertGatesOnPriorOutput(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{
			"plan": map[string]any{"status": "approved"},
		}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "gate.yaml", `
kind: state_machine
id: gated_workflow
name: Gated Workflow
initial: plan
states:
  - id: plan
    on_entry:
      - id: plan
        type: tool
        tool: plan_tool
        with:
          arguments: {}
    transitions:
      - trigger: succeeded
        to: assert_plan
  - id: assert_plan
    on_entry:
      - id: assert_plan
        type: assert
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
	service := openTestService(t, ctx, definitionsDir, toolServer.URL+"/api/context")
	defer service.Close()

	started, err := service.StartWorkflow(ctx, "gated_workflow", map[string]any{})
	if err != nil {
		t.Fatalf("StartWorkflow() error = %v", err)
	}
	waitForRunStatus(t, ctx, service, started.ID, statusSucceeded)
}

// TestStateMachineDataAssertFailureFailsRun verifies failed data gates stop progression.
func TestStateMachineDataAssertFailureFailsRun(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "gate_fail.yaml", `
kind: state_machine
id: failed_gate_workflow
name: Failed Gate Workflow
initial: assert_plan
states:
  - id: assert_plan
    on_entry:
      - id: assert_plan
        type: assert
        with:
          path: workflow_input.status
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

// TestStateMachinePolicyApprovalGatePausesBeforeEffects verifies confirmation-required effects wait.
func TestStateMachinePolicyApprovalGatePausesBeforeEffects(t *testing.T) {
	ctx := context.Background()
	var calls atomic.Int64
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"sent": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "approval_gate.yaml", `
kind: state_machine
id: approval_gate
name: Approval Gate
initial: send
states:
  - id: send
    on_entry:
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

// TestStateMachineRuntimeMaxInputBytesBlocksInvocation verifies runtime input limits.
func TestStateMachineRuntimeMaxInputBytesBlocksInvocation(t *testing.T) {
	ctx := context.Background()
	toolServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]any{"structuredContent": map[string]any{"called": true}})
	}))
	defer toolServer.Close()

	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "input_limit.yaml", `
kind: state_machine
id: input_limit
name: Input Limit
initial: gate
states:
  - id: gate
    on_entry:
      - id: gate
        uses: data.assert
        runtime:
          max_input_bytes: 10
        with:
          path: workflow_input.payload
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

// TestStateMachineRuntimeMaxArtifactBytesBlocksOversizedOutput verifies artifact limits.
func TestStateMachineRuntimeMaxArtifactBytesBlocksOversizedOutput(t *testing.T) {
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
kind: state_machine
id: artifact_limit
name: Artifact Limit
initial: fetch
states:
  - id: fetch
    on_entry:
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
