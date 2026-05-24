// This file implements the Operations service boundary.
package operations

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"agentawesome/internal/services/operations/resolution"
)

const (
	defaultOperationStatus          = "active"
	defaultOperationRunLeaseSeconds = 300
	maxOperationRunLeaseSeconds     = 3600
	codingWorkflowID                = "professional_coding_change"
)

var operationIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)

// WorkflowExecutor starts workflow runs for resolved Operations.
type WorkflowExecutor interface {
	StartWorkflow(context.Context, string, map[string]any) (WorkflowRun, error)
	WorkflowDefaults(context.Context, string) (map[string]any, string, error)
}

// CodebaseCatalog resolves memory-backed codebase records.
type CodebaseCatalog interface {
	GetCodebase(context.Context, string) (Codebase, error)
	ResolveCodebase(context.Context, string) (CodebaseResolution, error)
}

// Service owns Operation setup, resolution, policy, and run links.
type Service struct {
	store     *Store
	workflow  WorkflowExecutor
	codebases CodebaseCatalog
	resolver  resolution.Resolver
}

// NewService creates an Operations service.
func NewService(store *Store, workflow WorkflowExecutor, codebases CodebaseCatalog) *Service {
	return &Service{store: store, workflow: workflow, codebases: codebases, resolver: resolution.NewResolver()}
}

// CreateOperation validates and stores a new Operation.
func (s *Service) CreateOperation(ctx context.Context, req OperationRequest) (Operation, error) {
	op, err := operationFromRequest(req, true)
	if err != nil {
		return Operation{}, err
	}
	if err := s.store.UpsertOperation(ctx, op); err != nil {
		return Operation{}, err
	}
	return s.store.GetOperation(ctx, op.ID)
}

// UpdateOperation replaces one existing Operation.
func (s *Service) UpdateOperation(ctx context.Context, id string, req OperationRequest) (Operation, error) {
	req.ID = strings.TrimSpace(id)
	op, err := operationFromRequest(req, false)
	if err != nil {
		return Operation{}, err
	}
	existing, err := s.store.GetOperation(ctx, op.ID)
	if err != nil {
		return Operation{}, err
	}
	op.CreatedAt = existing.CreatedAt
	op.Version = existing.Version
	if err := s.store.UpsertOperation(ctx, op); err != nil {
		return Operation{}, err
	}
	return s.store.GetOperation(ctx, op.ID)
}

// GetOperation loads one saved Operation.
func (s *Service) GetOperation(ctx context.Context, id string) (Operation, error) {
	return s.store.GetOperation(ctx, id)
}

// ListOperations lists saved Operations.
func (s *Service) ListOperations(ctx context.Context, query OperationQuery) ([]Operation, error) {
	return s.store.ListOperations(ctx, query)
}

// DeleteOperation removes one saved Operation.
func (s *Service) DeleteOperation(ctx context.Context, id string) error {
	return s.store.DeleteOperation(ctx, id)
}

// GetOperationRunSnapshot loads immutable Operation audit data for a run.
func (s *Service) GetOperationRunSnapshot(ctx context.Context, runID string) (OperationRunSnapshot, error) {
	return s.store.GetRunSnapshot(ctx, runID)
}

// PreviewOperationRun resolves input and policy without starting a workflow.
func (s *Service) PreviewOperationRun(ctx context.Context, operationID string, req OperationRunRequest) (OperationPreview, error) {
	op, err := s.store.GetOperation(ctx, operationID)
	if err != nil {
		return OperationPreview{}, err
	}
	resolved, err := s.ResolveOperationInput(ctx, op, req)
	if err != nil {
		return OperationPreview{}, err
	}
	decision := evaluatePolicy(op, resolved)
	missing := unresolvedNames(resolved)
	status := "ready"
	if len(missing) > 0 {
		status = "needs_input"
	}
	if decision.Status != "allowed" {
		status = "blocked"
	}
	return OperationPreview{
		Operation:      op,
		ResolvedInput:  resolved.Input,
		Resolution:     resolutionMap(resolved),
		MissingSetup:   missing,
		PolicyDecision: decision,
		Status:         status,
	}, nil
}

