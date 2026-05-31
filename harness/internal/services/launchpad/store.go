// This file stores Launchpad-owned records in SQLite.
package launchpad

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

const launchpadSQLiteBusyTimeoutPragma = "busy_timeout=5000"

// Store owns Launchpad persistence tables.
type Store struct {
	db *sql.DB
}

// OpenStore creates the Launchpad database and applies schema.
func OpenStore(ctx context.Context, path string) (*Store, error) {
	resolved := strings.TrimSpace(path)
	if resolved == "" {
		return nil, fmt.Errorf("launchpad database path is required")
	}
	if err := ensureLaunchpadPath(resolved); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", launchpadDatabaseDSN(resolved))
	if err != nil {
		return nil, fmt.Errorf("open launchpad database %q: %w", resolved, err)
	}
	store := &Store{db: db}
	if err := store.migrate(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

// Close releases the Launchpad database handle.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

// UpsertLaunch stores or replaces one Launch.
func (s *Store) UpsertLaunch(ctx context.Context, op Launch) error {
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
	_, err = s.db.ExecContext(ctx, `INSERT INTO launchpad
		(id, name, runbook_id, runbook_version, codebase_id, runtime_target_id, agent_profile_id, defaults_json, policy_json, schedule_json, secret_refs_json, status, version, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			name = excluded.name,
			runbook_id = excluded.runbook_id,
			runbook_version = excluded.runbook_version,
			codebase_id = excluded.codebase_id,
			runtime_target_id = excluded.runtime_target_id,
			agent_profile_id = excluded.agent_profile_id,
			defaults_json = excluded.defaults_json,
			policy_json = excluded.policy_json,
			schedule_json = excluded.schedule_json,
			secret_refs_json = excluded.secret_refs_json,
			status = excluded.status,
			version = launchpad.version + 1,
			updated_at = excluded.updated_at`,
		op.ID, op.Name, op.RunbookID, op.RunbookVersion, op.CodebaseID, op.RuntimeTargetID, op.AgentProfileID, defaults, policy, schedule, secrets, op.Status, op.Version, op.CreatedAt, op.UpdatedAt)
	if err != nil {
		return fmt.Errorf("upsert launch %q: %w", op.ID, err)
	}
	return nil
}

// GetLaunch loads one Launch by id.
func (s *Store) GetLaunch(ctx context.Context, id string) (Launch, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, runbook_id, runbook_version, codebase_id, runtime_target_id, agent_profile_id, defaults_json, policy_json, schedule_json, secret_refs_json, status, version, created_at, updated_at FROM launchpad WHERE id = ?`, strings.TrimSpace(id))
	return scanLaunch(row)
}

// ListLaunchpad lists Launchpad matching a filter.
func (s *Store) ListLaunchpad(ctx context.Context, query LaunchQuery) ([]Launch, error) {
	clauses := []string{"1=1"}
	args := []any{}
	if strings.TrimSpace(query.RunbookID) != "" {
		clauses = append(clauses, "runbook_id = ?")
		args = append(args, strings.TrimSpace(query.RunbookID))
	}
	if strings.TrimSpace(query.CodebaseID) != "" {
		clauses = append(clauses, "codebase_id = ?")
		args = append(args, strings.TrimSpace(query.CodebaseID))
	}
	if strings.TrimSpace(query.Status) != "" {
		clauses = append(clauses, "status = ?")
		args = append(args, strings.TrimSpace(query.Status))
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, runbook_id, runbook_version, codebase_id, runtime_target_id, agent_profile_id, defaults_json, policy_json, schedule_json, secret_refs_json, status, version, created_at, updated_at FROM launchpad WHERE `+strings.Join(clauses, " AND ")+` ORDER BY updated_at DESC, id`, args...)
	if err != nil {
		return nil, fmt.Errorf("list launchpad: %w", err)
	}
	defer rows.Close()
	ops := []Launch{}
	for rows.Next() {
		op, err := scanLaunch(rows)
		if err != nil {
			return nil, err
		}
		ops = append(ops, op)
	}
	return ops, rows.Err()
}

// DeleteLaunch removes one Launch.
func (s *Store) DeleteLaunch(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM launchpad WHERE id = ?`, strings.TrimSpace(id))
	if err != nil {
		return fmt.Errorf("delete launch %q: %w", id, err)
	}
	return nil
}

// InsertRunLink stores a runbook run link for an Launch.
func (s *Store) InsertRunLink(ctx context.Context, link LaunchRunLink) error {
	if link.CreatedAt == "" {
		link.CreatedAt = timestampNow()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO launch_run_links (launch_id, run_id, created_at) VALUES (?, ?, ?)`, link.LaunchID, link.RunID, link.CreatedAt)
	if err != nil {
		return fmt.Errorf("insert launch run link: %w", err)
	}
	return nil
}

