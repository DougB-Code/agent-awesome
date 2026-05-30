// This file tests Operations service resolution, preview, and start behavior.
package operations

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

const testWorkflowID = "source_change"

// TestOperationPreviewResolvesCodebaseInput verifies run input can use codebase defaults.
func TestOperationPreviewResolvesCodebaseInput(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)

	preview, err := service.PreviewOperationRun(ctx, op.ID, OperationRunRequest{Input: map[string]any{"change_request": "Fix settings crash"}})
	if err != nil {
		t.Fatalf("PreviewOperationRun() error = %v", err)
	}
	if preview.Status != "ready" || len(preview.MissingSetup) != 0 {
		t.Fatalf("preview = %#v, want ready without missing setup", preview)
	}
	if preview.ResolvedInput["repository_path"] != "/repo/agent" || preview.ResolvedInput["remote"] != "origin" {
		t.Fatalf("resolved input = %#v, want codebase repository defaults", preview.ResolvedInput)
	}
	fields := preview.Resolution["fields"].(map[string]any)
	repositoryField := fields["repository_path"].(map[string]any)
	if repositoryField["source"] != "codebase_default" {
		t.Fatalf("repository provenance = %#v, want codebase_default", repositoryField)
	}
}

// TestOperationCreatePreservesExplicitPolicy verifies saved policies are not workflow-special-cased.
func TestOperationCreatePreservesExplicitPolicy(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)

	op, err := service.CreateOperation(ctx, OperationRequest{
		Name:            "Source Change",
		WorkflowID:      testWorkflowID,
		CodebaseID:      "agent_awesome",
		RuntimeTargetID: "this_computer",
		Policy: OperationPolicy{
			SourceControl:     "open_pr_only",
			DestructiveAction: "deny",
			AllowedTools:      []string{"sourcecontrol.open_pull_request"},
			AllowedTargets:    []string{"this_computer"},
		},
	})
	if err != nil {
		t.Fatalf("CreateOperation() error = %v", err)
	}
	if op.Policy.SourceControl != "open_pr_only" || op.Policy.DestructiveAction != "deny" {
		t.Fatalf("policy = %#v, want explicit open-pr policy", op.Policy)
	}
	if !containsAny(op.Policy.AllowedTools, []string{"sourcecontrol.open_pull_request"}) {
		t.Fatalf("allowed tools = %#v, want sourcecontrol open PR", op.Policy.AllowedTools)
	}
	if !containsAny(op.Policy.AllowedTargets, []string{"this_computer"}) {
		t.Fatalf("allowed targets = %#v, want selected target", op.Policy.AllowedTargets)
	}
}

// TestOperationStartPersistsRunLinkAndSnapshot verifies workflow starts are auditable.
func TestOperationStartPersistsRunLinkAndSnapshot(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)

	started, err := service.StartOperation(ctx, op.ID, OperationRunRequest{Input: map[string]any{"change_request": "Fix settings crash"}})
	if err != nil {
		t.Fatalf("StartOperation() error = %v", err)
	}
	if started.Run.ID == "" || started.Link.OperationID != op.ID || started.Link.RunID != started.Run.ID {
		t.Fatalf("start result = %#v, want run link", started)
	}
	snapshot, err := service.store.GetRunSnapshot(ctx, started.Run.ID)
	if err != nil {
		t.Fatalf("GetRunSnapshot() error = %v", err)
	}
	if snapshot.OperationID != op.ID || snapshot.ResolvedInput["change_request"] != "Fix settings crash" {
		t.Fatalf("snapshot = %#v, want resolved run snapshot", snapshot)
	}
}