// StartOperation resolves input, records a snapshot, and starts a workflow run.
func (s *Service) StartOperation(ctx context.Context, operationID string, req OperationRunRequest) (OperationStartResult, error) {
	preview, err := s.PreviewOperationRun(ctx, operationID, req)
	if err != nil {
		return OperationStartResult{}, err
	}
	if len(preview.MissingSetup) > 0 {
		return OperationStartResult{}, fmt.Errorf("operation needs input: %s", strings.Join(preview.MissingSetup, ", "))
	}
	if preview.PolicyDecision.Status != "allowed" {
		return OperationStartResult{}, fmt.Errorf("operation policy blocked start: %s", strings.Join(preview.PolicyDecision.Reasons, "; "))
	}
	run, err := s.workflow.StartWorkflow(ctx, preview.Operation.WorkflowID, preview.ResolvedInput)
	if err != nil {
		return OperationStartResult{}, err
	}
	link := OperationRunLink{OperationID: preview.Operation.ID, RunID: run.ID}
	if err := s.store.InsertRunLink(ctx, link); err != nil {
		return OperationStartResult{}, err
	}
	snapshot := OperationRunSnapshot{
		RunID:            run.ID,
		OperationID:      preview.Operation.ID,
		OperationVersion: preview.Operation.Version,
		WorkflowID:       preview.Operation.WorkflowID,
		WorkflowVersion:  preview.Operation.WorkflowVersion,
		ResolvedInput:    preview.ResolvedInput,
		Resolution:       preview.Resolution,
		Target: OperationTarget{
			RuntimeTargetID: preview.Operation.RuntimeTargetID,
			AgentProfileID:  preview.Operation.AgentProfileID,
		},
		Policy:     preview.Operation.Policy,
		SecretRefs: preview.Operation.SecretRefs,
	}
	if err := s.store.InsertRunSnapshot(ctx, snapshot); err != nil {
		return OperationStartResult{}, err
	}
	link.CreatedAt = timestampNow()
	snapshot.CreatedAt = link.CreatedAt
	return OperationStartResult{Operation: preview.Operation, Run: run, Preview: preview, Link: link, Snapshot: snapshot}, nil
}

// EnqueueOperationRun stores a resolved Operation run for a target worker.
func (s *Service) EnqueueOperationRun(ctx context.Context, operationID string, req OperationRunRequest) (OperationRunQueueItem, error) {
	preview, err := s.PreviewOperationRun(ctx, operationID, req)
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	if len(preview.MissingSetup) > 0 {
		return OperationRunQueueItem{}, fmt.Errorf("operation needs input: %s", strings.Join(preview.MissingSetup, ", "))
	}
	if preview.PolicyDecision.Status != "allowed" {
		return OperationRunQueueItem{}, fmt.Errorf("operation policy blocked enqueue: %s", strings.Join(preview.PolicyDecision.Reasons, "; "))
	}
	id, err := randomHexID("oprun")
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	now := timestampNow()
	item := OperationRunQueueItem{
		ID:               id,
		OperationID:      preview.Operation.ID,
		OperationVersion: preview.Operation.Version,
		OperationHash:    hashOperation(preview.Operation),
		WorkflowID:       preview.Operation.WorkflowID,
		WorkflowVersion:  preview.Operation.WorkflowVersion,
		Target: OperationTarget{
			RuntimeTargetID: preview.Operation.RuntimeTargetID,
			AgentProfileID:  preview.Operation.AgentProfileID,
		},
		Policy:         preview.Operation.Policy,
		PolicyDecision: preview.PolicyDecision,
		SecretRefs:     preview.Operation.SecretRefs,
		ResolvedInput:  preview.ResolvedInput,
		Resolution:     preview.Resolution,
		RequestInput:   displaySafeRequestInput(req),
		Source:         strings.TrimSpace(req.Source),
		Status:         OperationRunQueueStatusQueued,
		MaxAttempts:    maxAttemptsForPolicy(preview.Operation.Policy),
		EnqueuedAt:     now,
		UpdatedAt:      now,
	}
	if err := s.store.InsertRunQueueItem(ctx, item); err != nil {
		return OperationRunQueueItem{}, err
	}
	return s.store.GetRunQueueItem(ctx, item.ID)
}

// ListQueuedOperationRuns lists durable queued Operation runs.
func (s *Service) ListQueuedOperationRuns(ctx context.Context, query OperationRunQueueQuery) ([]OperationRunQueueItem, error) {
	return s.store.ListRunQueueItems(ctx, query)
}

// LeaseQueuedOperationRun leases one eligible queued run for a target worker.
func (s *Service) LeaseQueuedOperationRun(ctx context.Context, req OperationRunLeaseRequest) (OperationRunLease, error) {
	targetID := strings.TrimSpace(req.TargetID)
	if targetID == "" {
		return OperationRunLease{}, errors.New("target_id is required")
	}
	leaseID, err := randomHexID("lease")
	if err != nil {
		return OperationRunLease{}, err
	}
	expiresAt := operationRunLeaseExpiry(req.LeaseSeconds)
	item, err := s.store.LeaseNextRunQueueItem(ctx, targetID, leaseID, expiresAt)
	if err != nil {
		return OperationRunLease{}, err
	}
	return OperationRunLease{Item: item, LeaseID: leaseID, LeaseExpiresAt: expiresAt}, nil
}

