// This file stores Operations-owned records in SQLite.
package operations

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/glebarez/go-sqlite"
)

const operationsSQLiteBusyTimeoutPragma = "busy_timeout=5000"

// Store owns Operations persistence tables.
type Store struct {
	db *sql.DB
}

// OpenStore creates the Operations database and applies schema.
func OpenStore(ctx context.Context, path string) (*Store, error) {
	resolved := strings.TrimSpace(path)
	if resolved == "" {
		return nil, fmt.Errorf("operations database path is required")
	}
	if err := ensureOperationsPath(resolved); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", operationsDatabaseDSN(resolved))
	if err != nil {
		return nil, fmt.Errorf("open operations database %q: %w", resolved, err)
	}
	store := &Store{db: db}
	if err := store.migrate(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

// Close releases the Operations database handle.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

// UpsertOperation stores or replaces one Operation.
func (s *Store) UpsertOperation(ctx context.Context, op Operation) error {
	now := timestampNow()
	if op.CreatedAt == "" {
		op.CreatedAt = now
	}
	op.UpdatedAt = now
	defaults, err := encodeMap(op.Defaults)
	if err != nil {
		return err
	}
	policy, err := encodeJSON(op.Policy)
	if err != nil {
		return err
	}
	schedule, err := encodeJSON(op.Schedule)
	if err != nil {
		return err
	}
	secrets, err := encodeJSON(op.SecretRefs)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO operations
		(id, name, workflow_id, workflow_version, codebase_id, runtime_target_id, agent_profile_id, defaults_json, policy_json, schedule_json, secret_refs_json, status, version, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			name = excluded.name,
			workflow_id = excluded.workflow_id,
			workflow_version = excluded.workflow_version,
			codebase_id = excluded.codebase_id,
			runtime_target_id = excluded.runtime_target_id,
			agent_profile_id = excluded.agent_profile_id,
			defaults_json = excluded.defaults_json,
			policy_json = excluded.policy_json,
			schedule_json = excluded.schedule_json,
			secret_refs_json = excluded.secret_refs_json,
			status = excluded.status,
			version = operations.version + 1,
			updated_at = excluded.updated_at`,
		op.ID, op.Name, op.WorkflowID, op.WorkflowVersion, op.CodebaseID, op.RuntimeTargetID, op.AgentProfileID, defaults, policy, schedule, secrets, op.Status, op.Version, op.CreatedAt, op.UpdatedAt)
	if err != nil {
		return fmt.Errorf("upsert operation %q: %w", op.ID, err)
	}
	return nil
}

// GetOperation loads one Operation by id.
func (s *Store) GetOperation(ctx context.Context, id string) (Operation, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, workflow_id, workflow_version, codebase_id, runtime_target_id, agent_profile_id, defaults_json, policy_json, schedule_json, secret_refs_json, status, version, created_at, updated_at FROM operations WHERE id = ?`, strings.TrimSpace(id))
	return scanOperation(row)
}

// ListOperations lists Operations matching a filter.
func (s *Store) ListOperations(ctx context.Context, query OperationQuery) ([]Operation, error) {
	clauses := []string{"1=1"}
	args := []any{}
	if strings.TrimSpace(query.WorkflowID) != "" {
		clauses = append(clauses, "workflow_id = ?")
		args = append(args, strings.TrimSpace(query.WorkflowID))
	}
	if strings.TrimSpace(query.CodebaseID) != "" {
		clauses = append(clauses, "codebase_id = ?")
		args = append(args, strings.TrimSpace(query.CodebaseID))
	}
	if strings.TrimSpace(query.Status) != "" {
		clauses = append(clauses, "status = ?")
		args = append(args, strings.TrimSpace(query.Status))
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, workflow_id, workflow_version, codebase_id, runtime_target_id, agent_profile_id, defaults_json, policy_json, schedule_json, secret_refs_json, status, version, created_at, updated_at FROM operations WHERE `+strings.Join(clauses, " AND ")+` ORDER BY updated_at DESC, id`, args...)
	if err != nil {
		return nil, fmt.Errorf("list operations: %w", err)
	}
	defer rows.Close()
	ops := []Operation{}
	for rows.Next() {
		op, err := scanOperation(rows)
		if err != nil {
			return nil, err
		}
		ops = append(ops, op)
	}
	return ops, rows.Err()
}

// DeleteOperation removes one Operation.
func (s *Store) DeleteOperation(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM operations WHERE id = ?`, strings.TrimSpace(id))
	if err != nil {
		return fmt.Errorf("delete operation %q: %w", id, err)
	}
	return nil
}

// InsertRunLink stores a workflow run link for an Operation.
func (s *Store) InsertRunLink(ctx context.Context, link OperationRunLink) error {
	if link.CreatedAt == "" {
		link.CreatedAt = timestampNow()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO operation_run_links (operation_id, run_id, created_at) VALUES (?, ?, ?)`, link.OperationID, link.RunID, link.CreatedAt)
	if err != nil {
		return fmt.Errorf("insert operation run link: %w", err)
	}
	return nil
}

// InsertRunSnapshot stores one immutable run-start snapshot.
func (s *Store) InsertRunSnapshot(ctx context.Context, snapshot OperationRunSnapshot) error {
	if snapshot.CreatedAt == "" {
		snapshot.CreatedAt = timestampNow()
	}
	resolved, err := encodeMap(snapshot.ResolvedInput)
	if err != nil {
		return err
	}
	resolution, err := encodeMap(snapshot.Resolution)
	if err != nil {
		return err
	}
	target, err := encodeJSON(snapshot.Target)
	if err != nil {
		return err
	}
	policy, err := encodeJSON(snapshot.Policy)
	if err != nil {
		return err
	}
	secrets, err := encodeJSON(snapshot.SecretRefs)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO operation_run_snapshots
		(run_id, operation_id, operation_version, workflow_id, workflow_version, resolved_input_json, resolution_json, target_json, policy_json, secret_refs_json, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		snapshot.RunID, snapshot.OperationID, snapshot.OperationVersion, snapshot.WorkflowID, snapshot.WorkflowVersion, resolved, resolution, target, policy, secrets, snapshot.CreatedAt)
	if err != nil {
		return fmt.Errorf("insert operation run snapshot: %w", err)
	}
	return nil
}

// GetRunSnapshot loads one run snapshot by workflow run id.
func (s *Store) GetRunSnapshot(ctx context.Context, runID string) (OperationRunSnapshot, error) {
	row := s.db.QueryRowContext(ctx, `SELECT run_id, operation_id, operation_version, workflow_id, workflow_version, resolved_input_json, resolution_json, target_json, policy_json, secret_refs_json, created_at FROM operation_run_snapshots WHERE run_id = ?`, strings.TrimSpace(runID))
	return scanRunSnapshot(row)
}

// InsertRunQueueItem stores one durable queued Operation run.
func (s *Store) InsertRunQueueItem(ctx context.Context, item OperationRunQueueItem) error {
	now := timestampNow()
	if item.EnqueuedAt == "" {
		item.EnqueuedAt = now
	}
	if item.UpdatedAt == "" {
		item.UpdatedAt = item.EnqueuedAt
	}
	target, err := encodeJSON(item.Target)
	if err != nil {
		return err
	}
	policy, err := encodeJSON(item.Policy)
	if err != nil {
		return err
	}
	decision, err := encodeJSON(item.PolicyDecision)
	if err != nil {
		return err
	}
	secrets, err := encodeJSON(item.SecretRefs)
	if err != nil {
		return err
	}
	resolved, err := encodeMap(item.ResolvedInput)
	if err != nil {
		return err
	}
	resolution, err := encodeMap(item.Resolution)
	if err != nil {
		return err
	}
	requestInput, err := encodeMap(item.RequestInput)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO operation_run_queue
		(id, operation_id, operation_version, operation_hash, workflow_id, workflow_version, target_runtime_target_id, target_json, policy_json, policy_decision_json, secret_refs_json, resolved_input_json, resolution_json, request_input_json, source, status, attempts, max_attempts, lease_id, leased_by_target_id, lease_expires_at, run_id, last_error, enqueued_at, updated_at, started_at, completed_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		item.ID, item.OperationID, item.OperationVersion, item.OperationHash, item.WorkflowID, item.WorkflowVersion, item.Target.RuntimeTargetID, target, policy, decision, secrets, resolved, resolution, requestInput, item.Source, item.Status, item.Attempts, item.MaxAttempts, item.LeaseID, item.LeasedByTargetID, item.LeaseExpiresAt, item.RunID, item.LastError, item.EnqueuedAt, item.UpdatedAt, item.StartedAt, item.CompletedAt)
	if err != nil {
		return fmt.Errorf("insert operation run queue item: %w", err)
	}
	return nil
}

// GetRunQueueItem loads one queued Operation run.
func (s *Store) GetRunQueueItem(ctx context.Context, id string) (OperationRunQueueItem, error) {
	row := s.db.QueryRowContext(ctx, runQueueSelectSQL()+` WHERE id = ?`, strings.TrimSpace(id))
	return scanRunQueueItem(row)
}

// ListRunQueueItems lists queued Operation runs matching a filter.
func (s *Store) ListRunQueueItems(ctx context.Context, query OperationRunQueueQuery) ([]OperationRunQueueItem, error) {
	clauses := []string{"1=1"}
	args := []any{}
	if strings.TrimSpace(query.OperationID) != "" {
		clauses = append(clauses, "operation_id = ?")
		args = append(args, strings.TrimSpace(query.OperationID))
	}
	if strings.TrimSpace(query.Status) != "" {
		clauses = append(clauses, "status = ?")
		args = append(args, strings.TrimSpace(query.Status))
	}
	if strings.TrimSpace(query.TargetID) != "" {
		clauses = append(clauses, "(target_runtime_target_id = '' OR target_runtime_target_id = ?)")
		args = append(args, strings.TrimSpace(query.TargetID))
	}
	limit := query.Limit
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, runQueueSelectSQL()+` WHERE `+strings.Join(clauses, " AND ")+` ORDER BY enqueued_at ASC, id LIMIT ?`, args...)
	if err != nil {
		return nil, fmt.Errorf("list operation run queue: %w", err)
	}
	defer rows.Close()
	items := []OperationRunQueueItem{}
	for rows.Next() {
		item, err := scanRunQueueItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

// CountRunQueueItems counts queued runs for one operation and status set.
func (s *Store) CountRunQueueItems(ctx context.Context, operationID string, statuses ...string) (int, error) {
	clauses := []string{"operation_id = ?"}
	args := []any{strings.TrimSpace(operationID)}
	if len(statuses) > 0 {
		placeholders := make([]string, 0, len(statuses))
		for _, status := range statuses {
			placeholders = append(placeholders, "?")
			args = append(args, status)
		}
		clauses = append(clauses, "status IN ("+strings.Join(placeholders, ",")+")")
	}
	var count int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM operation_run_queue WHERE `+strings.Join(clauses, " AND "), args...).Scan(&count); err != nil {
		return 0, fmt.Errorf("count operation run queue items: %w", err)
	}
	return count, nil
}

// LeaseNextRunQueueItem leases the oldest queued run eligible for a target.
func (s *Store) LeaseNextRunQueueItem(ctx context.Context, targetID string, leaseID string, leaseExpiresAt string) (OperationRunQueueItem, error) {
	targetID = strings.TrimSpace(targetID)
	if targetID == "" {
		return OperationRunQueueItem{}, fmt.Errorf("target id is required")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	defer tx.Rollback()
	row := tx.QueryRowContext(ctx, runQueueSelectSQL()+` WHERE status = ? AND (target_runtime_target_id = '' OR target_runtime_target_id = ?) ORDER BY enqueued_at ASC, id LIMIT 1`, OperationRunQueueStatusQueued, targetID)
	item, err := scanRunQueueItem(row)
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	now := timestampNow()
	result, err := tx.ExecContext(ctx, `UPDATE operation_run_queue
		SET status = ?, attempts = attempts + 1, lease_id = ?, leased_by_target_id = ?, lease_expires_at = ?, updated_at = ?, last_error = ''
		WHERE id = ? AND status = ?`,
		OperationRunQueueStatusLeased, leaseID, targetID, leaseExpiresAt, now, item.ID, OperationRunQueueStatusQueued)
	if err != nil {
		return OperationRunQueueItem{}, fmt.Errorf("lease operation run queue item: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	if affected == 0 {
		return OperationRunQueueItem{}, sql.ErrNoRows
	}
	if err := tx.Commit(); err != nil {
		return OperationRunQueueItem{}, err
	}
	return s.GetRunQueueItem(ctx, item.ID)
}

// RenewRunQueueLease extends a live worker lease.
func (s *Store) RenewRunQueueLease(ctx context.Context, id string, leaseID string, leaseExpiresAt string) (OperationRunQueueItem, error) {
	result, err := s.db.ExecContext(ctx, `UPDATE operation_run_queue
		SET lease_expires_at = ?, updated_at = ?
		WHERE id = ? AND lease_id = ? AND status IN (?, ?)`,
		leaseExpiresAt, timestampNow(), strings.TrimSpace(id), strings.TrimSpace(leaseID), OperationRunQueueStatusLeased, OperationRunQueueStatusRunning)
	if err != nil {
		return OperationRunQueueItem{}, fmt.Errorf("renew operation run queue lease: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	if affected == 0 {
		return OperationRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// MarkRunQueueItemRunning records the workflow run started by a lease.
func (s *Store) MarkRunQueueItemRunning(ctx context.Context, id string, leaseID string, runID string) (OperationRunQueueItem, error) {
	now := timestampNow()
	result, err := s.db.ExecContext(ctx, `UPDATE operation_run_queue
		SET status = ?, run_id = ?, started_at = ?, updated_at = ?
		WHERE id = ? AND lease_id = ? AND status = ?`,
		OperationRunQueueStatusRunning, strings.TrimSpace(runID), now, now, strings.TrimSpace(id), strings.TrimSpace(leaseID), OperationRunQueueStatusLeased)
	if err != nil {
		return OperationRunQueueItem{}, fmt.Errorf("mark operation run queue item running: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	if affected == 0 {
		return OperationRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// ReleaseRunQueueLease completes, fails, or cancels a leased queued run.
func (s *Store) ReleaseRunQueueLease(ctx context.Context, id string, req OperationRunLeaseReleaseRequest) (OperationRunQueueItem, error) {
	now := timestampNow()
	runID := strings.TrimSpace(req.RunID)
	status := strings.TrimSpace(req.Status)
	result, err := s.db.ExecContext(ctx, `UPDATE operation_run_queue
		SET status = ?, run_id = CASE WHEN ? = '' THEN run_id ELSE ? END, last_error = ?, lease_id = '', leased_by_target_id = '', lease_expires_at = '', completed_at = ?, updated_at = ?
		WHERE id = ? AND lease_id = ? AND status IN (?, ?)`,
		status, runID, runID, strings.TrimSpace(req.Error), now, now, strings.TrimSpace(id), strings.TrimSpace(req.LeaseID), OperationRunQueueStatusLeased, OperationRunQueueStatusRunning)
	if err != nil {
		return OperationRunQueueItem{}, fmt.Errorf("release operation run queue lease: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	if affected == 0 {
		return OperationRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// CancelRunQueueItem cancels a queued run before it completes.
func (s *Store) CancelRunQueueItem(ctx context.Context, id string) (OperationRunQueueItem, error) {
	now := timestampNow()
	result, err := s.db.ExecContext(ctx, `UPDATE operation_run_queue
		SET status = ?, lease_id = '', leased_by_target_id = '', lease_expires_at = '', completed_at = ?, updated_at = ?
		WHERE id = ? AND status IN (?, ?)`,
		OperationRunQueueStatusCanceled, now, now, strings.TrimSpace(id), OperationRunQueueStatusQueued, OperationRunQueueStatusLeased)
	if err != nil {
		return OperationRunQueueItem{}, fmt.Errorf("cancel operation run queue item: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return OperationRunQueueItem{}, err
	}
	if affected == 0 {
		return OperationRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// RecoverExpiredRunQueueLeases returns expired leases to the queue or fails them.
func (s *Store) RecoverExpiredRunQueueLeases(ctx context.Context, now string) (int, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, attempts, max_attempts FROM operation_run_queue WHERE status IN (?, ?) AND lease_expires_at != '' AND lease_expires_at <= ?`, OperationRunQueueStatusLeased, OperationRunQueueStatusRunning, now)
	if err != nil {
		return 0, fmt.Errorf("query expired operation run leases: %w", err)
	}
	defer rows.Close()
	type expiredLease struct {
		id          string
		attempts    int
		maxAttempts int
	}
	expired := []expiredLease{}
	for rows.Next() {
		var item expiredLease
		if err := rows.Scan(&item.id, &item.attempts, &item.maxAttempts); err != nil {
			return 0, err
		}
		expired = append(expired, item)
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for _, item := range expired {
		status := OperationRunQueueStatusQueued
		completedAt := ""
		if item.attempts >= item.maxAttempts {
			status = OperationRunQueueStatusFailed
			completedAt = now
		}
		if _, err := s.db.ExecContext(ctx, `UPDATE operation_run_queue
			SET status = ?, lease_id = '', leased_by_target_id = '', lease_expires_at = '', last_error = 'lease expired', completed_at = ?, updated_at = ?
			WHERE id = ?`, status, completedAt, now, item.id); err != nil {
			return 0, fmt.Errorf("recover expired operation run lease: %w", err)
		}
	}
	return len(expired), nil
}

// migrate creates the Operations storage tables.
func (s *Store) migrate(ctx context.Context) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS operations (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			workflow_id TEXT NOT NULL,
			workflow_version TEXT NOT NULL,
			codebase_id TEXT NOT NULL,
			runtime_target_id TEXT NOT NULL,
			agent_profile_id TEXT NOT NULL,
			defaults_json TEXT NOT NULL,
			policy_json TEXT NOT NULL,
			schedule_json TEXT NOT NULL,
			secret_refs_json TEXT NOT NULL,
			status TEXT NOT NULL,
			version INTEGER NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS operation_run_links (
			operation_id TEXT NOT NULL,
			run_id TEXT NOT NULL,
			created_at TEXT NOT NULL,
			PRIMARY KEY (operation_id, run_id)
		)`,
		`CREATE TABLE IF NOT EXISTS operation_run_snapshots (
			run_id TEXT PRIMARY KEY,
			operation_id TEXT NOT NULL,
			operation_version INTEGER NOT NULL,
			workflow_id TEXT NOT NULL,
			workflow_version TEXT NOT NULL,
			resolved_input_json TEXT NOT NULL,
			resolution_json TEXT NOT NULL,
			target_json TEXT NOT NULL,
			policy_json TEXT NOT NULL,
			secret_refs_json TEXT NOT NULL,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS operation_run_queue (
			id TEXT PRIMARY KEY,
			operation_id TEXT NOT NULL,
			operation_version INTEGER NOT NULL,
			operation_hash TEXT NOT NULL,
			workflow_id TEXT NOT NULL,
			workflow_version TEXT NOT NULL,
			target_runtime_target_id TEXT NOT NULL,
			target_json TEXT NOT NULL,
			policy_json TEXT NOT NULL,
			policy_decision_json TEXT NOT NULL,
			secret_refs_json TEXT NOT NULL,
			resolved_input_json TEXT NOT NULL,
			resolution_json TEXT NOT NULL,
			request_input_json TEXT NOT NULL,
			source TEXT NOT NULL,
			status TEXT NOT NULL,
			attempts INTEGER NOT NULL,
			max_attempts INTEGER NOT NULL,
			lease_id TEXT NOT NULL,
			leased_by_target_id TEXT NOT NULL,
			lease_expires_at TEXT NOT NULL,
			run_id TEXT NOT NULL,
			last_error TEXT NOT NULL,
			enqueued_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,
			started_at TEXT NOT NULL,
			completed_at TEXT NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS operation_run_queue_status_target_idx ON operation_run_queue(status, target_runtime_target_id, enqueued_at)`,
	}
	for _, statement := range statements {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate operations database: %w", err)
		}
	}
	return nil
}

// scanOperation decodes one Operation row.
func scanOperation(row interface{ Scan(...any) error }) (Operation, error) {
	var op Operation
	var defaults, policy, schedule, secrets string
	if err := row.Scan(&op.ID, &op.Name, &op.WorkflowID, &op.WorkflowVersion, &op.CodebaseID, &op.RuntimeTargetID, &op.AgentProfileID, &defaults, &policy, &schedule, &secrets, &op.Status, &op.Version, &op.CreatedAt, &op.UpdatedAt); err != nil {
		return Operation{}, err
	}
	if err := decodeMap(defaults, &op.Defaults); err != nil {
		return Operation{}, err
	}
	if err := decodeJSON(policy, &op.Policy); err != nil {
		return Operation{}, err
	}
	if err := decodeJSON(schedule, &op.Schedule); err != nil {
		return Operation{}, err
	}
	if err := decodeJSON(secrets, &op.SecretRefs); err != nil {
		return Operation{}, err
	}
	return op, nil
}

// scanRunSnapshot decodes one Operation run snapshot row.
func scanRunSnapshot(row interface{ Scan(...any) error }) (OperationRunSnapshot, error) {
	var snapshot OperationRunSnapshot
	var resolved, resolution, target, policy, secrets string
	if err := row.Scan(&snapshot.RunID, &snapshot.OperationID, &snapshot.OperationVersion, &snapshot.WorkflowID, &snapshot.WorkflowVersion, &resolved, &resolution, &target, &policy, &secrets, &snapshot.CreatedAt); err != nil {
		return OperationRunSnapshot{}, err
	}
	if err := decodeMap(resolved, &snapshot.ResolvedInput); err != nil {
		return OperationRunSnapshot{}, err
	}
	if err := decodeMap(resolution, &snapshot.Resolution); err != nil {
		return OperationRunSnapshot{}, err
	}
	if err := decodeJSON(target, &snapshot.Target); err != nil {
		return OperationRunSnapshot{}, err
	}
	if err := decodeJSON(policy, &snapshot.Policy); err != nil {
		return OperationRunSnapshot{}, err
	}
	if err := decodeJSON(secrets, &snapshot.SecretRefs); err != nil {
		return OperationRunSnapshot{}, err
	}
	return snapshot, nil
}

// runQueueSelectSQL returns the full queued-run projection.
func runQueueSelectSQL() string {
	return `SELECT id, operation_id, operation_version, operation_hash, workflow_id, workflow_version, target_json, policy_json, policy_decision_json, secret_refs_json, resolved_input_json, resolution_json, request_input_json, source, status, attempts, max_attempts, lease_id, leased_by_target_id, lease_expires_at, run_id, last_error, enqueued_at, updated_at, started_at, completed_at FROM operation_run_queue`
}

// scanRunQueueItem decodes one queued Operation run row.
func scanRunQueueItem(row interface{ Scan(...any) error }) (OperationRunQueueItem, error) {
	var item OperationRunQueueItem
	var target, policy, decision, secrets, resolved, resolution, requestInput string
	if err := row.Scan(&item.ID, &item.OperationID, &item.OperationVersion, &item.OperationHash, &item.WorkflowID, &item.WorkflowVersion, &target, &policy, &decision, &secrets, &resolved, &resolution, &requestInput, &item.Source, &item.Status, &item.Attempts, &item.MaxAttempts, &item.LeaseID, &item.LeasedByTargetID, &item.LeaseExpiresAt, &item.RunID, &item.LastError, &item.EnqueuedAt, &item.UpdatedAt, &item.StartedAt, &item.CompletedAt); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeJSON(target, &item.Target); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeJSON(policy, &item.Policy); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeJSON(decision, &item.PolicyDecision); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeJSON(secrets, &item.SecretRefs); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeMap(resolved, &item.ResolvedInput); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeMap(resolution, &item.Resolution); err != nil {
		return OperationRunQueueItem{}, err
	}
	if err := decodeMap(requestInput, &item.RequestInput); err != nil {
		return OperationRunQueueItem{}, err
	}
	return item, nil
}

// encodeMap encodes a JSON map with an empty object default.
func encodeMap(value map[string]any) (string, error) {
	if value == nil {
		value = map[string]any{}
	}
	return encodeJSON(value)
}

// encodeJSON encodes a value as compact JSON.
func encodeJSON(value any) (string, error) {
	data, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// decodeMap decodes a JSON object with an empty object default.
func decodeMap(raw string, target *map[string]any) error {
	if strings.TrimSpace(raw) == "" {
		*target = map[string]any{}
		return nil
	}
	return json.Unmarshal([]byte(raw), target)
}

// decodeJSON decodes a JSON string into a target.
func decodeJSON(raw string, target any) error {
	if strings.TrimSpace(raw) == "" {
		raw = "null"
	}
	return json.Unmarshal([]byte(raw), target)
}

// ensureOperationsPath creates a private SQLite path when needed.
func ensureOperationsPath(path string) error {
	if strings.HasPrefix(path, "file:") {
		return nil
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create operations database directory %q: %w", dir, err)
	}
	file, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return fmt.Errorf("create operations database %q: %w", path, err)
	}
	return file.Close()
}

// operationsDatabaseDSN adds SQLite pragmas for local concurrent access.
func operationsDatabaseDSN(path string) string {
	if strings.HasPrefix(path, "file:") || strings.Contains(path, "?") {
		return path
	}
	values := url.Values{}
	values.Add("_pragma", operationsSQLiteBusyTimeoutPragma)
	values.Add("_pragma", "journal_mode=WAL")
	values.Add("_pragma", "foreign_keys=ON")
	values.Add("_pragma", "synchronous=NORMAL")
	return path + "?" + values.Encode()
}

// timestampNow returns an RFC3339 UTC timestamp.
func timestampNow() string {
	return time.Now().UTC().Format(time.RFC3339Nano)
}
