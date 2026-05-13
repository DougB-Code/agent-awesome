// This file configures runtime sessions inside the memory-backed SQLite store.
package sessionstore

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"agentawesome/internal/config/schema"
	"github.com/glebarez/sqlite"
	"google.golang.org/adk/session"
	"google.golang.org/adk/session/database"
	"gorm.io/gorm"
)

const (
	dataDirEnv             = "AGENTAWESOME_DATA_DIR"
	memoryDatabaseEnv      = "MEMORY_DB_PATH"
	sessionDatabaseEnv     = "AGENTAWESOME_SESSION_DB"
	sessionDatabaseDirName = "harness"
	memoryDatabaseDirName  = "memory"
	sessionDatabaseName    = "sessions.db"
	memoryDatabaseName     = "memory.db"
)

// DefaultDataDir returns the harness data directory for persistent runtime files.
func DefaultDataDir() string {
	if dir := strings.TrimSpace(os.Getenv(dataDirEnv)); dir != "" {
		return dir
	}
	configDir, err := os.UserConfigDir()
	if err != nil {
		return filepath.Join(".", schema.AppConfigDirName, "data")
	}
	return filepath.Join(configDir, schema.AppConfigDirName, "data")
}

// DefaultDatabasePath returns the default SQLite path for chat sessions.
func DefaultDatabasePath() string {
	return ResolveDatabasePath("")
}

// ResolveDatabasePath returns an explicit path or the configured default path.
func ResolveDatabasePath(path string) string {
	if resolved := strings.TrimSpace(path); resolved != "" {
		return resolved
	}
	if path := strings.TrimSpace(os.Getenv(sessionDatabaseEnv)); path != "" {
		return path
	}
	if path := strings.TrimSpace(os.Getenv(memoryDatabaseEnv)); path != "" {
		return path
	}
	return filepath.Join(DefaultDataDir(), memoryDatabaseDirName, memoryDatabaseName)
}

// Open creates and migrates a runtime session service in the memory database.
func Open(path string) (session.Service, error) {
	resolved := strings.TrimSpace(path)
	if resolved == "" {
		resolved = ResolveDatabasePath("")
	}
	if err := ensureDatabasePath(resolved); err != nil {
		return nil, err
	}
	service, err := database.NewSessionService(sqlite.Open(databaseDSN(resolved)), &gorm.Config{PrepareStmt: true})
	if err != nil {
		return nil, fmt.Errorf("open runtime session database %q: %w", resolved, err)
	}
	if err := database.AutoMigrate(service); err != nil {
		return nil, fmt.Errorf("migrate runtime session database %q: %w", resolved, err)
	}
	if strings.TrimSpace(path) == "" {
		if err := migrateLegacyDefaultDatabase(context.Background(), resolved); err != nil {
			return nil, err
		}
	}
	return service, nil
}

// LegacyDefaultDatabasePath returns the previous harness-owned chat DB path.
func LegacyDefaultDatabasePath() string {
	return filepath.Join(DefaultDataDir(), sessionDatabaseDirName, sessionDatabaseName)
}

// ensureDatabasePath creates the parent directory and private database file.
func ensureDatabasePath(path string) error {
	if strings.HasPrefix(path, "file:") {
		return nil
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create runtime session database directory %q: %w", dir, err)
	}
	file, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return fmt.Errorf("create runtime session database %q: %w", path, err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close runtime session database %q: %w", path, err)
	}
	return nil
}

// migrateLegacyDefaultDatabase copies sessions from the old default DB once.
func migrateLegacyDefaultDatabase(ctx context.Context, targetPath string) error {
	legacyPath := LegacyDefaultDatabasePath()
	if samePath(legacyPath, targetPath) || !regularFileExists(legacyPath) {
		return nil
	}
	if strings.HasPrefix(targetPath, "file:") {
		return nil
	}
	db, err := sql.Open("sqlite", databaseDSN(targetPath))
	if err != nil {
		return fmt.Errorf("open target runtime session database for migration %q: %w", targetPath, err)
	}
	defer db.Close()
	if _, err := db.ExecContext(ctx, "PRAGMA busy_timeout = 5000"); err != nil {
		return fmt.Errorf("configure target runtime session database migration: %w", err)
	}
	if _, err := db.ExecContext(ctx, "ATTACH DATABASE ? AS legacy_sessions", legacyPath); err != nil {
		return fmt.Errorf("attach legacy runtime session database %q: %w", legacyPath, err)
	}
	defer db.ExecContext(context.Background(), "DETACH DATABASE legacy_sessions")
	for _, table := range legacyTables() {
		if err := copyLegacyTable(ctx, db, table); err != nil {
			return err
		}
	}
	return nil
}

// databaseDSN adds concurrency pragmas for the shared memory SQLite file.
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

// legacyTables returns the runtime session tables copied from the old default DB.
func legacyTables() []legacyTable {
	return []legacyTable{
		{name: "sessions", columns: []string{"app_name", "user_id", "id", "state", "create_time", "update_time"}},
		{name: "events", columns: []string{"id", "app_name", "user_id", "session_id", "invocation_id", "author", "actions", "long_running_tool_ids_json", "branch", "timestamp", "content", "grounding_metadata", "custom_metadata", "usage_metadata", "citation_metadata", "partial", "turn_complete", "error_code", "error_message", "interrupted"}},
		{name: "app_states", columns: []string{"app_name", "state", "update_time"}},
		{name: "user_states", columns: []string{"app_name", "user_id", "state", "update_time"}},
	}
}

// legacyTable describes one runtime session table migration copy.
type legacyTable struct {
	name    string
	columns []string
}

// copyLegacyTable copies one table with INSERT OR IGNORE semantics.
func copyLegacyTable(ctx context.Context, db *sql.DB, table legacyTable) error {
	if ok, err := tableExists(ctx, db, "legacy_sessions", table.name); err != nil {
		return err
	} else if !ok {
		return nil
	}
	columns := strings.Join(table.columns, ", ")
	query := fmt.Sprintf("INSERT OR IGNORE INTO main.%s (%s) SELECT %s FROM legacy_sessions.%s", table.name, columns, columns, table.name)
	if _, err := db.ExecContext(ctx, query); err != nil {
		return fmt.Errorf("migrate legacy runtime session table %s: %w", table.name, err)
	}
	return nil
}

// tableExists reports whether an attached SQLite database has a table.
func tableExists(ctx context.Context, db *sql.DB, databaseName string, tableName string) (bool, error) {
	query := fmt.Sprintf("SELECT name FROM %s.sqlite_master WHERE type = 'table' AND name = ?", databaseName)
	var name string
	if err := db.QueryRowContext(ctx, query, tableName).Scan(&name); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("inspect SQLite table %s.%s: %w", databaseName, tableName, err)
	}
	return true, nil
}

// regularFileExists reports whether a path names an existing regular file.
func regularFileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// samePath reports whether two filesystem paths resolve to the same location.
func samePath(left string, right string) bool {
	if left == "" || right == "" {
		return false
	}
	if filepath.Clean(left) == filepath.Clean(right) {
		return true
	}
	leftAbs, leftErr := filepath.Abs(left)
	rightAbs, rightErr := filepath.Abs(right)
	return leftErr == nil && rightErr == nil && leftAbs == rightAbs
}