// RenewQueuedOperationRunLease extends a live target worker lease.
func (s *Service) RenewQueuedOperationRunLease(ctx context.Context, queueID string, req OperationRunLeaseRenewRequest) (OperationRunLease, error) {
	leaseID := strings.TrimSpace(req.LeaseID)
	if leaseID == "" {
		return OperationRunLease{}, errors.New("lease_id is required")
	}
	expiresAt := operationRunLeaseExpiry(req.LeaseSeconds)
	item, err := s.store.RenewRunQueueLease(ctx, queueID, leaseID, expiresAt)
	if err != nil {
		return OperationRunLease{}, err
	}
	return OperationRunLease{Item: item, LeaseID: leaseID, LeaseExpiresAt: expiresAt}, nil
}

// StartQueuedOperationRun starts a workflow run from an active queue lease.
func (s *Service) StartQueuedOperationRun(ctx context.Context, queueID string, leaseID string) (OperationRunQueueStartResult, error) {
	item, err := s.store.GetRunQueueItem(ctx, queueID)
	if err != nil {
		return OperationRunQueueStartResult{}, err
	}
	if item.Status != OperationRunQueueStatusLeased {
		return OperationRunQueueStartResult{}, fmt.Errorf("queued run %q is %s, not leased", item.ID, item.Status)
	}
	if item.LeaseID != strings.TrimSpace(leaseID) {
		return OperationRunQueueStartResult{}, errors.New("lease_id does not match queued run")
	}
	if operationRunLeaseExpired(item.LeaseExpiresAt) {
		return OperationRunQueueStartResult{}, errors.New("queued run lease expired")
	}
	run, err := s.workflow.StartWorkflow(ctx, item.WorkflowID, item.ResolvedInput)
	if err != nil {
		return OperationRunQueueStartResult{}, err
	}
	link := OperationRunLink{OperationID: item.OperationID, RunID: run.ID}
	if err := s.store.InsertRunLink(ctx, link); err != nil {
		return OperationRunQueueStartResult{}, err
	}
	snapshot := OperationRunSnapshot{
		RunID:            run.ID,
		OperationID:      item.OperationID,
		OperationVersion: item.OperationVersion,
		WorkflowID:       item.WorkflowID,
		WorkflowVersion:  item.WorkflowVersion,
		ResolvedInput:    item.ResolvedInput,
		Resolution:       item.Resolution,
		Target:           item.Target,
		Policy:           item.Policy,
		SecretRefs:       item.SecretRefs,
	}
	if err := s.store.InsertRunSnapshot(ctx, snapshot); err != nil {
		return OperationRunQueueStartResult{}, err
	}
	item, err = s.store.MarkRunQueueItemRunning(ctx, item.ID, leaseID, run.ID)
	if err != nil {
		return OperationRunQueueStartResult{}, err
	}
	link.CreatedAt = timestampNow()
	snapshot.CreatedAt = link.CreatedAt
	return OperationRunQueueStartResult{Item: item, Run: run, Link: link, Snapshot: snapshot}, nil
}

// ReleaseQueuedOperationRunLease marks a leased queued run complete or failed.
func (s *Service) ReleaseQueuedOperationRunLease(ctx context.Context, queueID string, req OperationRunLeaseReleaseRequest) (OperationRunQueueItem, error) {
	if strings.TrimSpace(req.LeaseID) == "" {
		return OperationRunQueueItem{}, errors.New("lease_id is required")
	}
	req.Status = strings.TrimSpace(req.Status)
	if req.Status == "" {
		req.Status = OperationRunQueueStatusCompleted
	}
	if !isTerminalQueueStatus(req.Status) {
		return OperationRunQueueItem{}, fmt.Errorf("queue release status %q is not terminal", req.Status)
	}
	return s.store.ReleaseRunQueueLease(ctx, queueID, req)
}

// CancelQueuedOperationRun cancels one queued run before completion.
func (s *Service) CancelQueuedOperationRun(ctx context.Context, queueID string) (OperationRunQueueItem, error) {
	return s.store.CancelRunQueueItem(ctx, queueID)
}

// RecoverExpiredQueuedOperationRunLeases returns expired leases to the queue.
func (s *Service) RecoverExpiredQueuedOperationRunLeases(ctx context.Context) (int, error) {
	return s.store.RecoverExpiredRunQueueLeases(ctx, timestampNow())
}