// TestOperationSnapshotRedactsRawSecretRequestValues verifies snapshots keep refs only.
func TestOperationSnapshotRedactsRawSecretRequestValues(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)

	started, err := service.StartOperation(ctx, op.ID, OperationRunRequest{
		Input: map[string]any{
			"change_request": "Fix settings crash",
			"api_token":      "plain-secret-value",
		},
		Task: map[string]any{
			"title":     "Fix settings crash",
			"api_token": "nested-secret-value",
		},
	})
	if err != nil {
		t.Fatalf("StartOperation() error = %v", err)
	}
	snapshot, err := service.store.GetRunSnapshot(ctx, started.Run.ID)
	if err != nil {
		t.Fatalf("GetRunSnapshot() error = %v", err)
	}
	if snapshot.ResolvedInput["api_token"] == "plain-secret-value" {
		t.Fatalf("snapshot = %#v, want secret value absent", snapshot.ResolvedInput)
	}
	if snapshot.ResolvedInput["api_token"] != "secret://redacted/api_token" {
		t.Fatalf("api_token = %#v, want redacted secret reference", snapshot.ResolvedInput["api_token"])
	}
	task, ok := snapshot.ResolvedInput["task"].(map[string]any)
	if !ok {
		t.Fatalf("task = %#v, want redacted task map", snapshot.ResolvedInput["task"])
	}
	if task["api_token"] != "secret://redacted/api_token" {
		t.Fatalf("task api_token = %#v, want redacted secret reference", task["api_token"])
	}
}

// TestOperationStartResolvesCodebaseByName verifies generic starts can resolve codebase defaults.
func TestOperationStartResolvesCodebaseByName(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)

	started, err := service.StartOperation(ctx, op.ID, OperationRunRequest{
		CodebaseName: "Agent Awesome",
		Input:        map[string]any{"change_request": "Fix settings crash"},
		Source:       "api",
	})
	if err != nil {
		t.Fatalf("StartOperation() error = %v", err)
	}
	if started.Run.DefinitionID != testWorkflowID {
		t.Fatalf("definition = %q, want test workflow", started.Run.DefinitionID)
	}
	if started.Run.Input["repository_path"] != "/repo/agent" {
		t.Fatalf("repository_path = %#v, want codebase default", started.Run.Input["repository_path"])
	}
}

// TestQueuedOperationRunLeasesAndStarts verifies durable target leasing.
func TestQueuedOperationRunLeasesAndStarts(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)

	queued, err := service.EnqueueOperationRun(ctx, op.ID, OperationRunRequest{
		Input:  map[string]any{"change_request": "Fix settings crash", "api_token": "secret"},
		Source: "schedule",
	})
	if err != nil {
		t.Fatalf("EnqueueOperationRun() error = %v", err)
	}
	if queued.Status != OperationRunQueueStatusQueued || queued.Target.RuntimeTargetID != "this_computer" {
		t.Fatalf("queued = %#v, want queued for this_computer", queued)
	}
	if queued.RequestInput["api_token"] != "[redacted]" {
		t.Fatalf("request input = %#v, want secret redacted", queued.RequestInput)
	}

	lease, err := service.LeaseQueuedOperationRun(ctx, OperationRunLeaseRequest{TargetID: "this_computer"})
	if err != nil {
		t.Fatalf("LeaseQueuedOperationRun() error = %v", err)
	}
	if lease.Item.ID != queued.ID || lease.Item.Attempts != 1 || lease.Item.Status != OperationRunQueueStatusLeased {
		t.Fatalf("lease = %#v, want leased queued run", lease)
	}
	if _, err := service.LeaseQueuedOperationRun(ctx, OperationRunLeaseRequest{TargetID: "this_computer"}); err == nil {
		t.Fatalf("second LeaseQueuedOperationRun() error = nil, want no eligible item")
	}

	renewed, err := service.RenewQueuedOperationRunLease(ctx, queued.ID, OperationRunLeaseRenewRequest{LeaseID: lease.LeaseID, LeaseSeconds: 600})
	if err != nil {
		t.Fatalf("RenewQueuedOperationRunLease() error = %v", err)
	}
	if renewed.Item.LeaseExpiresAt == "" {
		t.Fatalf("renewed lease = %#v, want expiry", renewed)
	}

	started, err := service.StartQueuedOperationRun(ctx, queued.ID, lease.LeaseID)
	if err != nil {
		t.Fatalf("StartQueuedOperationRun() error = %v", err)
	}
	if started.Run.ID == "" || started.Item.Status != OperationRunQueueStatusRunning {
		t.Fatalf("started = %#v, want running workflow", started)
	}
	snapshot, err := service.store.GetRunSnapshot(ctx, started.Run.ID)
	if err != nil {
		t.Fatalf("GetRunSnapshot() error = %v", err)
	}
	if snapshot.OperationID != op.ID || snapshot.Target.RuntimeTargetID != "this_computer" {
		t.Fatalf("snapshot = %#v, want queued run snapshot", snapshot)
	}
	completed, err := service.ReleaseQueuedOperationRunLease(ctx, queued.ID, OperationRunLeaseReleaseRequest{LeaseID: lease.LeaseID, Status: OperationRunQueueStatusCompleted})
	if err != nil {
		t.Fatalf("ReleaseQueuedOperationRunLease() error = %v", err)
	}
	if completed.Status != OperationRunQueueStatusCompleted || completed.RunID != started.Run.ID {
		t.Fatalf("completed = %#v, want completed run id", completed)
	}
}

