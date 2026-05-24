// This file stores Runtime Target records in SQLite.
package targets

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/glebarez/go-sqlite"
)

const targetsSQLiteBusyTimeoutPragma = "busy_timeout=5000"

// Store owns Runtime Target persistence tables.
type Store struct {
	db *sql.DB
}

// OpenStore creates the targets database and applies schema.
func OpenStore(ctx context.Context, path string) (*Store, error) {
	resolved := strings.TrimSpace(path)
	if resolved == "" {
		return nil, fmt.Errorf("runtime targets database path is required")
	}
	if err := ensureTargetsPath(resolved); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", targetsDatabaseDSN(resolved))
	if err != nil {
		return nil, fmt.Errorf("open runtime targets database %q: %w", resolved, err)
	}
	store := &Store{db: db}
	if err := store.migrate(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

// Close releases the targets database handle.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

// UpsertTarget stores one runtime target.
func (s *Store) UpsertTarget(ctx context.Context, target RuntimeTarget) error {
	now := timestampNow()
	if target.CreatedAt == "" {
		target.CreatedAt = now
	}
	if target.UpdatedAt == "" {
		target.UpdatedAt = now
	}
	capabilities, err := encodeStrings(target.Capabilities)
	if err != nil {
		return err
	}
	allowedCodebases, err := encodeStrings(target.AllowedCodebaseIDs)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO runtime_targets
		(id, name, kind, status, version, capabilities_json, allowed_codebase_ids_json, secret_ref_count, last_seen_at, current_run_count, os, hostname, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			name = excluded.name,
			kind = excluded.kind,
			status = excluded.status,
			version = excluded.version,
			capabilities_json = excluded.capabilities_json,
			allowed_codebase_ids_json = excluded.allowed_codebase_ids_json,
			secret_ref_count = excluded.secret_ref_count,
			last_seen_at = excluded.last_seen_at,
			current_run_count = excluded.current_run_count,
			os = excluded.os,
			hostname = excluded.hostname,
			updated_at = excluded.updated_at`,
		target.ID, target.Name, target.Kind, target.Status, target.Version, capabilities, allowedCodebases, target.SecretRefCount, target.LastSeenAt, target.CurrentRunCount, target.OS, target.Hostname, target.CreatedAt, target.UpdatedAt)
	if err != nil {
		return fmt.Errorf("upsert runtime target %q: %w", target.ID, err)
	}
	return nil
}

// GetTarget loads one runtime target by id.
func (s *Store) GetTarget(ctx context.Context, id string) (RuntimeTarget, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, kind, status, version, capabilities_json, allowed_codebase_ids_json, secret_ref_count, last_seen_at, current_run_count, os, hostname, created_at, updated_at FROM runtime_targets WHERE id = ?`, strings.TrimSpace(id))
	return scanTarget(row)
}

// ListTargets lists runtime targets in stable display order.
func (s *Store) ListTargets(ctx context.Context) ([]RuntimeTarget, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, kind, status, version, capabilities_json, allowed_codebase_ids_json, secret_ref_count, last_seen_at, current_run_count, os, hostname, created_at, updated_at FROM runtime_targets ORDER BY kind, name, id`)
	if err != nil {
		return nil, fmt.Errorf("list runtime targets: %w", err)
	}
	defer rows.Close()
	targets := []RuntimeTarget{}
	for rows.Next() {
		target, err := scanTarget(rows)
		if err != nil {
			return nil, err
		}
		targets = append(targets, target)
	}
	return targets, rows.Err()
}

// AppendLog stores one display-safe target log row.
func (s *Store) AppendLog(ctx context.Context, entry TargetLogEntry) error {
	if entry.CreatedAt == "" {
		entry.CreatedAt = timestampNow()
	}
	if strings.TrimSpace(entry.Level) == "" {
		entry.Level = "info"
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO runtime_target_logs (target_id, level, message, created_at) VALUES (?, ?, ?, ?)`, strings.TrimSpace(entry.TargetID), strings.TrimSpace(entry.Level), strings.TrimSpace(entry.Message), entry.CreatedAt)
	if err != nil {
		return fmt.Errorf("append runtime target log: %w", err)
	}
	return nil
}

// ListLogs lists target logs newest first.
func (s *Store) ListLogs(ctx context.Context, targetID string, limit int) ([]TargetLogEntry, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `SELECT id, target_id, level, message, created_at FROM runtime_target_logs WHERE target_id = ? ORDER BY id DESC LIMIT ?`, strings.TrimSpace(targetID), limit)
	if err != nil {
		return nil, fmt.Errorf("list runtime target logs: %w", err)
	}
	defer rows.Close()
	logs := []TargetLogEntry{}
	for rows.Next() {
		var entry TargetLogEntry
		if err := rows.Scan(&entry.ID, &entry.TargetID, &entry.Level, &entry.Message, &entry.CreatedAt); err != nil {
			return nil, err
		}
		logs = append(logs, entry)
	}
	return logs, rows.Err()
}

