// This file implements the Launchpad service boundary.
package launchpad

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"agentawesome/internal/services/launchpad/resolution"
)

const (
	defaultLaunchStatus          = "active"
	defaultLaunchRunLeaseSeconds = 300
	maxLaunchRunLeaseSeconds     = 3600
)

var launchIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)

// RunbookExecutor starts runbook runs for resolved Launchpad.
type RunbookExecutor interface {
	StartRunbook(context.Context, string, map[string]any) (RunbookRun, error)
	RunbookDefaults(context.Context, string) (map[string]any, string, error)
}

// CodebaseCatalog resolves memory-backed codebase records.
type CodebaseCatalog interface {
	GetCodebase(context.Context, string) (Codebase, error)
	ResolveCodebase(context.Context, string) (CodebaseResolution, error)
}

// Service owns Launch setup, resolution, policy, and run links.
type Service struct {
	store     *Store
	runbook  RunbookExecutor
	codebases CodebaseCatalog
	resolver  resolution.Resolver
}

// NewService creates an Launchpad service.
func NewService(store *Store, runbook RunbookExecutor, codebases CodebaseCatalog) *Service {
	return &Service{store: store, runbook: runbook, codebases: codebases, resolver: resolution.NewResolver()}
}

// CreateLaunch validates and stores a new Launch.
func (s *Service) CreateLaunch(ctx context.Context, req LaunchRequest) (Launch, error) {
	op, err := launchFromRequest(req, true)
	if err != nil {
		return Launch{}, err
	}
	if err := s.store.UpsertLaunch(ctx, op); err != nil {
		return Launch{}, err
	}
	return s.store.GetLaunch(ctx, op.ID)
}

// UpdateLaunch replaces one existing Launch.
func (s *Service) UpdateLaunch(ctx context.Context, id string, req LaunchRequest) (Launch, error) {
	req.ID = strings.TrimSpace(id)
	op, err := launchFromRequest(req, false)
	if err != nil {
		return Launch{}, err
	}
	existing, err := s.store.GetLaunch(ctx, op.ID)
	if err != nil {
		return Launch{}, err
	}
	op.CreatedAt = existing.CreatedAt
	op.Version = existing.Version
	if err := s.store.UpsertLaunch(ctx, op); err != nil {
		return Launch{}, err
	}
	return s.store.GetLaunch(ctx, op.ID)
}

// GetLaunch loads one saved Launch.
func (s *Service) GetLaunch(ctx context.Context, id string) (Launch, error) {
	return s.store.GetLaunch(ctx, id)
}

// ListLaunchpad lists saved Launchpad.
func (s *Service) ListLaunchpad(ctx context.Context, query LaunchQuery) ([]Launch, error) {
	return s.store.ListLaunchpad(ctx, query)
}

// DeleteLaunch removes one saved Launch.
func (s *Service) DeleteLaunch(ctx context.Context, id string) error {
	return s.store.DeleteLaunch(ctx, id)
}

// GetLaunchRunSnapshot loads immutable Launch audit data for a run.
func (s *Service) GetLaunchRunSnapshot(ctx context.Context, runID string) (LaunchRunSnapshot, error) {
	return s.store.GetRunSnapshot(ctx, runID)
}