// TestExpiredQueueLeaseRecovery verifies expired leases retry then fail by policy.
func TestExpiredQueueLeaseRecovery(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	op, err := service.CreateOperation(ctx, OperationRequest{
		ID:              "retrying_source_change",
		Name:            "Retrying Source Change",
		WorkflowID:      testWorkflowID,
		CodebaseID:      "agent_awesome",
		RuntimeTargetID: "this_computer",
		AgentProfileID:  "automation_agent",
		Defaults:        map[string]any{"package_path": "."},
		Policy:          OperationPolicy{RetryLimit: 1},
	})
	if err != nil {
		t.Fatalf("CreateOperation() error = %v", err)
	}
	queued, err := service.EnqueueOperationRun(ctx, op.ID, OperationRunRequest{Input: map[string]any{"change_request": "Fix settings crash"}})
	if err != nil {
		t.Fatalf("EnqueueOperationRun() error = %v", err)
	}
	leaseOne, err := service.store.LeaseNextRunQueueItem(ctx, "this_computer", "lease_one", time.Now().UTC().Add(-time.Minute).Format(time.RFC3339))
	if err != nil {
		t.Fatalf("LeaseNextRunQueueItem() error = %v", err)
	}
	recovered, err := service.store.RecoverExpiredRunQueueLeases(ctx, time.Now().UTC().Format(time.RFC3339))
	if err != nil {
		t.Fatalf("RecoverExpiredRunQueueLeases() error = %v", err)
	}
	if recovered != 1 {
		t.Fatalf("recovered = %d, want 1", recovered)
	}
	retry, err := service.store.GetRunQueueItem(ctx, queued.ID)
	if err != nil {
		t.Fatalf("GetRunQueueItem() error = %v", err)
	}
	if retry.Status != OperationRunQueueStatusQueued || retry.Attempts != leaseOne.Attempts {
		t.Fatalf("retry item = %#v, want queued retry", retry)
	}
	if _, err := service.store.LeaseNextRunQueueItem(ctx, "this_computer", "lease_two", time.Now().UTC().Add(-time.Minute).Format(time.RFC3339)); err != nil {
		t.Fatalf("second LeaseNextRunQueueItem() error = %v", err)
	}
	if _, err := service.store.RecoverExpiredRunQueueLeases(ctx, time.Now().UTC().Format(time.RFC3339)); err != nil {
		t.Fatalf("second RecoverExpiredRunQueueLeases() error = %v", err)
	}
	failed, err := service.store.GetRunQueueItem(ctx, queued.ID)
	if err != nil {
		t.Fatalf("GetRunQueueItem() failed item error = %v", err)
	}
	if failed.Status != OperationRunQueueStatusFailed || failed.LastError != "lease expired" {
		t.Fatalf("failed item = %#v, want exhausted lease failure", failed)
	}
}

