// This file implements SQLite-backed context graph persistence.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	graph "memory/internal/memory/graph/domain"

	_ "modernc.org/sqlite"
)

// sqlRunner is the common SQL surface shared by database and transaction handles.
type sqlRunner interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

// Config contains filesystem and SQLite settings for the graph store.
type Config struct {
	DBPath   string
	DataRoot string
}

// Store owns SQLite graph metadata and filesystem source blobs.
type Store struct {
	db                   *sql.DB
	runner               sqlRunner
	dataRoot             string
	now                  func() time.Time
	inUnitOfWork         bool
	stagedEvidenceFiles  []evidenceFileWrite
	stagedEvidenceByNode map[graph.NodeID]string
	evidenceRemovals     []string
}

// Open creates a graph store and applies SQLite schema.
func Open(ctx context.Context, cfg Config) (*Store, error) {
	if strings.TrimSpace(cfg.DBPath) == "" {
		cfg.DBPath = "context_graph.db"
	}
	if strings.TrimSpace(cfg.DataRoot) == "" {
		cfg.DataRoot = "data"
	}
	if err := os.MkdirAll(filepath.Join(cfg.DataRoot, "sources"), 0o700); err != nil {
		return nil, fmt.Errorf("create graph sources directory: %w", err)
	}
	db, err := sql.Open("sqlite", cfg.DBPath)
	if err != nil {
		return nil, fmt.Errorf("open graph sqlite: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	store := &Store{
		db:       db,
		runner:   db,
		dataRoot: cfg.DataRoot,
		now:      func() time.Time { return time.Now().UTC() },
	}
	if err := store.configure(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.ExecContext(ctx, schemaSQL); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("apply graph schema: %w", err)
	}
	if err := store.migrate(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

// Close releases SQLite resources.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

// WithUnitOfWork runs graph operations in one SQLite transaction.
func (s *Store) WithUnitOfWork(ctx context.Context, work func(*Store) error) error {
	if s == nil || s.db == nil {
		return errors.New("graph store is closed")
	}
	if s.inUnitOfWork {
		return errors.New("nested graph unit of work is not supported")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin graph unit of work: %w", err)
	}
	txStore := &Store{
		db:                   s.db,
		runner:               tx,
		dataRoot:             s.dataRoot,
		now:                  s.now,
		inUnitOfWork:         true,
		stagedEvidenceByNode: map[graph.NodeID]string{},
	}
	finished := false
	defer func() {
		if !finished {
			_ = tx.Rollback()
			txStore.cleanupEvidenceFiles()
		}
	}()
	if err := work(txStore); err != nil {
		return err
	}
	if err := txStore.commitEvidenceFiles(); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		txStore.cleanupCommittedEvidenceFiles()
		return fmt.Errorf("commit graph unit of work: %w", err)
	}
	finished = true
	txStore.cleanupSupersededEvidenceFiles()
	return nil
}

// configure applies SQLite pragmas needed for concurrent local service use.
func (s *Store) configure(ctx context.Context) error {
	pragmas := []string{
		"PRAGMA journal_mode = WAL",
		"PRAGMA busy_timeout = 5000",
		"PRAGMA foreign_keys = ON",
		"PRAGMA synchronous = NORMAL",
	}
	for _, pragma := range pragmas {
		if _, err := s.runner.ExecContext(ctx, pragma); err != nil {
			return fmt.Errorf("configure graph sqlite %q: %w", pragma, err)
		}
	}
	return nil
}

// migrate removes legacy graph storage columns that moved to repository routing.
func (s *Store) migrate(ctx context.Context) error {
	if _, err := s.runner.ExecContext(ctx, "DROP INDEX IF EXISTS idx_graph_nodes_firewall_sensitivity"); err != nil {
		return fmt.Errorf("drop legacy graph firewall index: %w", err)
	}
	hasFirewall, err := s.hasColumn(ctx, "graph_nodes", "firewall")
	if err != nil {
		return err
	}
	if !hasFirewall {
		return nil
	}
	if _, err := s.runner.ExecContext(ctx, "ALTER TABLE graph_nodes DROP COLUMN firewall"); err != nil {
		return fmt.Errorf("drop legacy graph firewall column: %w", err)
	}
	return nil
}

// hasColumn reports whether a known graph table still has a column.
func (s *Store) hasColumn(ctx context.Context, table string, column string) (bool, error) {
	rows, err := s.runner.QueryContext(ctx, "PRAGMA table_info("+table+")")
	if err != nil {
		return false, fmt.Errorf("inspect graph table %s: %w", table, err)
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name string
		var columnType string
		var notNull int
		var defaultValue any
		var primaryKey int
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &primaryKey); err != nil {
			return false, fmt.Errorf("scan graph table %s columns: %w", table, err)
		}
		if name == column {
			return true, nil
		}
	}
	if err := rows.Err(); err != nil {
		return false, fmt.Errorf("inspect graph table %s columns: %w", table, err)
	}
	return false, nil
}
