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

	_ "modernc.org/sqlite"
)

const agentSpecTableStatement = `CREATE TABLE IF NOT EXISTS workflow_agent_specs (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	description TEXT NOT NULL,
	instructions TEXT NOT NULL,
	permissions_json TEXT NOT NULL,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
)`

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
		`CREATE TABLE IF NOT EXISTS workflow_templates (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT NOT NULL,
			category TEXT NOT NULL,
			tags_json TEXT NOT NULL,
			parameters_json TEXT NOT NULL,
			requirements_json TEXT NOT NULL,
			body_json TEXT NOT NULL,
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
		agentSpecTableStatement,
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
	if err := s.migrateAgentSpecTable(ctx); err != nil {
		return err
	}
	return nil
}

// migrateAgentSpecTable rebuilds agent specs into the current permission model.
func (s *Store) migrateAgentSpecTable(ctx context.Context) error {
	columns, err := s.tableColumns(ctx, "workflow_agent_specs")
	if err != nil {
		return err
	}
	expected := []string{"id", "name", "description", "instructions", "permissions_json", "created_at", "updated_at"}
	if hasOnlyColumns(columns, expected) {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin agent spec migration: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DROP TABLE IF EXISTS workflow_agent_specs_rebuild`); err != nil {
		return fmt.Errorf("prepare agent spec migration: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `ALTER TABLE workflow_agent_specs RENAME TO workflow_agent_specs_rebuild`); err != nil {
		return fmt.Errorf("rename agent spec table: %w", err)
	}
	if _, err := tx.ExecContext(ctx, agentSpecTableStatement); err != nil {
		return fmt.Errorf("create migrated agent spec table: %w", err)
	}
	permissionsColumn := `'{}'`
	if columns["permissions_json"] {
		permissionsColumn = "permissions_json"
	}
	copyStatement := `INSERT INTO workflow_agent_specs
		(id, name, description, instructions, permissions_json, created_at, updated_at)
		SELECT id, name, description, instructions, ` + permissionsColumn + `, created_at, updated_at
		FROM workflow_agent_specs_rebuild`
	if _, err := tx.ExecContext(ctx, copyStatement); err != nil {
		return fmt.Errorf("copy migrated agent specs: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `DROP TABLE workflow_agent_specs_rebuild`); err != nil {
		return fmt.Errorf("drop rebuilt agent spec table: %w", err)
	}
	return tx.Commit()
}

// tableColumns returns the column names currently present on a SQLite table.
func (s *Store) tableColumns(ctx context.Context, table string) (map[string]bool, error) {
	if strings.TrimSpace(table) != "workflow_agent_specs" {
		return nil, fmt.Errorf("unsupported table inspection %q", table)
	}
	rows, err := s.db.QueryContext(ctx, "PRAGMA table_info("+table+")")
	if err != nil {
		return nil, fmt.Errorf("inspect table %q: %w", table, err)
	}
	defer rows.Close()
	columns := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, columnType string
		var notNull, primaryKey int
		var defaultValue any
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &primaryKey); err != nil {
			return nil, fmt.Errorf("inspect table %q column: %w", table, err)
		}
		columns[name] = true
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("inspect table %q columns: %w", table, err)
	}
	return columns, nil
}

// hasOnlyColumns reports whether the table column set matches the expected set.
func hasOnlyColumns(columns map[string]bool, expected []string) bool {
	if len(columns) != len(expected) {
		return false
	}
	for _, column := range expected {
		if !columns[column] {
			return false
		}
	}
	return true
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
	values.Add("_pragma", "busy_timeout=5000")
	values.Add("_pragma", "journal_mode=WAL")
	values.Add("_pragma", "foreign_keys=ON")
	values.Add("_pragma", "synchronous=NORMAL")
	return path + "?" + values.Encode()
}