// PairingSecret returns the durable HMAC secret used for invite tokens.
func (s *Store) PairingSecret(ctx context.Context) ([]byte, error) {
	var encoded string
	err := s.db.QueryRowContext(ctx, `SELECT secret FROM runtime_target_pairing_secret WHERE id = 'default'`).Scan(&encoded)
	if err == nil {
		return decodePairingSecret(encoded)
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("load runtime target pairing secret: %w", err)
	}
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return nil, fmt.Errorf("generate runtime target pairing secret: %w", err)
	}
	encoded = encodePairingSecret(secret)
	result, err := s.db.ExecContext(ctx, `INSERT OR IGNORE INTO runtime_target_pairing_secret (id, secret, created_at) VALUES ('default', ?, ?)`, encoded, timestampNow())
	if err != nil {
		return nil, fmt.Errorf("store runtime target pairing secret: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	if affected == 0 {
		return s.PairingSecret(ctx)
	}
	return secret, nil
}

// migrate creates the Runtime Target storage tables.
func (s *Store) migrate(ctx context.Context) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS runtime_targets (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			kind TEXT NOT NULL,
			status TEXT NOT NULL,
			version TEXT NOT NULL,
			capabilities_json TEXT NOT NULL,
			allowed_codebase_ids_json TEXT NOT NULL,
			secret_ref_count INTEGER NOT NULL,
			last_seen_at TEXT NOT NULL,
			current_run_count INTEGER NOT NULL,
			os TEXT NOT NULL,
			hostname TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS runtime_target_logs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			target_id TEXT NOT NULL,
			level TEXT NOT NULL,
			message TEXT NOT NULL,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS runtime_target_pairing_secret (
			id TEXT PRIMARY KEY,
			secret TEXT NOT NULL,
			created_at TEXT NOT NULL
		)`,
	}
	for _, statement := range statements {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate runtime targets database: %w", err)
		}
	}
	return nil
}

// scanTarget decodes one runtime target row.
func scanTarget(row interface{ Scan(...any) error }) (RuntimeTarget, error) {
	var target RuntimeTarget
	var capabilities, allowedCodebases string
	if err := row.Scan(&target.ID, &target.Name, &target.Kind, &target.Status, &target.Version, &capabilities, &allowedCodebases, &target.SecretRefCount, &target.LastSeenAt, &target.CurrentRunCount, &target.OS, &target.Hostname, &target.CreatedAt, &target.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return RuntimeTarget{}, notFoundError{message: "runtime target not found"}
		}
		return RuntimeTarget{}, err
	}
	if err := decodeStrings(capabilities, &target.Capabilities); err != nil {
		return RuntimeTarget{}, err
	}
	if err := decodeStrings(allowedCodebases, &target.AllowedCodebaseIDs); err != nil {
		return RuntimeTarget{}, err
	}
	return target, nil
}

// encodeStrings encodes string slices as compact JSON.
func encodeStrings(values []string) (string, error) {
	if values == nil {
		values = []string{}
	}
	data, err := json.Marshal(values)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// decodeStrings decodes a JSON string slice.
func decodeStrings(raw string, target *[]string) error {
	if strings.TrimSpace(raw) == "" {
		*target = []string{}
		return nil
	}
	return json.Unmarshal([]byte(raw), target)
}

// encodePairingSecret stores binary token key material as URL-safe text.
func encodePairingSecret(secret []byte) string {
	return base64.RawURLEncoding.EncodeToString(secret)
}

// decodePairingSecret loads URL-safe token key material.
func decodePairingSecret(raw string) ([]byte, error) {
	secret, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(raw))
	if err != nil {
		return nil, fmt.Errorf("decode runtime target pairing secret: %w", err)
	}
	if len(secret) < 32 {
		return nil, fmt.Errorf("runtime target pairing secret is too short")
	}
	return secret, nil
}

// ensureTargetsPath creates a private SQLite path when needed.
func ensureTargetsPath(path string) error {
	if strings.HasPrefix(path, "file:") {
		return nil
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create runtime targets database directory %q: %w", dir, err)
	}
	file, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return fmt.Errorf("create runtime targets database %q: %w", path, err)
	}
	return file.Close()
}

// targetsDatabaseDSN adds SQLite pragmas for local concurrent access.
func targetsDatabaseDSN(path string) string {
	if strings.HasPrefix(path, "file:") || strings.Contains(path, "?") {
		return path
	}
	values := url.Values{}
	values.Add("_pragma", targetsSQLiteBusyTimeoutPragma)
	values.Add("_pragma", "journal_mode=WAL")
	values.Add("_pragma", "foreign_keys=ON")
	values.Add("_pragma", "synchronous=NORMAL")
	return path + "?" + values.Encode()
}

// timestampNow returns an RFC3339 UTC timestamp.
func timestampNow() string {
	return time.Now().UTC().Format(time.RFC3339Nano)
}

// notFoundError is returned for missing target records.
type notFoundError struct {
	message string
}

// Error returns the display-safe missing record message.
func (e notFoundError) Error() string {
	return e.message
}

// isNotFound reports whether an error is a missing target.
func isNotFound(err error) bool {
	var notFound notFoundError
	return errors.As(err, &notFound)
}