// EnqueueDueScheduledOperations queues due scheduled Operations.
func (s *Service) EnqueueDueScheduledOperations(ctx context.Context, now time.Time) (OperationScheduleResult, error) {
	ops, err := s.store.ListOperations(ctx, OperationQuery{Status: defaultOperationStatus})
	if err != nil {
		return OperationScheduleResult{}, err
	}
	result := OperationScheduleResult{Checked: len(ops)}
	for _, op := range ops {
		if !op.Schedule.Enabled {
			continue
		}
		if !operationScheduleDue(op.Schedule, now) {
			continue
		}
		if operationScheduleStopped(op.Schedule, now) {
			result.Skipped = append(result.Skipped, OperationScheduleSkip{OperationID: op.ID, Reason: "schedule window ended"})
			continue
		}
		if operationScheduleInQuietHours(op.Schedule, now) {
			result.Skipped = append(result.Skipped, OperationScheduleSkip{OperationID: op.ID, Reason: "quiet hours"})
			continue
		}
		if op.Schedule.MaxRuns > 0 {
			count, err := s.store.CountRunQueueItems(ctx, op.ID)
			if err != nil {
				return result, err
			}
			if count >= op.Schedule.MaxRuns {
				result.Skipped = append(result.Skipped, OperationScheduleSkip{OperationID: op.ID, Reason: "max scheduled runs reached"})
				continue
			}
		}
		maxParallel := op.Policy.MaxParallelism
		if maxParallel <= 0 {
			maxParallel = 1
		}
		active, err := s.store.CountRunQueueItems(ctx, op.ID, OperationRunQueueStatusQueued, OperationRunQueueStatusLeased, OperationRunQueueStatusRunning)
		if err != nil {
			return result, err
		}
		if active >= maxParallel {
			result.Skipped = append(result.Skipped, OperationScheduleSkip{OperationID: op.ID, Reason: "max parallel runs active"})
			continue
		}
		item, err := s.EnqueueOperationRun(ctx, op.ID, OperationRunRequest{Source: "schedule"})
		if err != nil {
			result.Skipped = append(result.Skipped, OperationScheduleSkip{OperationID: op.ID, Reason: err.Error()})
			continue
		}
		result.Enqueued = append(result.Enqueued, item)
	}
	return result, nil
}

// StartCodingChange resolves a coding Operation from a conversational request.
func (s *Service) StartCodingChange(ctx context.Context, req OperationRunRequest) (OperationStartResult, error) {
	codebase, err := s.resolveRequestedCodebase(ctx, req)
	if err != nil {
		return OperationStartResult{}, err
	}
	ops, err := s.store.ListOperations(ctx, OperationQuery{WorkflowID: codingWorkflowID, CodebaseID: codebase.ID, Status: defaultOperationStatus})
	if err != nil {
		return OperationStartResult{}, err
	}
	if len(ops) == 0 {
		return OperationStartResult{}, fmt.Errorf("no coding operation is configured for codebase %q", codebase.Name)
	}
	if len(ops) > 1 {
		return OperationStartResult{}, fmt.Errorf("multiple coding operations are configured for codebase %q", codebase.Name)
	}
	req.OperationID = ops[0].ID
	if req.Input == nil {
		req.Input = map[string]any{}
	}
	req.Input["codebase_id"] = codebase.ID
	return s.StartOperation(ctx, ops[0].ID, req)
}

// ResolveOperationInput applies the shared input resolver for one Operation.
func (s *Service) ResolveOperationInput(ctx context.Context, op Operation, req OperationRunRequest) (resolution.Result, error) {
	codebase, codebaseDiagnostics, err := s.operationCodebase(ctx, op, req)
	if err != nil {
		return resolution.Result{}, err
	}
	workflowDefaults, workflowVersion, err := s.workflow.WorkflowDefaults(ctx, op.WorkflowID)
	if err != nil {
		return resolution.Result{}, err
	}
	workflowDefaults = mergeDefaults(defaultWorkflowInput(op.WorkflowID), workflowDefaults)
	if op.WorkflowVersion == "" {
		op.WorkflowVersion = workflowVersion
	}
	codebaseDefaults := codebaseDefaultInput(codebase)
	generated := generatedInput(op, codebase, req)
	secretRefs := secretReferenceInput(op.SecretRefs)
	required := requiredFieldsForWorkflow(op.WorkflowID)
	result, err := s.resolver.Resolve(ctx, resolution.Request{
		RequiredFields:    required,
		RunRequest:        requestInput(req),
		OperationDefaults: op.Defaults,
		CodebaseDefaults:  codebaseDefaults,
		WorkflowDefaults:  workflowDefaults,
		GeneratedValues:   generated,
		SecretReferences:  secretRefs,
	})
	if err != nil {
		return resolution.Result{}, err
	}
	for _, diagnostic := range codebaseDiagnostics {
		result.Diagnostics = append(result.Diagnostics, resolution.Diagnostic{Level: "info", Message: diagnostic})
	}
	return result, nil
}

