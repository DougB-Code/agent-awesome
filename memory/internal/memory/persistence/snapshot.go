// This file saves and restores local memory snapshots.
package persistence

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

const (
	defaultTimeout = 30 * time.Second
	dbEntryName    = "memory.db"
	dataPrefix     = "data"
)

// snapshotStaging stores extracted snapshot files before promotion.
type snapshotStaging struct {
	dbStageDir string
	dbPath     string
	walPath    string
	shmPath    string
	dataRoot   string
}

// restoreMove describes one staged path that replaces a live path.
type restoreMove struct {
	source   string
	target   string
	required bool
}

// restoreBackup tracks one live path moved out of the way during promotion.
type restoreBackup struct {
	target    string
	path      string
	parentDir string
	existed   bool
}

// HTTPStore saves memory snapshots through an authenticated HTTP endpoint.
type HTTPStore struct {
	URL     string
	Token   string
	Timeout time.Duration
	Client  *http.Client
}

// Enabled reports whether this store has enough configuration to run.
func (s HTTPStore) Enabled() bool {
	return strings.TrimSpace(s.URL) != "" && strings.TrimSpace(s.Token) != ""
}

// Restore downloads and extracts the latest snapshot into the local store paths.
func (s HTTPStore) Restore(ctx context.Context, dbPath string, dataRoot string) error {
	if !s.Enabled() {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, s.timeout())
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.URL, nil)
	if err != nil {
		return fmt.Errorf("create snapshot restore request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+s.Token)
	resp, err := s.client().Do(req)
	if err != nil {
		return fmt.Errorf("download memory snapshot: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("download memory snapshot: HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read memory snapshot: %w", err)
	}
	if len(data) == 0 {
		return nil
	}
	if err := extractSnapshot(bytes.NewReader(data), dbPath, dataRoot); err != nil {
		return fmt.Errorf("restore memory snapshot: %w", err)
	}
	return nil
}

// Save archives and uploads the current local store paths.
func (s HTTPStore) Save(ctx context.Context, dbPath string, dataRoot string) error {
	if !s.Enabled() {
		return nil
	}
	archive, err := buildSnapshot(dbPath, dataRoot)
	if err != nil {
		return fmt.Errorf("build memory snapshot: %w", err)
	}
	ctx, cancel := context.WithTimeout(ctx, s.timeout())
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, s.URL, bytes.NewReader(archive))
	if err != nil {
		return fmt.Errorf("create snapshot save request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+s.Token)
	req.Header.Set("Content-Type", "application/gzip")
	resp, err := s.client().Do(req)
	if err != nil {
		return fmt.Errorf("upload memory snapshot: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("upload memory snapshot: HTTP %d", resp.StatusCode)
	}
	return nil
}

// timeout returns the configured HTTP timeout or the package default.
func (s HTTPStore) timeout() time.Duration {
	if s.Timeout <= 0 {
		return defaultTimeout
	}
	return s.Timeout
}

// client returns the configured HTTP client or a default client.
func (s HTTPStore) client() *http.Client {
	if s.Client != nil {
		return s.Client
	}
	return &http.Client{Timeout: s.timeout()}
}

// buildSnapshot archives the SQLite database plus source data directory.
func buildSnapshot(dbPath string, dataRoot string) ([]byte, error) {
	var buf bytes.Buffer
	gzipWriter := gzip.NewWriter(&buf)
	tarWriter := tar.NewWriter(gzipWriter)
	if err := addFileIfExists(tarWriter, dbPath, dbEntryName); err != nil {
		_ = tarWriter.Close()
		_ = gzipWriter.Close()
		return nil, err
	}
	if err := addFileIfExists(tarWriter, dbPath+"-wal", dbEntryName+"-wal"); err != nil {
		_ = tarWriter.Close()
		_ = gzipWriter.Close()
		return nil, err
	}
	if err := addFileIfExists(tarWriter, dbPath+"-shm", dbEntryName+"-shm"); err != nil {
		_ = tarWriter.Close()
		_ = gzipWriter.Close()
		return nil, err
	}
	if err := addDirectory(tarWriter, dataRoot, dataPrefix); err != nil {
		_ = tarWriter.Close()
		_ = gzipWriter.Close()
		return nil, err
	}
	if err := tarWriter.Close(); err != nil {
		_ = gzipWriter.Close()
		return nil, err
	}
	if err := gzipWriter.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// addFileIfExists adds one file to the archive when it is present.
func addFileIfExists(writer *tar.Writer, path string, name string) error {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.IsDir() || !info.Mode().IsRegular() {
		return nil
	}
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	header, err := tar.FileInfoHeader(info, "")
	if err != nil {
		return err
	}
	header.Name = name
	if err := writer.WriteHeader(header); err != nil {
		return err
	}
	_, err = io.Copy(writer, file)
	return err
}

// addDirectory adds all regular files under a directory to the archive.
func addDirectory(writer *tar.Writer, root string, prefix string) error {
	info, err := os.Stat(root)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return nil
	}
	return filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		return addFileIfExists(writer, path, filepath.ToSlash(filepath.Join(prefix, rel)))
	})
}

// extractSnapshot extracts a snapshot into the SQLite and source paths.
func extractSnapshot(reader io.Reader, dbPath string, dataRoot string) error {
	gzipReader, err := gzip.NewReader(reader)
	if err != nil {
		return err
	}
	defer gzipReader.Close()
	staging, err := newSnapshotStaging(dbPath, dataRoot)
	if err != nil {
		return err
	}
	defer staging.cleanup()

	tarReader := tar.NewReader(gzipReader)
	for {
		header, err := tarReader.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return err
		}
		target, ok, err := snapshotTarget(header.Name, staging.dbPath, staging.dataRoot)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}
		if header.FileInfo().IsDir() {
			continue
		}
		if header.Typeflag != tar.TypeReg && header.Typeflag != tar.TypeRegA {
			return fmt.Errorf("unsupported snapshot entry %q", header.Name)
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
			return err
		}
		file, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(file, tarReader)
		closeErr := file.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
	}
	if err := staging.validate(); err != nil {
		return err
	}
	if err := promoteSnapshot(staging, dbPath, dataRoot); err != nil {
		return err
	}
	return nil
}