// PreviewLaunchRun resolves input and policy without starting a runbook.
func (s *Service) PreviewLaunchRun(ctx context.Context, launchID string, req LaunchRunRequest) (LaunchPreview, error) {
	op, err := s.store.GetLaunch(ctx, launchID)
	if err != nil {
		return LaunchPreview{}, err
	}
	resolved, err := s.ResolveLaunchInput(ctx, op, req)
	if err != nil {
		return LaunchPreview{}, err
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
	return LaunchPreview{
		Launch:      op,
		ResolvedInput:  resolved.Input,
		Resolution:     resolutionMap(resolved),
		MissingSetup:   missing,
		PolicyDecision: decision,
		Status:         status,
	}, nil
}

// StartLaunch resolves input, records a snapshot, and starts a runbook run.
func (s *Service) StartLaunch(ctx context.Context, launchID string, req LaunchRunRequest) (LaunchStartResult, error) {
	preview, err := s.PreviewLaunchRun(ctx, launchID, req)
	if err != nil {
		return LaunchStartResult{}, err
	}
	if len(preview.MissingSetup) > 0 {
		return LaunchStartResult{}, fmt.Errorf("launch needs input: %s", strings.Join(preview.MissingSetup, ", "))
	}
	if preview.PolicyDecision.Status != "allowed" {
		return LaunchStartResult{}, fmt.Errorf("launch policy blocked start: %s", strings.Join(preview.PolicyDecision.Reasons, "; "))
	}
	run, err := s.runbook.StartRunbook(ctx, preview.Launch.RunbookID, preview.ResolvedInput)
	if err != nil {
		return LaunchStartResult{}, err
	}
	link := LaunchRunLink{LaunchID: preview.Launch.ID, RunID: run.ID}
	if err := s.store.InsertRunLink(ctx, link); err != nil {
		return LaunchStartResult{}, err
	}
	snapshot := LaunchRunSnapshot{
		RunID:            run.ID,
		LaunchID:      preview.Launch.ID,
		LaunchVersion: preview.Launch.Version,
		RunbookID:       preview.Launch.RunbookID,
		RunbookVersion:  preview.Launch.RunbookVersion,
		ResolvedInput:    preview.ResolvedInput,
		Resolution:       preview.Resolution,
		Target: LaunchTarget{
			RuntimeTargetID: preview.Launch.RuntimeTargetID,
			AgentProfileID:  preview.Launch.AgentProfileID,
		},
		Policy:     preview.Launch.Policy,
		SecretRefs: preview.Launch.SecretRefs,
	}
	if err := s.store.InsertRunSnapshot(ctx, snapshot); err != nil {
		return LaunchStartResult{}, err
	}
	link.CreatedAt = timestampNow()
	snapshot.CreatedAt = link.CreatedAt
	return LaunchStartResult{Launch: preview.Launch, Run: run, Preview: preview, Link: link, Snapshot: snapshot}, nil
}

// EnqueueLaunchRun stores a resolved Launch run for a target worker.
func (s *Service) EnqueueLaunchRun(ctx context.Context, launchID string, req LaunchRunRequest) (LaunchRunQueueItem, error) {
	preview, err := s.PreviewLaunchRun(ctx, launchID, req)
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	if len(preview.MissingSetup) > 0 {
		return LaunchRunQueueItem{}, fmt.Errorf("launch needs input: %s", strings.Join(preview.MissingSetup, ", "))
	}
	if preview.PolicyDecision.Status != "allowed" {
		return LaunchRunQueueItem{}, fmt.Errorf("launch policy blocked enqueue: %s", strings.Join(preview.PolicyDecision.Reasons, "; "))
	}
	id, err := randomHexID("oprun")
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	now := timestampNow()
	item := LaunchRunQueueItem{
		ID:               id,
		LaunchID:      preview.Launch.ID,
		LaunchVersion: preview.Launch.Version,
		LaunchHash:    hashLaunch(preview.Launch),
		RunbookID:       preview.Launch.RunbookID,
		RunbookVersion:  preview.Launch.RunbookVersion,
		Target: LaunchTarget{
			RuntimeTargetID: preview.Launch.RuntimeTargetID,
			AgentProfileID:  preview.Launch.AgentProfileID,
		},
		Policy:         preview.Launch.Policy,
		PolicyDecision: preview.PolicyDecision,
		SecretRefs:     preview.Launch.SecretRefs,
		ResolvedInput:  preview.ResolvedInput,
		Resolution:     preview.Resolution,
		RequestInput:   displaySafeRequestInput(req),
		Source:         strings.TrimSpace(req.Source),
		Status:         LaunchRunQueueStatusQueued,
		MaxAttempts:    maxAttemptsForPolicy(preview.Launch.Policy),
		EnqueuedAt:     now,
		UpdatedAt:      now,
	}
	if err := s.store.InsertRunQueueItem(ctx, item); err != nil {
		return LaunchRunQueueItem{}, err
	}
	return s.store.GetRunQueueItem(ctx, item.ID)
}

// ListQueuedLaunchRuns lists durable queued Launch runs.
func (s *Service) ListQueuedLaunchRuns(ctx context.Context, query LaunchRunQueueQuery) ([]LaunchRunQueueItem, error) {
	return s.store.ListRunQueueItems(ctx, query)
}

// LeaseQueuedLaunchRun leases one eligible queued run for a target worker.
func (s *Service) LeaseQueuedLaunchRun(ctx context.Context, req LaunchRunLeaseRequest) (LaunchRunLease, error) {
	targetID := strings.TrimSpace(req.TargetID)
	if targetID == "" {
		return LaunchRunLease{}, errors.New("target_id is required")
	}
	leaseID, err := randomHexID("lease")
	if err != nil {
		return LaunchRunLease{}, err
	}
	expiresAt := launchRunLeaseExpiry(req.LeaseSeconds)
	item, err := s.store.LeaseNextRunQueueItem(ctx, targetID, leaseID, expiresAt)
	if err != nil {
		return LaunchRunLease{}, err
	}
	return LaunchRunLease{Item: item, LeaseID: leaseID, LeaseExpiresAt: expiresAt}, nil
}

// RenewQueuedLaunchRunLease extends a live target worker lease.
func (s *Service) RenewQueuedLaunchRunLease(ctx context.Context, queueID string, req LaunchRunLeaseRenewRequest) (LaunchRunLease, error) {
	leaseID := strings.TrimSpace(req.LeaseID)
	if leaseID == "" {
		return LaunchRunLease{}, errors.New("lease_id is required")
	}
	expiresAt := launchRunLeaseExpiry(req.LeaseSeconds)
	item, err := s.store.RenewRunQueueLease(ctx, queueID, leaseID, expiresAt)
	if err != nil {
		return LaunchRunLease{}, err
	}
	return LaunchRunLease{Item: item, LeaseID: leaseID, LeaseExpiresAt: expiresAt}, nil
}

// StartQueuedLaunchRun starts a runbook run from an active queue lease.
func (s *Service) StartQueuedLaunchRun(ctx context.Context, queueID string, leaseID string) (LaunchRunQueueStartResult, error) {
	item, err := s.store.GetRunQueueItem(ctx, queueID)
	if err != nil {
		return LaunchRunQueueStartResult{}, err
	}
	if item.Status != LaunchRunQueueStatusLeased {
		return LaunchRunQueueStartResult{}, fmt.Errorf("queued run %q is %s, not leased", item.ID, item.Status)
	}
	if item.LeaseID != strings.TrimSpace(leaseID) {
		return LaunchRunQueueStartResult{}, errors.New("lease_id does not match queued run")
	}
	if launchRunLeaseExpired(item.LeaseExpiresAt) {
		return LaunchRunQueueStartResult{}, errors.New("queued run lease expired")
	}
	run, err := s.runbook.StartRunbook(ctx, item.RunbookID, item.ResolvedInput)
	if err != nil {
		return LaunchRunQueueStartResult{}, err
	}
	link := LaunchRunLink{LaunchID: item.LaunchID, RunID: run.ID}
	if err := s.store.InsertRunLink(ctx, link); err != nil {
		return LaunchRunQueueStartResult{}, err
	}
	snapshot := LaunchRunSnapshot{
		RunID:            run.ID,
		LaunchID:      item.LaunchID,
		LaunchVersion: item.LaunchVersion,
		RunbookID:       item.RunbookID,
		RunbookVersion:  item.RunbookVersion,
		ResolvedInput:    item.ResolvedInput,
		Resolution:       item.Resolution,
		Target:           item.Target,
		Policy:           item.Policy,
		SecretRefs:       item.SecretRefs,
	}
	if err := s.store.InsertRunSnapshot(ctx, snapshot); err != nil {
		return LaunchRunQueueStartResult{}, err
	}
	item, err = s.store.MarkRunQueueItemRunning(ctx, item.ID, leaseID, run.ID)
	if err != nil {
		return LaunchRunQueueStartResult{}, err
	}
	link.CreatedAt = timestampNow()
	snapshot.CreatedAt = link.CreatedAt
	return LaunchRunQueueStartResult{Item: item, Run: run, Link: link, Snapshot: snapshot}, nil
}

// ReleaseQueuedLaunchRunLease marks a leased queued run complete or failed.
func (s *Service) ReleaseQueuedLaunchRunLease(ctx context.Context, queueID string, req LaunchRunLeaseReleaseRequest) (LaunchRunQueueItem, error) {
	if strings.TrimSpace(req.LeaseID) == "" {
		return LaunchRunQueueItem{}, errors.New("lease_id is required")
	}
	req.Status = strings.TrimSpace(req.Status)
	if req.Status == "" {
		req.Status = LaunchRunQueueStatusCompleted
	}
	if !isTerminalQueueStatus(req.Status) {
		return LaunchRunQueueItem{}, fmt.Errorf("queue release status %q is not terminal", req.Status)
	}
	return s.store.ReleaseRunQueueLease(ctx, queueID, req)
}

// CancelQueuedLaunchRun cancels one queued run before completion.
func (s *Service) CancelQueuedLaunchRun(ctx context.Context, queueID string) (LaunchRunQueueItem, error) {
	return s.store.CancelRunQueueItem(ctx, queueID)
}

// RecoverExpiredQueuedLaunchRunLeases returns expired leases to the queue.
func (s *Service) RecoverExpiredQueuedLaunchRunLeases(ctx context.Context) (int, error) {
	return s.store.RecoverExpiredRunQueueLeases(ctx, timestampNow())
}

// EnqueueDueScheduledLaunchpad queues due scheduled Launchpad.
func (s *Service) EnqueueDueScheduledLaunchpad(ctx context.Context, now time.Time) (LaunchScheduleResult, error) {
	ops, err := s.store.ListLaunchpad(ctx, LaunchQuery{Status: defaultLaunchStatus})
	if err != nil {
		return LaunchScheduleResult{}, err
	}
	result := LaunchScheduleResult{Checked: len(ops)}
	for _, op := range ops {
		if !op.Schedule.Enabled {
			continue
		}
		if !launchScheduleDue(op.Schedule, now) {
			continue
		}
		if launchScheduleStopped(op.Schedule, now) {
			result.Skipped = append(result.Skipped, LaunchScheduleSkip{LaunchID: op.ID, Reason: "schedule window ended"})
			continue
		}
		if launchScheduleInQuietHours(op.Schedule, now) {
			result.Skipped = append(result.Skipped, LaunchScheduleSkip{LaunchID: op.ID, Reason: "quiet hours"})
			continue
		}
		if op.Schedule.MaxRuns > 0 {
			count, err := s.store.CountRunQueueItems(ctx, op.ID)
			if err != nil {
				return result, err
			}
			if count >= op.Schedule.MaxRuns {
				result.Skipped = append(result.Skipped, LaunchScheduleSkip{LaunchID: op.ID, Reason: "max scheduled runs reached"})
				continue
			}
		}
		maxParallel := op.Policy.MaxParallelism
		if maxParallel <= 0 {
			maxParallel = 1
		}
		active, err := s.store.CountRunQueueItems(ctx, op.ID, LaunchRunQueueStatusQueued, LaunchRunQueueStatusLeased, LaunchRunQueueStatusRunning)
		if err != nil {
			return result, err
		}
		if active >= maxParallel {
			result.Skipped = append(result.Skipped, LaunchScheduleSkip{LaunchID: op.ID, Reason: "max parallel runs active"})
			continue
		}
		item, err := s.EnqueueLaunchRun(ctx, op.ID, LaunchRunRequest{Source: "schedule"})
		if err != nil {
			result.Skipped = append(result.Skipped, LaunchScheduleSkip{LaunchID: op.ID, Reason: err.Error()})
			continue
		}
		result.Enqueued = append(result.Enqueued, item)
	}
	return result, nil
}

// ResolveLaunchInput applies the shared input resolver for one Launch.
func (s *Service) ResolveLaunchInput(ctx context.Context, op Launch, req LaunchRunRequest) (resolution.Result, error) {
	codebase, codebaseDiagnostics, err := s.launchCodebase(ctx, op, req)
	if err != nil {
		return resolution.Result{}, err
	}
	runbookDefaults, runbookVersion, err := s.runbook.RunbookDefaults(ctx, op.RunbookID)
	if err != nil {
		return resolution.Result{}, err
	}
	if op.RunbookVersion == "" {
		op.RunbookVersion = runbookVersion
	}
	codebaseDefaults := codebaseDefaultInput(codebase)
	secretRefs := secretReferenceInput(op.SecretRefs)
	result, err := s.resolver.Resolve(ctx, resolution.Request{
		RunRequest:        requestInput(req),
		LaunchDefaults: op.Defaults,
		CodebaseDefaults:  codebaseDefaults,
		RunbookDefaults:  runbookDefaults,
		GeneratedValues:   map[string]any{},
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

// launchCodebase returns the codebase bound to a run request or Launch.
func (s *Service) launchCodebase(ctx context.Context, op Launch, req LaunchRunRequest) (Codebase, []string, error) {
	codebaseName := strings.TrimSpace(req.CodebaseName)
	inputCodebaseID := ""
	if codebaseID, ok := req.Input["codebase_id"].(string); ok {
		inputCodebaseID = strings.TrimSpace(codebaseID)
	}
	launchCodebaseID := strings.TrimSpace(op.CodebaseID)
	if codebaseName == "" && inputCodebaseID == "" && launchCodebaseID == "" {
		return Codebase{}, nil, nil
	}
	if s.codebases == nil {
		return Codebase{}, nil, errors.New("codebase catalog is not configured")
	}
	if codebaseName != "" {
		resolved, err := s.codebases.ResolveCodebase(ctx, codebaseName)
		if err != nil {
			return Codebase{}, nil, err
		}
		if resolved.Status != "matched" || resolved.Codebase == nil {
			return Codebase{}, resolved.Diagnostics, fmt.Errorf("codebase %q was not resolved: %s", codebaseName, resolved.Status)
		}
		return *resolved.Codebase, resolved.Diagnostics, nil
	}
	if inputCodebaseID != "" {
		codebase, err := s.codebases.GetCodebase(ctx, inputCodebaseID)
		return codebase, nil, err
	}
	codebase, err := s.codebases.GetCodebase(ctx, launchCodebaseID)
	return codebase, nil, err
}

// launchFromRequest normalizes a create or update request.
func launchFromRequest(req LaunchRequest, create bool) (Launch, error) {
	id := normalizeLaunchID(req.ID)
	if id == "" && create {
		id = normalizeLaunchID(slug(req.Name))
	}
	if id == "" || !launchIDPattern.MatchString(id) {
		return Launch{}, fmt.Errorf("launch id is required and must be stable")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return Launch{}, errors.New("launch name is required")
	}
	runbookID := strings.TrimSpace(req.RunbookID)
	if runbookID == "" {
		return Launch{}, errors.New("runbook_id is required")
	}
	status := strings.TrimSpace(req.Status)
	if status == "" {
		status = defaultLaunchStatus
	}
	policy := req.Policy
	version := 1
	return Launch{
		ID:              id,
		Name:            name,
		RunbookID:      runbookID,
		RunbookVersion: strings.TrimSpace(req.RunbookVersion),
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

// evaluatePolicy checks user-facing Launch safety before start.
func evaluatePolicy(op Launch, resolved resolution.Result) LaunchPolicyDecision {
	reasons := []string{}
	if op.Policy.SourceControl == "open_pr_only" {
		if !containsAny(op.Policy.AllowedTools, []string{"sourcecontrol.open_pull_request"}) {
			reasons = append(reasons, "open pull request permission is missing")
		}
	}
	for _, unresolved := range resolved.Unresolved {
		reasons = append(reasons, "missing "+unresolved.Name)
	}
	if len(reasons) > 0 {
		return LaunchPolicyDecision{Status: "blocked", Reasons: reasons}
	}
	return LaunchPolicyDecision{Status: "allowed"}
}

// requestInput returns a non-nil run request input map.
func requestInput(req LaunchRunRequest) map[string]any {
	input := cloneMap(req.Input)
	if req.Task != nil {
		if _, ok := input["task"]; !ok {
			input["task"] = cloneMap(req.Task)
		}
	}
	return secretReferenceSafeInput(input)
}

// codebaseDefaultInput maps catalog fields onto runbook input names.
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
	if codebase.RuntimeTargetID != "" {
		values["runtime_target_id"] = codebase.RuntimeTargetID
	}
	if codebase.AgentProfileID != "" {
		values["agent_profile_id"] = codebase.AgentProfileID
	}
	return values
}

// secretReferenceInput maps secret bindings onto resolver fields.
func secretReferenceInput(bindings []LaunchSecretBinding) map[string]any {
	values := map[string]any{}
	for _, binding := range bindings {
		if strings.TrimSpace(binding.Name) != "" && strings.TrimSpace(binding.Ref) != "" {
			values[strings.TrimSpace(binding.Name)] = strings.TrimSpace(binding.Ref)
		}
	}
	return values
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

// normalizeLaunchID canonicalizes an Launch id.
func normalizeLaunchID(value string) string {
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

// launchScheduleDue reports whether a cron-like schedule is due at now.
func launchScheduleDue(schedule LaunchSchedule, now time.Time) bool {
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

// launchScheduleStopped reports whether a schedule stop time has passed.
func launchScheduleStopped(schedule LaunchSchedule, now time.Time) bool {
	if strings.TrimSpace(schedule.StopAt) == "" {
		return false
	}
	stopAt, err := time.Parse(time.RFC3339, schedule.StopAt)
	if err != nil {
		return true
	}
	return now.UTC().After(stopAt.UTC())
}

// launchScheduleInQuietHours reports whether now is inside quiet hours.
func launchScheduleInQuietHours(schedule LaunchSchedule, now time.Time) bool {
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
func maxAttemptsForPolicy(policy LaunchPolicy) int {
	if policy.RetryLimit < 0 {
		return 1
	}
	return policy.RetryLimit + 1
}

// launchRunLeaseExpiry returns the bounded lease expiry timestamp.
func launchRunLeaseExpiry(seconds int) string {
	if seconds <= 0 {
		seconds = defaultLaunchRunLeaseSeconds
	}
	if seconds > maxLaunchRunLeaseSeconds {
		seconds = maxLaunchRunLeaseSeconds
	}
	return time.Now().UTC().Add(time.Duration(seconds) * time.Second).Format(time.RFC3339)
}

// launchRunLeaseExpired reports whether a lease timestamp is in the past.
func launchRunLeaseExpired(value string) bool {
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
	case LaunchRunQueueStatusCompleted, LaunchRunQueueStatusFailed, LaunchRunQueueStatusCanceled:
		return true
	default:
		return false
	}
}

// displaySafeRequestInput returns request input without secret-like values.
func displaySafeRequestInput(req LaunchRunRequest) map[string]any {
	return redactSensitiveMap(requestInput(req))
}

// secretReferenceSafeInput replaces raw secret-like request values with refs.
func secretReferenceSafeInput(values map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range values {
		if !sensitiveInputKey(key) {
			out[key] = secretReferenceSafeValue(value)
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

// secretReferenceSafeValue redacts nested secret-like values while preserving shape.
func secretReferenceSafeValue(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		return secretReferenceSafeInput(typed)
	case map[any]any:
		next := map[string]any{}
		for key, item := range typed {
			next[fmt.Sprint(key)] = item
		}
		return secretReferenceSafeInput(next)
	case []any:
		out := make([]any, 0, len(typed))
		for _, item := range typed {
			out = append(out, secretReferenceSafeValue(item))
		}
		return out
	default:
		return value
	}
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
	return normalizeLaunchID(prefix) + "_" + hex.EncodeToString(data[:]), nil
}

// hashLaunch returns a stable hash for version snapshots.
func hashLaunch(op Launch) string {
	data, _ := json.Marshal(op)
	return hashString(data)
}

// hashString returns a stable SHA-256 hex digest.
func hashString(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