// operationCodebase returns the codebase bound to a run request or Operation.
func (s *Service) operationCodebase(ctx context.Context, op Operation, req OperationRunRequest) (Codebase, []string, error) {
	if s.codebases == nil {
		return Codebase{}, nil, errors.New("codebase catalog is not configured")
	}
	if strings.TrimSpace(req.CodebaseName) != "" {
		resolved, err := s.codebases.ResolveCodebase(ctx, req.CodebaseName)
		if err != nil {
			return Codebase{}, nil, err
		}
		if resolved.Status != "matched" || resolved.Codebase == nil {
			return Codebase{}, resolved.Diagnostics, fmt.Errorf("codebase %q was not resolved: %s", req.CodebaseName, resolved.Status)
		}
		return *resolved.Codebase, resolved.Diagnostics, nil
	}
	if codebaseID, ok := req.Input["codebase_id"].(string); ok && strings.TrimSpace(codebaseID) != "" {
		codebase, err := s.codebases.GetCodebase(ctx, codebaseID)
		return codebase, nil, err
	}
	if strings.TrimSpace(op.CodebaseID) == "" {
		return Codebase{}, nil, nil
	}
	codebase, err := s.codebases.GetCodebase(ctx, op.CodebaseID)
	return codebase, nil, err
}

// resolveRequestedCodebase resolves the conversational coding codebase.
func (s *Service) resolveRequestedCodebase(ctx context.Context, req OperationRunRequest) (Codebase, error) {
	name := strings.TrimSpace(req.CodebaseName)
	if name == "" {
		if value, ok := req.Input["codebase"].(string); ok {
			name = value
		}
	}
	if name == "" {
		if value, ok := req.Input["codebase_name"].(string); ok {
			name = value
		}
	}
	if name == "" {
		if value, ok := req.Task["codebase"].(string); ok {
			name = value
		}
	}
	if name == "" {
		if value, ok := req.Task["codebase_name"].(string); ok {
			name = value
		}
	}
	if name == "" {
		return Codebase{}, errors.New("codebase name is required")
	}
	resolved, err := s.codebases.ResolveCodebase(ctx, name)
	if err != nil {
		return Codebase{}, err
	}
	if resolved.Status != "matched" || resolved.Codebase == nil {
		return Codebase{}, fmt.Errorf("codebase %q was not resolved: %s", name, resolved.Status)
	}
	return *resolved.Codebase, nil
}

// operationFromRequest normalizes a create or update request.
func operationFromRequest(req OperationRequest, create bool) (Operation, error) {
	id := normalizeOperationID(req.ID)
	if id == "" && create {
		id = normalizeOperationID(slug(req.Name))
	}
	if id == "" || !operationIDPattern.MatchString(id) {
		return Operation{}, fmt.Errorf("operation id is required and must be stable")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return Operation{}, errors.New("operation name is required")
	}
	workflowID := strings.TrimSpace(req.WorkflowID)
	if workflowID == "" {
		return Operation{}, errors.New("workflow_id is required")
	}
	status := strings.TrimSpace(req.Status)
	if status == "" {
		status = defaultOperationStatus
	}
	policy := req.Policy
	if workflowID == codingWorkflowID && (policy.SourceControl == "" || policy.SourceControl == "open_pr_only") {
		policy = defaultCodingPolicy(req)
	}
	version := 1
	return Operation{
		ID:              id,
		Name:            name,
		WorkflowID:      workflowID,
		WorkflowVersion: strings.TrimSpace(req.WorkflowVersion),
		CodebaseID:      strings.TrimSpace(req.CodebaseID),
		RuntimeTargetID: strings.TrimSpace(req.RuntimeTargetID),
		AgentProfileID:  strings.TrimSpace(req.AgentProfileID),
		Defaults:        cloneMap(req.Defaults),
		Policy:          policy,
		Schedule:        req.Schedule,
		SecretRefs:      req.SecretRefs,
		Status:          status,
		Version:         version,
	}, nil
}

// defaultCodingPolicy returns source-control-safe coding defaults.
func defaultCodingPolicy(req OperationRequest) OperationPolicy {
	policy := req.Policy
	policy.SourceControl = "open_pr_only"
	policy.DestructiveAction = "deny"
	policy.AllowedTools = uniqueStrings(append(policy.AllowedTools,
		"sourcecontrol.prepare_worktree",
		"sourcecontrol.status",
		"sourcecontrol.commit",
		"sourcecontrol.push",
		"sourcecontrol.open_pull_request",
	))
	policy.AllowedMCPServers = uniqueStrings(append(policy.AllowedMCPServers, "sourcecontrol"))
	if req.CodebaseID != "" {
		policy.AllowedCodebases = uniqueStrings(append(policy.AllowedCodebases, req.CodebaseID))
	}
	if req.RuntimeTargetID != "" {
		policy.AllowedTargets = uniqueStrings(append(policy.AllowedTargets, req.RuntimeTargetID))
	}
	return policy
}