// snapshotTarget maps safe archive entries to local filesystem targets.
func snapshotTarget(name string, dbPath string, dataRoot string) (string, bool, error) {
	clean, err := cleanSnapshotEntryName(name)
	if err != nil {
		return "", false, err
	}
	switch clean {
	case dbEntryName:
		return dbPath, true, nil
	case dbEntryName + "-wal":
		return dbPath + "-wal", true, nil
	case dbEntryName + "-shm":
		return dbPath + "-shm", true, nil
	}
	if strings.HasPrefix(clean, dataPrefix+"/") {
		rel := strings.TrimPrefix(clean, dataPrefix+"/")
		if rel == "" {
			return "", false, nil
		}
		return filepath.Join(dataRoot, filepath.FromSlash(rel)), true, nil
	}
	return "", false, nil
}

// cleanSnapshotEntryName returns a normalized archive path or rejects traversal.
func cleanSnapshotEntryName(name string) (string, error) {
	raw := filepath.ToSlash(strings.TrimSpace(name))
	if raw == "" || raw == "." || path.IsAbs(raw) || filepath.IsAbs(name) || filepath.VolumeName(name) != "" {
		return "", fmt.Errorf("unsafe snapshot entry %q", name)
	}
	for _, segment := range strings.Split(raw, "/") {
		if segment == ".." {
			return "", fmt.Errorf("unsafe snapshot entry %q", name)
		}
	}
	clean := path.Clean(raw)
	if clean == "." {
		return "", fmt.Errorf("unsafe snapshot entry %q", name)
	}
	return clean, nil
}

// newSnapshotStaging creates restore temp paths beside their final locations.
func newSnapshotStaging(dbPath string, dataRoot string) (*snapshotStaging, error) {
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o700); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(dataRoot), 0o700); err != nil {
		return nil, err
	}
	dbStageDir, err := os.MkdirTemp(filepath.Dir(dbPath), ".agentawesome-snapshot-db-*")
	if err != nil {
		return nil, err
	}
	dataStageRoot, err := os.MkdirTemp(filepath.Dir(dataRoot), ".agentawesome-snapshot-data-*")
	if err != nil {
		_ = os.RemoveAll(dbStageDir)
		return nil, err
	}
	return &snapshotStaging{
		dbStageDir: dbStageDir,
		dbPath:     filepath.Join(dbStageDir, dbEntryName),
		walPath:    filepath.Join(dbStageDir, dbEntryName+"-wal"),
		shmPath:    filepath.Join(dbStageDir, dbEntryName+"-shm"),
		dataRoot:   dataStageRoot,
	}, nil
}