// InsertRunSnapshot stores one immutable run-start snapshot.
func (s *Store) InsertRunSnapshot(ctx context.Context, snapshot LaunchRunSnapshot) error {
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
	_, err = s.db.ExecContext(ctx, `INSERT INTO launchpad_run_snapshots
		(run_id, launch_id, launch_version, runbook_id, runbook_version, resolved_input_json, resolution_json, target_json, policy_json, secret_refs_json, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		snapshot.RunID, snapshot.LaunchID, snapshot.LaunchVersion, snapshot.RunbookID, snapshot.RunbookVersion, resolved, resolution, target, policy, secrets, snapshot.CreatedAt)
	if err != nil {
		return fmt.Errorf("insert launch run snapshot: %w", err)
	}
	return nil
}

// GetRunSnapshot loads one run snapshot by runbook run id.
func (s *Store) GetRunSnapshot(ctx context.Context, runID string) (LaunchRunSnapshot, error) {
	row := s.db.QueryRowContext(ctx, `SELECT run_id, launch_id, launch_version, runbook_id, runbook_version, resolved_input_json, resolution_json, target_json, policy_json, secret_refs_json, created_at FROM launchpad_run_snapshots WHERE run_id = ?`, strings.TrimSpace(runID))
	return scanRunSnapshot(row)
}

// InsertRunQueueItem stores one durable queued Launch run.
func (s *Store) InsertRunQueueItem(ctx context.Context, item LaunchRunQueueItem) error {
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
	_, err = s.db.ExecContext(ctx, `INSERT INTO launch_run_queue
		(id, launch_id, launch_version, launch_hash, runbook_id, runbook_version, target_runtime_target_id, target_json, policy_json, policy_decision_json, secret_refs_json, resolved_input_json, resolution_json, request_input_json, source, status, attempts, max_attempts, lease_id, leased_by_target_id, lease_expires_at, run_id, last_error, enqueued_at, updated_at, started_at, completed_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		item.ID, item.LaunchID, item.LaunchVersion, item.LaunchHash, item.RunbookID, item.RunbookVersion, item.Target.RuntimeTargetID, target, policy, decision, secrets, resolved, resolution, requestInput, item.Source, item.Status, item.Attempts, item.MaxAttempts, item.LeaseID, item.LeasedByTargetID, item.LeaseExpiresAt, item.RunID, item.LastError, item.EnqueuedAt, item.UpdatedAt, item.StartedAt, item.CompletedAt)
	if err != nil {
		return fmt.Errorf("insert launch run queue item: %w", err)
	}
	return nil
}

// GetRunQueueItem loads one queued Launch run.
func (s *Store) GetRunQueueItem(ctx context.Context, id string) (LaunchRunQueueItem, error) {
	row := s.db.QueryRowContext(ctx, runQueueSelectSQL()+` WHERE id = ?`, strings.TrimSpace(id))
	return scanRunQueueItem(row)
}

// ListRunQueueItems lists queued Launch runs matching a filter.
func (s *Store) ListRunQueueItems(ctx context.Context, query LaunchRunQueueQuery) ([]LaunchRunQueueItem, error) {
	clauses := []string{"1=1"}
	args := []any{}
	if strings.TrimSpace(query.LaunchID) != "" {
		clauses = append(clauses, "launch_id = ?")
		args = append(args, strings.TrimSpace(query.LaunchID))
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
		return nil, fmt.Errorf("list launch run queue: %w", err)
	}
	defer rows.Close()
	items := []LaunchRunQueueItem{}
	for rows.Next() {
		item, err := scanRunQueueItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

// CountRunQueueItems counts queued runs for one launch and status set.
func (s *Store) CountRunQueueItems(ctx context.Context, launchID string, statuses ...string) (int, error) {
	clauses := []string{"launch_id = ?"}
	args := []any{strings.TrimSpace(launchID)}
	if len(statuses) > 0 {
		placeholders := make([]string, 0, len(statuses))
		for _, status := range statuses {
			placeholders = append(placeholders, "?")
			args = append(args, status)
		}
		clauses = append(clauses, "status IN ("+strings.Join(placeholders, ",")+")")
	}
	var count int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM launch_run_queue WHERE `+strings.Join(clauses, " AND "), args...).Scan(&count); err != nil {
		return 0, fmt.Errorf("count launch run queue items: %w", err)
	}
	return count, nil
}

// LeaseNextRunQueueItem leases the oldest queued run eligible for a target.
func (s *Store) LeaseNextRunQueueItem(ctx context.Context, targetID string, leaseID string, leaseExpiresAt string) (LaunchRunQueueItem, error) {
	targetID = strings.TrimSpace(targetID)
	if targetID == "" {
		return LaunchRunQueueItem{}, fmt.Errorf("target id is required")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	defer tx.Rollback()
	row := tx.QueryRowContext(ctx, runQueueSelectSQL()+` WHERE status = ? AND (target_runtime_target_id = '' OR target_runtime_target_id = ?) ORDER BY enqueued_at ASC, id LIMIT 1`, LaunchRunQueueStatusQueued, targetID)
	item, err := scanRunQueueItem(row)
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	now := timestampNow()
	result, err := tx.ExecContext(ctx, `UPDATE launch_run_queue
		SET status = ?, attempts = attempts + 1, lease_id = ?, leased_by_target_id = ?, lease_expires_at = ?, updated_at = ?, last_error = ''
		WHERE id = ? AND status = ?`,
		LaunchRunQueueStatusLeased, leaseID, targetID, leaseExpiresAt, now, item.ID, LaunchRunQueueStatusQueued)
	if err != nil {
		return LaunchRunQueueItem{}, fmt.Errorf("lease launch run queue item: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	if affected == 0 {
		return LaunchRunQueueItem{}, sql.ErrNoRows
	}
	if err := tx.Commit(); err != nil {
		return LaunchRunQueueItem{}, err
	}
	return s.GetRunQueueItem(ctx, item.ID)
}

// RenewRunQueueLease extends a live worker lease.
func (s *Store) RenewRunQueueLease(ctx context.Context, id string, leaseID string, leaseExpiresAt string) (LaunchRunQueueItem, error) {
	result, err := s.db.ExecContext(ctx, `UPDATE launch_run_queue
		SET lease_expires_at = ?, updated_at = ?
		WHERE id = ? AND lease_id = ? AND status IN (?, ?)`,
		leaseExpiresAt, timestampNow(), strings.TrimSpace(id), strings.TrimSpace(leaseID), LaunchRunQueueStatusLeased, LaunchRunQueueStatusRunning)
	if err != nil {
		return LaunchRunQueueItem{}, fmt.Errorf("renew launch run queue lease: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	if affected == 0 {
		return LaunchRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// MarkRunQueueItemRunning records the runbook run started by a lease.
func (s *Store) MarkRunQueueItemRunning(ctx context.Context, id string, leaseID string, runID string) (LaunchRunQueueItem, error) {
	now := timestampNow()
	result, err := s.db.ExecContext(ctx, `UPDATE launch_run_queue
		SET status = ?, run_id = ?, started_at = ?, updated_at = ?
		WHERE id = ? AND lease_id = ? AND status = ?`,
		LaunchRunQueueStatusRunning, strings.TrimSpace(runID), now, now, strings.TrimSpace(id), strings.TrimSpace(leaseID), LaunchRunQueueStatusLeased)
	if err != nil {
		return LaunchRunQueueItem{}, fmt.Errorf("mark launch run queue item running: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	if affected == 0 {
		return LaunchRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// ReleaseRunQueueLease completes, fails, or cancels a leased queued run.
func (s *Store) ReleaseRunQueueLease(ctx context.Context, id string, req LaunchRunLeaseReleaseRequest) (LaunchRunQueueItem, error) {
	now := timestampNow()
	runID := strings.TrimSpace(req.RunID)
	status := strings.TrimSpace(req.Status)
	result, err := s.db.ExecContext(ctx, `UPDATE launch_run_queue
		SET status = ?, run_id = CASE WHEN ? = '' THEN run_id ELSE ? END, last_error = ?, lease_id = '', leased_by_target_id = '', lease_expires_at = '', completed_at = ?, updated_at = ?
		WHERE id = ? AND lease_id = ? AND status IN (?, ?)`,
		status, runID, runID, strings.TrimSpace(req.Error), now, now, strings.TrimSpace(id), strings.TrimSpace(req.LeaseID), LaunchRunQueueStatusLeased, LaunchRunQueueStatusRunning)
	if err != nil {
		return LaunchRunQueueItem{}, fmt.Errorf("release launch run queue lease: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	if affected == 0 {
		return LaunchRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// CancelRunQueueItem cancels a queued run before it completes.
func (s *Store) CancelRunQueueItem(ctx context.Context, id string) (LaunchRunQueueItem, error) {
	now := timestampNow()
	result, err := s.db.ExecContext(ctx, `UPDATE launch_run_queue
		SET status = ?, lease_id = '', leased_by_target_id = '', lease_expires_at = '', completed_at = ?, updated_at = ?
		WHERE id = ? AND status IN (?, ?)`,
		LaunchRunQueueStatusCanceled, now, now, strings.TrimSpace(id), LaunchRunQueueStatusQueued, LaunchRunQueueStatusLeased)
	if err != nil {
		return LaunchRunQueueItem{}, fmt.Errorf("cancel launch run queue item: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return LaunchRunQueueItem{}, err
	}
	if affected == 0 {
		return LaunchRunQueueItem{}, sql.ErrNoRows
	}
	return s.GetRunQueueItem(ctx, id)
}

// RecoverExpiredRunQueueLeases returns expired leases to the queue or fails them.
func (s *Store) RecoverExpiredRunQueueLeases(ctx context.Context, now string) (int, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, attempts, max_attempts FROM launch_run_queue WHERE status IN (?, ?) AND lease_expires_at != '' AND lease_expires_at <= ?`, LaunchRunQueueStatusLeased, LaunchRunQueueStatusRunning, now)
	if err != nil {
		return 0, fmt.Errorf("query expired launch run leases: %w", err)
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
		status := LaunchRunQueueStatusQueued
		completedAt := ""
		if item.attempts >= item.maxAttempts {
			status = LaunchRunQueueStatusFailed
			completedAt = now
		}
		if _, err := s.db.ExecContext(ctx, `UPDATE launch_run_queue
			SET status = ?, lease_id = '', leased_by_target_id = '', lease_expires_at = '', last_error = 'lease expired', completed_at = ?, updated_at = ?
			WHERE id = ?`, status, completedAt, now, item.id); err != nil {
			return 0, fmt.Errorf("recover expired launch run lease: %w", err)
		}
	}
	return len(expired), nil
}

// migrate creates the Launchpad storage tables.
func (s *Store) migrate(ctx context.Context) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS launchpad (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			runbook_id TEXT NOT NULL,
			runbook_version TEXT NOT NULL,
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
		`CREATE TABLE IF NOT EXISTS launch_run_links (
			launch_id TEXT NOT NULL,
			run_id TEXT NOT NULL,
			created_at TEXT NOT NULL,
			PRIMARY KEY (launch_id, run_id)
		)`,
		`CREATE TABLE IF NOT EXISTS launchpad_run_snapshots (
			run_id TEXT PRIMARY KEY,
			launch_id TEXT NOT NULL,
			launch_version INTEGER NOT NULL,
			runbook_id TEXT NOT NULL,
			runbook_version TEXT NOT NULL,
			resolved_input_json TEXT NOT NULL,
			resolution_json TEXT NOT NULL,
			target_json TEXT NOT NULL,
			policy_json TEXT NOT NULL,
			secret_refs_json TEXT NOT NULL,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS launch_run_queue (
			id TEXT PRIMARY KEY,
			launch_id TEXT NOT NULL,
			launch_version INTEGER NOT NULL,
			launch_hash TEXT NOT NULL,
			runbook_id TEXT NOT NULL,
			runbook_version TEXT NOT NULL,
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
		`CREATE INDEX IF NOT EXISTS launch_run_queue_status_target_idx ON launch_run_queue(status, target_runtime_target_id, enqueued_at)`,
	}
	for _, statement := range statements {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate launchpad database: %w", err)
		}
	}
	return nil
}

// scanLaunch decodes one Launch row.
func scanLaunch(row interface{ Scan(...any) error }) (Launch, error) {
	var op Launch
	var defaults, policy, schedule, secrets string
	if err := row.Scan(&op.ID, &op.Name, &op.RunbookID, &op.RunbookVersion, &op.CodebaseID, &op.RuntimeTargetID, &op.AgentProfileID, &defaults, &policy, &schedule, &secrets, &op.Status, &op.Version, &op.CreatedAt, &op.UpdatedAt); err != nil {
		return Launch{}, err
	}
	if err := decodeMap(defaults, &op.Defaults); err != nil {
		return Launch{}, err
	}
	if err := decodeJSON(policy, &op.Policy); err != nil {
		return Launch{}, err
	}
	if err := decodeJSON(schedule, &op.Schedule); err != nil {
		return Launch{}, err
	}
	if err := decodeJSON(secrets, &op.SecretRefs); err != nil {
		return Launch{}, err
	}
	return op, nil
}

// scanRunSnapshot decodes one Launch run snapshot row.
func scanRunSnapshot(row interface{ Scan(...any) error }) (LaunchRunSnapshot, error) {
	var snapshot LaunchRunSnapshot
	var resolved, resolution, target, policy, secrets string
	if err := row.Scan(&snapshot.RunID, &snapshot.LaunchID, &snapshot.LaunchVersion, &snapshot.RunbookID, &snapshot.RunbookVersion, &resolved, &resolution, &target, &policy, &secrets, &snapshot.CreatedAt); err != nil {
		return LaunchRunSnapshot{}, err
	}
	if err := decodeMap(resolved, &snapshot.ResolvedInput); err != nil {
		return LaunchRunSnapshot{}, err
	}
	if err := decodeMap(resolution, &snapshot.Resolution); err != nil {
		return LaunchRunSnapshot{}, err
	}
	if err := decodeJSON(target, &snapshot.Target); err != nil {
		return LaunchRunSnapshot{}, err
	}
	if err := decodeJSON(policy, &snapshot.Policy); err != nil {
		return LaunchRunSnapshot{}, err
	}
	if err := decodeJSON(secrets, &snapshot.SecretRefs); err != nil {
		return LaunchRunSnapshot{}, err
	}
	return snapshot, nil
}

// runQueueSelectSQL returns the full queued-run projection.
func runQueueSelectSQL() string {
	return `SELECT id, launch_id, launch_version, launch_hash, runbook_id, runbook_version, target_json, policy_json, policy_decision_json, secret_refs_json, resolved_input_json, resolution_json, request_input_json, source, status, attempts, max_attempts, lease_id, leased_by_target_id, lease_expires_at, run_id, last_error, enqueued_at, updated_at, started_at, completed_at FROM launch_run_queue`
}

// scanRunQueueItem decodes one queued Launch run row.
func scanRunQueueItem(row interface{ Scan(...any) error }) (LaunchRunQueueItem, error) {
	var item LaunchRunQueueItem
	var target, policy, decision, secrets, resolved, resolution, requestInput string
	if err := row.Scan(&item.ID, &item.LaunchID, &item.LaunchVersion, &item.LaunchHash, &item.RunbookID, &item.RunbookVersion, &target, &policy, &decision, &secrets, &resolved, &resolution, &requestInput, &item.Source, &item.Status, &item.Attempts, &item.MaxAttempts, &item.LeaseID, &item.LeasedByTargetID, &item.LeaseExpiresAt, &item.RunID, &item.LastError, &item.EnqueuedAt, &item.UpdatedAt, &item.StartedAt, &item.CompletedAt); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeJSON(target, &item.Target); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeJSON(policy, &item.Policy); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeJSON(decision, &item.PolicyDecision); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeJSON(secrets, &item.SecretRefs); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeMap(resolved, &item.ResolvedInput); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeMap(resolution, &item.Resolution); err != nil {
		return LaunchRunQueueItem{}, err
	}
	if err := decodeMap(requestInput, &item.RequestInput); err != nil {
		return LaunchRunQueueItem{}, err
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

// ensureLaunchpadPath creates a private SQLite path when needed.
func ensureLaunchpadPath(path string) error {
	if strings.HasPrefix(path, "file:") {
		return nil
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create launchpad database directory %q: %w", dir, err)
	}
	file, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return fmt.Errorf("create launchpad database %q: %w", path, err)
	}
	return file.Close()
}

// launchpadDatabaseDSN adds SQLite pragmas for local concurrent access.
func launchpadDatabaseDSN(path string) string {
	if strings.HasPrefix(path, "file:") || strings.Contains(path, "?") {
		return path
	}
	values := url.Values{}
	values.Add("_pragma", launchpadSQLiteBusyTimeoutPragma)
	values.Add("_pragma", "journal_mode=WAL")
	values.Add("_pragma", "foreign_keys=ON")
	values.Add("_pragma", "synchronous=NORMAL")
	return path + "?" + values.Encode()
}

// timestampNow returns an RFC3339 UTC timestamp.
func timestampNow() string {
	return time.Now().UTC().Format(time.RFC3339Nano)
}