// evaluatePolicy checks user-facing Operation safety before start.
func evaluatePolicy(op Operation, resolved resolution.Result) OperationPolicyDecision {
	reasons := []string{}
	if op.Policy.SourceControl == "open_pr_only" || op.Policy.SourceControl == "" {
		if containsAny(op.Policy.AllowedTools, []string{"sourcecontrol.open_pull_request"}) || op.WorkflowID != codingWorkflowID {
			return OperationPolicyDecision{Status: "allowed"}
		}
		reasons = append(reasons, "open pull request permission is missing")
	}
	for _, unresolved := range resolved.Unresolved {
		reasons = append(reasons, "missing "+unresolved.Name)
	}
	if len(reasons) > 0 {
		return OperationPolicyDecision{Status: "blocked", Reasons: reasons}
	}
	return OperationPolicyDecision{Status: "allowed"}
}

// requestInput returns a non-nil run request input map.
func requestInput(req OperationRunRequest) map[string]any {
	input := cloneMap(req.Input)
	if req.Task != nil {
		if title := taskString(req.Task, "title"); title != "" && input["change_request"] == nil {
			input["change_request"] = title
		}
		if body := taskString(req.Task, "body"); body != "" && input["change_request"] == nil {
			input["change_request"] = body
		}
	}
	return secretReferenceSafeInput(input)
}

// taskString returns one trimmed string from structured task context.
func taskString(task map[string]any, key string) string {
	if task == nil {
		return ""
	}
	value, ok := task[key].(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(value)
}

// firstNonEmpty returns the first non-empty string.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

// codebaseDefaultInput maps catalog fields onto workflow input names.
func codebaseDefaultInput(codebase Codebase) map[string]any {
	values := map[string]any{}
	if codebase.ID != "" {
		values["codebase_id"] = codebase.ID
	}
	if codebase.RepositoryPath != "" {
		values["repository_path"] = codebase.RepositoryPath
	}
	if codebase.DefaultRemote != "" {
		values["remote"] = codebase.DefaultRemote
	}
	if codebase.DefaultBranch != "" {
		values["base_ref"] = codebase.DefaultBranch
		values["pull_request_base"] = codebase.DefaultBranch
	}
	if codebase.GoModulePath != "" {
		values["go_module_path"] = codebase.GoModulePath
	}
	if codebase.RuntimeTargetID != "" {
		values["runtime_target_id"] = codebase.RuntimeTargetID
	}
	if codebase.AgentProfileID != "" {
		values["agent_profile_id"] = codebase.AgentProfileID
	}
	return values
}

// generatedInput builds deterministic generated coding fields.
func generatedInput(op Operation, codebase Codebase, req OperationRunRequest) map[string]any {
	input := requestInput(req)
	changeRequest, _ := input["change_request"].(string)
	taskBody := taskString(req.Task, "body")
	if taskBody == "" {
		taskBody = taskString(req.Task, "description")
	}
	branchSummary := strings.TrimSpace(changeRequest)
	if branchSummary == "" {
		branchSummary = strings.TrimSpace(op.Name)
	}
	branch := "aa-" + slug(branchSummary)
	if branch == "aa-" {
		branch = "aa-change"
	}
	values := map[string]any{
		"branch_summary":     branchSummary,
		"branch":             branch,
		"commit_message":     branchSummary,
		"pull_request_title": branchSummary,
		"pull_request_body":  firstNonEmpty(taskBody, branchSummary),
		"worktree_path":      filepath.Join("build", "sourcecontrol", "worktrees", strings.ReplaceAll(branch, "/", "_")),
	}
	if _, ok := input["pull_request_draft"]; !ok {
		values["pull_request_draft"] = false
	}
	if codebase.DefaultRemote == "" {
		values["remote"] = "origin"
	}
	if codebase.DefaultBranch == "" {
		values["base_ref"] = "HEAD"
	}
	return values
}

// secretReferenceInput maps secret bindings onto resolver fields.
func secretReferenceInput(bindings []OperationSecretBinding) map[string]any {
	values := map[string]any{}
	for _, binding := range bindings {
		if strings.TrimSpace(binding.Name) != "" && strings.TrimSpace(binding.Ref) != "" {
			values[strings.TrimSpace(binding.Name)] = strings.TrimSpace(binding.Ref)
		}
	}
	return values
}

// requiredFieldsForWorkflow returns the first-pass workflow input contract.
func requiredFieldsForWorkflow(workflowID string) []string {
	if workflowID == codingWorkflowID {
		return []string{
			"repository_path",
			"change_request",
			"branch_summary",
			"commit_message",
			"base_ref",
			"remote",
			"go_module_path",
			"pull_request_base",
			"pull_request_title",
			"pull_request_body",
			"pull_request_draft",
		}
	}
	return nil
}

// defaultWorkflowInput returns conservative first-pass workflow-level defaults.
func defaultWorkflowInput(workflowID string) map[string]any {
	if workflowID != codingWorkflowID {
		return map[string]any{}
	}
	return map[string]any{
		"remote":             "origin",
		"base_ref":           "HEAD",
		"go_module_path":     ".",
		"binary_path":        "",
		"binary_package":     ".",
		"binary_arg_1":       "",
		"binary_arg_2":       "",
		"codex_home":         "",
		"pull_request_base":  "HEAD",
		"pull_request_draft": false,
	}
}

// mergeDefaults overlays configured workflow defaults onto built-in defaults.
func mergeDefaults(base map[string]any, overlay map[string]any) map[string]any {
	merged := cloneMap(base)
	for key, value := range overlay {
		merged[key] = value
	}
	return merged
}

// unresolvedNames returns unresolved field names from a resolution result.
func unresolvedNames(result resolution.Result) []string {
	names := make([]string, 0, len(result.Unresolved))
	for _, item := range result.Unresolved {
		names = append(names, item.Name)
	}
	return names
}

// resolutionMap converts resolution output to a serializable map.
func resolutionMap(result resolution.Result) map[string]any {
	data, _ := json.Marshal(result)
	var out map[string]any
	_ = json.Unmarshal(data, &out)
	return out
}

// cloneMap copies one map.
func cloneMap(values map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range values {
		out[key] = value
	}
	return out
}

// normalizeOperationID canonicalizes an Operation id.
func normalizeOperationID(value string) string {
	return strings.Trim(strings.ToLower(strings.TrimSpace(value)), "_-")
}

// slug returns a conservative identifier fragment.
func slug(value string) string {
	var builder strings.Builder
	lastDash := false
	for _, item := range strings.ToLower(strings.TrimSpace(value)) {
		switch {
		case item >= 'a' && item <= 'z':
			builder.WriteRune(item)
			lastDash = false
		case item >= '0' && item <= '9':
			builder.WriteRune(item)
			lastDash = false
		default:
			if !lastDash && builder.Len() > 0 {
				builder.WriteByte('_')
				lastDash = true
			}
		}
	}
	return strings.Trim(builder.String(), "_")
}

// uniqueStrings trims and deduplicates strings.
func uniqueStrings(values []string) []string {
	seen := map[string]struct{}{}
	out := []string{}
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		out = append(out, trimmed)
	}
	return out
}

