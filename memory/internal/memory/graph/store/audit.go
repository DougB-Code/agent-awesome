// This file appends and lists graph audit events.
package store

import (
	"context"
	"fmt"

	graph "memory/internal/memory/graph/domain"
)

// AppendAudit stores one append-only graph audit event.
func (s *Store) AppendAudit(ctx context.Context, req graph.AppendAuditRequest) (graph.AuditEvent, error) {
	req, err := graph.NormalizeAppendAuditRequest(req)
	if err != nil {
		return graph.AuditEvent{}, err
	}
	auditID := req.AuditID
	if auditID == "" {
		auditID, err = newAuditID()
		if err != nil {
			return graph.AuditEvent{}, err
		}
	}
	now := s.now()
	if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_audit_events
		(id, event_kind, actor, subject_node_id, subject_edge_id, source_node_id, message, details_json, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		auditID, req.Kind, req.Actor, nullableNodeID(req.SubjectNodeID), nullableEdgeID(req.SubjectEdgeID), nullableNodeID(req.SourceNodeID), req.Message, req.DetailsJSON, timeString(now)); err != nil {
		return graph.AuditEvent{}, fmt.Errorf("append graph audit: %w", err)
	}
	return graph.AuditEvent{ID: auditID, Kind: req.Kind, Actor: req.Actor, SubjectNodeID: req.SubjectNodeID, SubjectEdgeID: req.SubjectEdgeID, SourceNodeID: req.SourceNodeID, Message: req.Message, DetailsJSON: req.DetailsJSON, CreatedAt: now}, nil
}

// ListAuditEvents returns recent graph audit events for verification and inspection.
func (s *Store) ListAuditEvents(ctx context.Context, limit int) ([]graph.AuditEvent, error) {
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	rows, err := s.runner.QueryContext(ctx, `SELECT id, event_kind, actor, COALESCE(subject_node_id, ''), COALESCE(subject_edge_id, ''), COALESCE(source_node_id, ''), message, details_json, created_at FROM graph_audit_events ORDER BY created_at DESC, id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, fmt.Errorf("list graph audit events: %w", err)
	}
	defer rows.Close()
	events := []graph.AuditEvent{}
	for rows.Next() {
		event, err := scanAuditEvent(rows)
		if err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}
