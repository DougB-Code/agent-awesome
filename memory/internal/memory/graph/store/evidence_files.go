// This file manages filesystem evidence blobs for the SQLite graph store.
package store

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	graph "memory/internal/memory/graph/domain"
)

// evidenceFileWrite tracks one filesystem write staged for transaction commit.
type evidenceFileWrite struct {
	nodeID    graph.NodeID
	checksum  string
	relPath   string
	tmpPath   string
	finalPath string
	size      int64
	created   bool
	staged    bool
	committed bool
}

// writeEvidenceFile writes or stages content for a stable source path.
func (s *Store) writeEvidenceFile(nodeID graph.NodeID, content string) (evidenceFileWrite, error) {
	bytes := []byte(content)
	sum := sha256.Sum256(bytes)
	checksum := fmt.Sprintf("%x", sum[:])
	relPath := filepath.Join("sources", string(nodeID)+"-"+checksum+".txt")
	fullPath := s.safePath(relPath)
	dir := filepath.Dir(fullPath)
	write := evidenceFileWrite{
		nodeID:    nodeID,
		checksum:  checksum,
		relPath:   relPath,
		finalPath: fullPath,
		size:      int64(len(bytes)),
	}
	if _, err := os.Stat(fullPath); err == nil {
		return write, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return evidenceFileWrite{}, fmt.Errorf("stat graph source file: %w", err)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return evidenceFileWrite{}, fmt.Errorf("create graph source directory: %w", err)
	}
	tmp, err := os.CreateTemp(dir, ".source-*.tmp")
	if err != nil {
		return evidenceFileWrite{}, fmt.Errorf("create graph source temp file: %w", err)
	}
	tmpPath := tmp.Name()
	cleanupTemp := true
	defer func() {
		if cleanupTemp {
			_ = removePathIfExists(tmpPath)
		}
	}()
	if _, err := tmp.Write(bytes); err != nil {
		_ = tmp.Close()
		return evidenceFileWrite{}, fmt.Errorf("write graph source temp file: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return evidenceFileWrite{}, fmt.Errorf("sync graph source temp file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return evidenceFileWrite{}, fmt.Errorf("close graph source temp file: %w", err)
	}
	write.tmpPath = tmpPath
	write.created = true
	if s.inUnitOfWork {
		write.staged = true
		s.stagedEvidenceFiles = append(s.stagedEvidenceFiles, write)
		if s.stagedEvidenceByNode == nil {
			s.stagedEvidenceByNode = map[graph.NodeID]string{}
		}
		s.stagedEvidenceByNode[nodeID] = tmpPath
		cleanupTemp = false
		return write, nil
	}
	if err := os.Rename(tmpPath, fullPath); err != nil {
		return evidenceFileWrite{}, fmt.Errorf("commit graph source file: %w", err)
	}
	cleanupTemp = false
	write.committed = true
	if err := syncDirectory(dir); err != nil {
		_ = removePathIfExists(fullPath)
		return evidenceFileWrite{}, fmt.Errorf("sync graph source directory: %w", err)
	}
	return write, nil
}

// discardEvidenceFile removes a write that did not reach database metadata.
func (s *Store) discardEvidenceFile(write evidenceFileWrite) {
	if !write.created {
		return
	}
	if write.staged {
		_ = removePathIfExists(write.tmpPath)
		if s.stagedEvidenceByNode != nil {
			delete(s.stagedEvidenceByNode, write.nodeID)
		}
		return
	}
	_ = removePathIfExists(write.finalPath)
}

// removeSupersededEvidenceFile schedules or removes an obsolete source path.
func (s *Store) removeSupersededEvidenceFile(relPath string) {
	if strings.TrimSpace(relPath) == "" {
		return
	}
	if s.inUnitOfWork {
		s.evidenceRemovals = append(s.evidenceRemovals, relPath)
		return
	}
	_ = s.removeEvidenceFile(relPath)
}

// commitEvidenceFiles atomically publishes staged source files before commit.
func (s *Store) commitEvidenceFiles() error {
	for index := range s.stagedEvidenceFiles {
		write := &s.stagedEvidenceFiles[index]
		if !write.created || !write.staged {
			continue
		}
		if _, err := os.Stat(write.finalPath); err == nil {
			_ = removePathIfExists(write.tmpPath)
			write.created = false
			continue
		} else if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("stat staged graph source file: %w", err)
		}
		if err := os.Rename(write.tmpPath, write.finalPath); err != nil {
			return fmt.Errorf("commit staged graph source file: %w", err)
		}
		write.committed = true
		if err := syncDirectory(filepath.Dir(write.finalPath)); err != nil {
			return fmt.Errorf("sync graph source directory: %w", err)
		}
	}
	return nil
}

// cleanupEvidenceFiles removes staged and committed files after rollback.
func (s *Store) cleanupEvidenceFiles() {
	for _, write := range s.stagedEvidenceFiles {
		if !write.created {
			continue
		}
		if write.committed {
			_ = removePathIfExists(write.finalPath)
			continue
		}
		_ = removePathIfExists(write.tmpPath)
	}
}

// cleanupCommittedEvidenceFiles removes files published before a failed commit.
func (s *Store) cleanupCommittedEvidenceFiles() {
	s.cleanupEvidenceFiles()
}

// cleanupSupersededEvidenceFiles removes old source files after commit.
func (s *Store) cleanupSupersededEvidenceFiles() {
	for _, relPath := range s.evidenceRemovals {
		_ = s.removeEvidenceFile(relPath)
	}
}

// removeEvidenceFile deletes a committed source file when it is safe to do so.
func (s *Store) removeEvidenceFile(relPath string) error {
	return removePathIfExists(s.safePath(relPath))
}

// removePathIfExists deletes a path and ignores missing files.
func removePathIfExists(path string) error {
	if strings.TrimSpace(path) == "" {
		return nil
	}
	err := os.Remove(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

// syncDirectory flushes directory metadata after atomic file renames.
func syncDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

// safePath constrains stored relative paths under the data root.
func (s *Store) safePath(relPath string) string {
	clean := filepath.Clean(string(filepath.Separator) + relPath)
	clean = strings.TrimLeft(clean, string(filepath.Separator))
	return filepath.Join(s.dataRoot, clean)
}