// containsAny reports whether values contains at least one target.
func containsAny(values []string, targets []string) bool {
	set := map[string]struct{}{}
	for _, value := range values {
		set[value] = struct{}{}
	}
	for _, target := range targets {
		if _, ok := set[target]; ok {
			return true
		}
	}
	return false
}

// operationScheduleDue reports whether a cron-like schedule is due at now.
func operationScheduleDue(schedule OperationSchedule, now time.Time) bool {
	cron := strings.TrimSpace(schedule.Cron)
	if cron == "" {
		return false
	}
	fields := strings.Fields(cron)
	if len(fields) != 5 {
		return false
	}
	utc := now.UTC()
	weekday := int(utc.Weekday())
	return cronFieldMatches(fields[0], utc.Minute(), 0, 59, false) &&
		cronFieldMatches(fields[1], utc.Hour(), 0, 23, false) &&
		cronFieldMatches(fields[2], utc.Day(), 1, 31, false) &&
		cronFieldMatches(fields[3], int(utc.Month()), 1, 12, false) &&
		cronFieldMatches(fields[4], weekday, 0, 7, true)
}

// cronFieldMatches checks one simple cron field.
func cronFieldMatches(field string, value int, min int, max int, sundayAlias bool) bool {
	field = strings.TrimSpace(field)
	if field == "*" {
		return true
	}
	if strings.HasPrefix(field, "*/") {
		step, err := strconv.Atoi(strings.TrimPrefix(field, "*/"))
		if err != nil || step <= 0 {
			return false
		}
		return value%step == 0
	}
	for _, part := range strings.Split(field, ",") {
		target, err := strconv.Atoi(strings.TrimSpace(part))
		if err != nil {
			return false
		}
		if sundayAlias && target == 7 {
			target = 0
		}
		if target < min || target > max {
			return false
		}
		if target == value {
			return true
		}
	}
	return false
}

// operationScheduleStopped reports whether a schedule stop time has passed.
func operationScheduleStopped(schedule OperationSchedule, now time.Time) bool {
	if strings.TrimSpace(schedule.StopAt) == "" {
		return false
	}
	stopAt, err := time.Parse(time.RFC3339, schedule.StopAt)
	if err != nil {
		return true
	}
	return now.UTC().After(stopAt.UTC())
}

