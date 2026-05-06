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
	"path/filepath"
	"strings"
	"time"
)

const (
	defaultTimeout = 30 * time.Second
	dbEntryName    = "memory.db"
	dataPrefix     = "data"
)

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

// buildSnapshot archives the SQLite database plus evidence data directory.
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
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.IsDir() {
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
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		return addFileIfExists(writer, path, filepath.ToSlash(filepath.Join(prefix, rel)))
	})
}

// extractSnapshot extracts a snapshot into the SQLite and evidence paths.
func extractSnapshot(reader io.Reader, dbPath string, dataRoot string) error {
	gzipReader, err := gzip.NewReader(reader)
	if err != nil {
		return err
	}
	defer gzipReader.Close()
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o700); err != nil {
		return err
	}
	if err := os.RemoveAll(dataRoot); err != nil {
		return err
	}
	if err := os.MkdirAll(dataRoot, 0o700); err != nil {
		return err
	}
	tarReader := tar.NewReader(gzipReader)
	for {
		header, err := tarReader.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if header.FileInfo().IsDir() {
			continue
		}
		target, ok := snapshotTarget(header.Name, dbPath, dataRoot)
		if !ok {
			continue
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
}

// snapshotTarget maps safe archive entries to local filesystem targets.
func snapshotTarget(name string, dbPath string, dataRoot string) (string, bool) {
	clean := filepath.ToSlash(filepath.Clean(name))
	switch clean {
	case dbEntryName:
		return dbPath, true
	case dbEntryName + "-wal":
		return dbPath + "-wal", true
	case dbEntryName + "-shm":
		return dbPath + "-shm", true
	}
	if strings.HasPrefix(clean, dataPrefix+"/") {
		rel := strings.TrimPrefix(clean, dataPrefix+"/")
		if rel == "" || strings.HasPrefix(rel, "../") || filepath.IsAbs(rel) {
			return "", false
		}
		return filepath.Join(dataRoot, filepath.FromSlash(rel)), true
	}
	return "", false
}