// TestEnqueueDueScheduledOperations verifies due schedules enqueue durable runs once.
func TestEnqueueDueScheduledOperations(t *testing.T) {
	ctx := context.Background()
	service := newTestOperationsService(t)
	_, err := service.CreateOperation(ctx, OperationRequest{
		ID:              "scheduled_source_change",
		Name:            "Scheduled Source Change",
		WorkflowID:      testWorkflowID,
		CodebaseID:      "agent_awesome",
		RuntimeTargetID: "this_computer",
		AgentProfileID:  "automation_agent",
		Defaults: map[string]any{
			"change_request": "Refresh generated docs",
			"package_path":   ".",
		},
		Policy:   OperationPolicy{MaxParallelism: 1},
		Schedule: OperationSchedule{Enabled: true, Cron: "5 12 * * *"},
	})
	if err != nil {
		t.Fatalf("CreateOperation() error = %v", err)
	}
	now := time.Date(2026, 5, 24, 12, 5, 0, 0, time.UTC)
	result, err := service.EnqueueDueScheduledOperations(ctx, now)
	if err != nil {
		t.Fatalf("EnqueueDueScheduledOperations() error = %v", err)
	}
	if len(result.Enqueued) != 1 || result.Enqueued[0].Source != "schedule" {
		t.Fatalf("schedule result = %#v, want one scheduled queue item", result)
	}
	result, err = service.EnqueueDueScheduledOperations(ctx, now)
	if err != nil {
		t.Fatalf("second EnqueueDueScheduledOperations() error = %v", err)
	}
	if len(result.Enqueued) != 0 || len(result.Skipped) != 1 || result.Skipped[0].Reason != "max parallel runs active" {
		t.Fatalf("second schedule result = %#v, want max parallel skip", result)
	}
}

// newTestOperationsService creates an isolated Operations service.
func newTestOperationsService(t *testing.T) *Service {
	t.Helper()
	store, err := OpenStore(context.Background(), filepath.Join(t.TempDir(), "operations.db"))
	if err != nil {
		t.Fatalf("OpenStore() error = %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return NewService(store, &fakeWorkflowExecutor{}, fakeCodebaseCatalog{
		records: map[string]Codebase{
			"agent_awesome": {
				ID:              "agent_awesome",
				Name:            "Agent Awesome",
				Aliases:         []string{"aa", "agent awesome"},
				RepositoryPath:  "/repo/agent",
				DefaultRemote:   "origin",
				DefaultBranch:   "main",
				RuntimeTargetID: "this_computer",
				AgentProfileID:  "automation_agent",
			},
		},
	})
}

// createTestSourceOperation stores a source-control Operation fixture.
func createTestSourceOperation(t *testing.T, service *Service) Operation {
	t.Helper()
	op, err := service.CreateOperation(context.Background(), OperationRequest{
		ID:              "source_change_agent_awesome",
		Name:            "Source Change for Agent Awesome",
		WorkflowID:      testWorkflowID,
		CodebaseID:      "agent_awesome",
		RuntimeTargetID: "this_computer",
		AgentProfileID:  "automation_agent",
		Defaults:        map[string]any{"package_path": "."},
	})
	if err != nil {
		t.Fatalf("CreateOperation() error = %v", err)
	}
	return op
}

// fakeWorkflowExecutor records workflow starts for tests.
type fakeWorkflowExecutor struct {
	starts int
}

// StartWorkflow returns a synthetic workflow run.
func (f *fakeWorkflowExecutor) StartWorkflow(_ context.Context, definitionID string, input map[string]any) (WorkflowRun, error) {
	f.starts++
	return WorkflowRun{ID: "run_123", DefinitionID: definitionID, Status: "running", Input: input}, nil
}

// WorkflowDefaults returns test workflow defaults.
func (f *fakeWorkflowExecutor) WorkflowDefaults(context.Context, string) (map[string]any, string, error) {
	return map[string]any{"pull_request_draft": false}, "test-hash", nil
}

// fakeCodebaseCatalog stores codebases in memory for tests.
type fakeCodebaseCatalog struct {
	records map[string]Codebase
}

// GetCodebase returns one fake codebase by id.
func (f fakeCodebaseCatalog) GetCodebase(_ context.Context, id string) (Codebase, error) {
	return f.records[id], nil
}

// ResolveCodebase resolves one fake codebase by name or alias.
func (f fakeCodebaseCatalog) ResolveCodebase(_ context.Context, query string) (CodebaseResolution, error) {
	for _, record := range f.records {
		if query == record.Name || query == record.ID {
			return CodebaseResolution{Status: "matched", Codebase: &record}, nil
		}
		for _, alias := range record.Aliases {
			if query == alias {
				return CodebaseResolution{Status: "matched", Codebase: &record}, nil
			}
		}
	}
	return CodebaseResolution{Status: "not_found"}, nil
}