// operationScheduleInQuietHours reports whether now is inside quiet hours.
func operationScheduleInQuietHours(schedule OperationSchedule, now time.Time) bool {
	start, okStart := parseScheduleClock(schedule.QuietHoursStart)
	end, okEnd := parseScheduleClock(schedule.QuietHoursEnd)
	if !okStart || !okEnd || start == end {
		return false
	}
	current := now.UTC().Hour()*60 + now.UTC().Minute()
	if start < end {
		return current >= start && current < end
	}
	return current >= start || current < end
}

// parseScheduleClock parses HH:MM schedule clock values.
func parseScheduleClock(value string) (int, bool) {
	parts := strings.Split(strings.TrimSpace(value), ":")
	if len(parts) != 2 {
		return 0, false
	}
	hour, err := strconv.Atoi(parts[0])
	if err != nil || hour < 0 || hour > 23 {
		return 0, false
	}
	minute, err := strconv.Atoi(parts[1])
	if err != nil || minute < 0 || minute > 59 {
		return 0, false
	}
	return hour*60 + minute, true
}

// maxAttemptsForPolicy converts retry policy into a total attempt count.
func maxAttemptsForPolicy(policy OperationPolicy) int {
	if policy.RetryLimit < 0 {
		return 1
	}
	return policy.RetryLimit + 1
}

// operationRunLeaseExpiry returns the bounded lease expiry timestamp.
func operationRunLeaseExpiry(seconds int) string {
	if seconds <= 0 {
		seconds = defaultOperationRunLeaseSeconds
	}
	if seconds > maxOperationRunLeaseSeconds {
		seconds = maxOperationRunLeaseSeconds
	}
	return time.Now().UTC().Add(time.Duration(seconds) * time.Second).Format(time.RFC3339)
}

// operationRunLeaseExpired reports whether a lease timestamp is in the past.
func operationRunLeaseExpired(value string) bool {
	if strings.TrimSpace(value) == "" {
		return true
	}
	expiresAt, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return true
	}
	return !expiresAt.After(time.Now().UTC())
}

// isTerminalQueueStatus reports whether a release status ends queue ownership.
func isTerminalQueueStatus(status string) bool {
	switch status {
	case OperationRunQueueStatusCompleted, OperationRunQueueStatusFailed, OperationRunQueueStatusCanceled:
		return true
	default:
		return false
	}
}

// displaySafeRequestInput returns request input without secret-like values.
func displaySafeRequestInput(req OperationRunRequest) map[string]any {
	return redactSensitiveMap(requestInput(req))
}

// secretReferenceSafeInput replaces raw secret-like request values with refs.
func secretReferenceSafeInput(values map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range values {
		if !sensitiveInputKey(key) {
			out[key] = value
			continue
		}
		if reference, ok := value.(string); ok && strings.HasPrefix(strings.TrimSpace(reference), "secret://") {
			out[key] = strings.TrimSpace(reference)
			continue
		}
		out[key] = "secret://redacted/" + strings.TrimSpace(key)
	}
	return out
}

// redactSensitiveMap recursively redacts values under secret-like keys.
func redactSensitiveMap(values map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range values {
		if sensitiveInputKey(key) {
			out[key] = "[redacted]"
			continue
		}
		out[key] = redactSensitiveValue(value)
	}
	return out
}

// redactSensitiveValue redacts nested map values while preserving shape.
func redactSensitiveValue(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		return redactSensitiveMap(typed)
	case map[any]any:
		next := map[string]any{}
		for key, item := range typed {
			next[fmt.Sprint(key)] = item
		}
		return redactSensitiveMap(next)
	case []any:
		out := make([]any, 0, len(typed))
		for _, item := range typed {
			out = append(out, redactSensitiveValue(item))
		}
		return out
	default:
		return value
	}
}

// sensitiveInputKey reports whether a request field name is secret-like.
func sensitiveInputKey(key string) bool {
	normalized := strings.ToLower(strings.TrimSpace(key))
	return strings.Contains(normalized, "secret") ||
		strings.Contains(normalized, "token") ||
		strings.Contains(normalized, "password") ||
		strings.Contains(normalized, "credential") ||
		strings.Contains(normalized, "api_key") ||
		strings.Contains(normalized, "apikey")
}

// randomHexID creates a collision-resistant id with a stable prefix.
func randomHexID(prefix string) (string, error) {
	var data [12]byte
	if _, err := rand.Read(data[:]); err != nil {
		return "", fmt.Errorf("generate %s id: %w", prefix, err)
	}
	return normalizeOperationID(prefix) + "_" + hex.EncodeToString(data[:]), nil
}

// hashOperation returns a stable hash for version snapshots.
func hashOperation(op Operation) string {
	data, _ := json.Marshal(op)
	return hashString(data)
}

// hashString returns a stable SHA-256 hex digest.
func hashString(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
