// This file configures runtime sessions inside the memory-backed SQLite store.
package sessionstore

import (
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
	dataDirEnv            = "AGENTAWESOME_DATA_DIR"
	memoryDatabaseEnv     = "MEMORY_DB_PATH"
	sessionDatabaseEnv    = "AGENTAWESOME_SESSION_DB"
	memoryDatabaseDirName = "memory"
	memoryDatabaseName    = "memory.db"
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
	return service, nil
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
