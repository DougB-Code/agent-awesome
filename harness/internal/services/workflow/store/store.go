// This file opens and initializes the workflow SQLite store.
package store

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	_ "github.com/glebarez/go-sqlite"
)

// sqliteBusyTimeoutPragma is the SQLite wait policy for locked workflow databases.
const sqliteBusyTimeoutPragma = "busy_timeout=5000"

// Store provides durable workflow persistence.
type Store struct {
	db *sql.DB
}

// Open creates the store database and applies schema migrations.
func Open(ctx context.Context, path string) (*Store, error) {
	resolved := strings.TrimSpace(path)
	if resolved == "" {
		return nil, fmt.Errorf("workflow database path is required")
	}
	if err := ensurePath(resolved); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", databaseDSN(resolved))
	if err != nil {
		return nil, fmt.Errorf("open workflow database %q: %w", resolved, err)
	}
	store := &Store{db: db}
	if err := store.migrate(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

// Close closes the underlying database handle.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

// DB returns the underlying database for focused tests.
func (s *Store) DB() *sql.DB {
	if s == nil {
		return nil
	}
	return s.db
}

// migrate creates the workflow storage tables when missing.
func (s *Store) migrate(ctx context.Context) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS workflow_definitions (
			id TEXT PRIMARY KEY,
			kind TEXT NOT NULL,
			name TEXT NOT NULL,
			hash TEXT NOT NULL,
			body_json TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_runs (
			id TEXT PRIMARY KEY,
			definition_id TEXT NOT NULL,
			kind TEXT NOT NULL,
			status TEXT NOT NULL,
			state TEXT NOT NULL,
			input_json TEXT NOT NULL,
			output_json TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_run_setups (
			id TEXT PRIMARY KEY,
			definition_id TEXT NOT NULL,
			name TEXT NOT NULL,
			description TEXT NOT NULL,
			input_json TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_events (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			run_id TEXT NOT NULL,
			type TEXT NOT NULL,
			message TEXT NOT NULL,
			data_json TEXT NOT NULL,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_step_outputs (
			run_id TEXT NOT NULL,
			step_id TEXT NOT NULL,
			output_json TEXT NOT NULL,
			created_at TEXT NOT NULL,
			PRIMARY KEY (run_id, step_id)
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_node_states (
			run_id TEXT NOT NULL,
			state_id TEXT NOT NULL,
			status TEXT NOT NULL,
			attempts INTEGER NOT NULL,
			output_json TEXT NOT NULL,
			error TEXT NOT NULL,
			started_at TEXT NOT NULL,
			completed_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,
			PRIMARY KEY (run_id, state_id)
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_pending_items (
			id TEXT PRIMARY KEY,
			run_id TEXT NOT NULL,
			step_id TEXT NOT NULL,
			status TEXT NOT NULL,
			prompt TEXT NOT NULL,
			payload_json TEXT NOT NULL,
			response_json TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_drafts (
			id TEXT PRIMARY KEY,
			kind TEXT NOT NULL,
			name TEXT NOT NULL,
			description TEXT NOT NULL,
			status TEXT NOT NULL,
			body_json TEXT NOT NULL,
			validation_json TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_packages (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			version TEXT NOT NULL,
			description TEXT NOT NULL,
			body_json TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_design_artifacts (
			id TEXT PRIMARY KEY,
			kind TEXT NOT NULL,
			name TEXT NOT NULL,
			body_json TEXT NOT NULL,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_observed_contracts (
			definition_id TEXT NOT NULL,
			node_id TEXT NOT NULL,
			tool_id TEXT NOT NULL,
			shape_hash TEXT NOT NULL,
			occurrences INTEGER NOT NULL,
			contract_json TEXT NOT NULL,
			observed_fields_json TEXT NOT NULL,
			first_seen_at TEXT NOT NULL,
			last_seen_at TEXT NOT NULL,
			PRIMARY KEY (definition_id, node_id, tool_id, shape_hash)
		)`,
		`CREATE TABLE IF NOT EXISTS workflow_published_definitions (
			definition_id TEXT PRIMARY KEY,
			draft_id TEXT NOT NULL,
			path TEXT NOT NULL,
			hash TEXT NOT NULL,
			published_at TEXT NOT NULL
		)`,
	}
	for _, statement := range statements {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("migrate workflow database: %w", err)
		}
	}
	return nil
}

// ensurePath creates the database parent directory and private file.
func ensurePath(path string) error {
	if strings.HasPrefix(path, "file:") {
		return nil
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create workflow database directory %q: %w", dir, err)
	}
	file, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return fmt.Errorf("create workflow database %q: %w", path, err)
	}
	return file.Close()
}

// databaseDSN adds SQLite pragmas for concurrent service access.
func databaseDSN(path string) string {
	if strings.HasPrefix(path, "file:") || strings.Contains(path, "?") {
		return path
	}
	values := url.Values{}
	values.Add("_pragma", sqliteBusyTimeoutPragma)
	values.Add("_pragma", "journal_mode=WAL")
	values.Add("_pragma", "foreign_keys=ON")
	values.Add("_pragma", "synchronous=NORMAL")
	return path + "?" + values.Encode()
}