// cleanup removes temporary staging paths after restore success or failure.
func (s *snapshotStaging) cleanup() {
	if s == nil {
		return
	}
	_ = os.RemoveAll(s.dbStageDir)
	_ = os.RemoveAll(s.dataRoot)
}

// validate verifies required extracted snapshot files before touching live data.
func (s *snapshotStaging) validate() error {
	info, err := os.Stat(s.dbPath)
	if errors.Is(err, os.ErrNotExist) {
		return errors.New("snapshot missing memory database")
	}
	if err != nil {
		return err
	}
	if info.IsDir() {
		return errors.New("snapshot memory database is not a regular file")
	}
	return nil
}

// promoteSnapshot replaces live snapshot paths and rolls back on failure.
func promoteSnapshot(staging *snapshotStaging, dbPath string, dataRoot string) error {
	moves := []restoreMove{
		{source: staging.dbPath, target: dbPath, required: true},
		{source: staging.walPath, target: dbPath + "-wal"},
		{source: staging.shmPath, target: dbPath + "-shm"},
		{source: staging.dataRoot, target: dataRoot, required: true},
	}
	backups := []restoreBackup{}
	promoted := []string{}
	rollback := func() {
		for i := len(promoted) - 1; i >= 0; i-- {
			_ = os.RemoveAll(promoted[i])
		}
		for i := len(backups) - 1; i >= 0; i-- {
			_ = backups[i].restore()
		}
	}
	for _, move := range moves {
		sourceExists, err := pathExists(move.source)
		if err != nil {
			rollback()
			return err
		}
		if !sourceExists && move.required {
			rollback()
			return fmt.Errorf("snapshot missing required path %s", filepath.Base(move.source))
		}
		backup, err := backupRestoreTarget(move.target)
		if err != nil {
			rollback()
			return err
		}
		if backup.existed {
			backups = append(backups, backup)
		}
		if !sourceExists {
			continue
		}
		if err := os.Rename(move.source, move.target); err != nil {
			rollback()
			return err
		}
		promoted = append(promoted, move.target)
		if err := syncDirectory(filepath.Dir(move.target)); err != nil {
			rollback()
			return err
		}
	}
	for _, backup := range backups {
		_ = os.RemoveAll(backup.parentDir)
	}
	return nil
}

// backupRestoreTarget moves an existing live path aside before promotion.
func backupRestoreTarget(target string) (restoreBackup, error) {
	exists, err := pathExists(target)
	if err != nil {
		return restoreBackup{}, err
	}
	if !exists {
		return restoreBackup{target: target}, nil
	}
	parentDir, err := os.MkdirTemp(filepath.Dir(target), ".agentawesome-restore-backup-*")
	if err != nil {
		return restoreBackup{}, err
	}
	backupPath := filepath.Join(parentDir, filepath.Base(target))
	if err := os.Rename(target, backupPath); err != nil {
		_ = os.RemoveAll(parentDir)
		return restoreBackup{}, err
	}
	return restoreBackup{target: target, path: backupPath, parentDir: parentDir, existed: true}, nil
}

// restore moves one backup path back to its live location.
func (b restoreBackup) restore() error {
	if !b.existed {
		return nil
	}
	_ = os.RemoveAll(b.target)
	if err := os.MkdirAll(filepath.Dir(b.target), 0o700); err != nil {
		return err
	}
	return os.Rename(b.path, b.target)
}

// pathExists reports whether a filesystem path exists.
func pathExists(path string) (bool, error) {
	if _, err := os.Lstat(path); errors.Is(err, os.ErrNotExist) {
		return false, nil
	} else if err != nil {
		return false, err
	}
	return true, nil
}

// syncDirectory flushes directory metadata after restore renames.
func syncDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
