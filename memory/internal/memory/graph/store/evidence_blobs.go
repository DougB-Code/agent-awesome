// This file stores evidence blob metadata and source content references.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"

	graph "memory/internal/memory/graph/domain"
)

// WriteEvidenceBlob writes source content for an evidence node.
func (s *Store) WriteEvidenceBlob(ctx context.Context, req graph.WriteEvidenceBlobRequest) (graph.EvidenceBlob, error) {
	req, err := graph.NormalizeWriteEvidenceBlobRequest(req)
	if err != nil {
		return graph.EvidenceBlob{}, err
	}
	existingPath, hadExisting, lookupErr := s.evidenceBlobExists(ctx, req.NodeID)
	if lookupErr != nil {
		return graph.EvidenceBlob{}, lookupErr
	}
	write, err := s.writeEvidenceFile(req.NodeID, req.Content)
	if err != nil {
		return graph.EvidenceBlob{}, err
	}
	now := s.now()
	if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_evidence_blobs
		(node_id, checksum, path, media_type, source_system, source_id, size_bytes, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(node_id) DO UPDATE SET checksum = excluded.checksum, path = excluded.path, media_type = excluded.media_type, source_system = excluded.source_system, source_id = excluded.source_id, size_bytes = excluded.size_bytes`,
		req.NodeID, write.checksum, write.relPath, req.MediaType, req.SourceSystem, req.SourceID, write.size, timeString(now)); err != nil {
		s.discardEvidenceFile(write)
		return graph.EvidenceBlob{}, fmt.Errorf("write graph source blob: %w", err)
	}
	if _, err := s.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "write_evidence_blob",
		Actor:         req.Actor,
		SubjectNodeID: req.NodeID,
		SourceNodeID:  req.SourceNodeID,
		Message:       "wrote graph source content",
		DetailsJSON:   evidenceBlobAuditDetails(req, write.checksum, write.size),
	}); err != nil {
		s.discardEvidenceFile(write)
		return graph.EvidenceBlob{}, err
	}
	if hadExisting && existingPath != write.relPath {
		s.removeSupersededEvidenceFile(existingPath)
	}
	return s.GetEvidenceBlob(ctx, req.NodeID)
}

// evidenceBlobAuditDetails serializes source write metadata for auditing.
func evidenceBlobAuditDetails(req graph.WriteEvidenceBlobRequest, checksum string, size int64) string {
	details := map[string]any{
		"checksum":      checksum,
		"media_type":    req.MediaType,
		"size_bytes":    size,
		"source_system": req.SourceSystem,
		"source_id":     req.SourceID,
	}
	bytes, err := json.Marshal(details)
	if err != nil {
		return ""
	}
	return string(bytes)
}

// GetEvidenceBlob loads metadata for one evidence node.
func (s *Store) GetEvidenceBlob(ctx context.Context, nodeID graph.NodeID) (graph.EvidenceBlob, error) {
	var blob graph.EvidenceBlob
	var createdAt string
	if err := s.runner.QueryRowContext(ctx, `SELECT node_id, checksum, path, media_type, source_system, source_id, size_bytes, created_at FROM graph_evidence_blobs WHERE node_id = ?`, nodeID).
		Scan(&blob.NodeID, &blob.Checksum, &blob.Path, &blob.MediaType, &blob.SourceSystem, &blob.SourceID, &blob.SizeBytes, &createdAt); err != nil {
		return graph.EvidenceBlob{}, fmt.Errorf("load graph source blob: %w", err)
	}
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.EvidenceBlob{}, err
	}
	blob.CreatedAt = created
	return blob, nil
}

// ReadEvidenceBlobContent reads source content from disk.
func (s *Store) ReadEvidenceBlobContent(ctx context.Context, nodeID graph.NodeID) (string, error) {
	blob, err := s.GetEvidenceBlob(ctx, nodeID)
	if err != nil {
		return "", err
	}
	if s.stagedEvidenceByNode != nil {
		if stagedPath := s.stagedEvidenceByNode[nodeID]; stagedPath != "" {
			bytes, err := os.ReadFile(stagedPath)
			if err != nil {
				return "", fmt.Errorf("read staged graph source file: %w", err)
			}
			return string(bytes), nil
		}
	}
	bytes, err := os.ReadFile(s.safePath(blob.Path))
	if err != nil {
		return "", fmt.Errorf("read graph source file: %w", err)
	}
	return string(bytes), nil
}

// evidenceBlobExists reports whether a source blob row already exists.
func (s *Store) evidenceBlobExists(ctx context.Context, nodeID graph.NodeID) (string, bool, error) {
	var path string
	err := s.runner.QueryRowContext(ctx, `SELECT path FROM graph_evidence_blobs WHERE node_id = ?`, nodeID).Scan(&path)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph source blob: %w", err)
	}
	return path, true, nil
}
