// This file stores and retrieves context graph edges.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	graph "memory/internal/memory/graph/domain"
	"memory/internal/memory/normalize"
)

// UpsertEdge creates or updates one directed graph edge.
func (s *Store) UpsertEdge(ctx context.Context, req graph.UpsertEdgeRequest) (graph.Edge, error) {
	req, err := graph.NormalizeUpsertEdgeRequest(req)
	if err != nil {
		return graph.Edge{}, err
	}
	now := s.now()
	edgeID := req.EdgeID
	if edgeID == "" {
		existing, ok, err := s.edgeIDByIdentity(ctx, req.FromNodeID, req.Type, req.ToNodeID, req.SourceNodeID)
		if err != nil {
			return graph.Edge{}, err
		}
		if ok {
			edgeID = existing
		}
	}
	if edgeID == "" {
		edgeID, err = newEdgeID()
		if err != nil {
			return graph.Edge{}, err
		}
		stamp := timeString(now)
		if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_edges
			(id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, source_node_id, actor, valid_from, valid_to, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			edgeID, req.FromNodeID, req.Type, req.ToNodeID, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, nullableTime(req.ValidFrom), nullableTime(req.ValidTo), stamp, stamp); err != nil {
			return graph.Edge{}, fmt.Errorf("insert graph edge: %w", err)
		}
		return s.GetEdge(ctx, edgeID)
	}
	result, err := s.runner.ExecContext(ctx, `UPDATE graph_edges
		SET from_node_id = ?, relation_type = ?, to_node_id = ?, status = ?, confidence = ?, trust_level = ?, source_node_id = ?, actor = ?, valid_from = ?, valid_to = ?, updated_at = ?
		WHERE id = ?`,
		req.FromNodeID, req.Type, req.ToNodeID, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, nullableTime(req.ValidFrom), nullableTime(req.ValidTo), timeString(now), edgeID)
	if err != nil {
		return graph.Edge{}, fmt.Errorf("update graph edge: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return graph.Edge{}, fmt.Errorf("update graph edge rows: %w", err)
	} else if rows == 0 {
		stamp := timeString(now)
		if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_edges
			(id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, source_node_id, actor, valid_from, valid_to, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			edgeID, req.FromNodeID, req.Type, req.ToNodeID, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, nullableTime(req.ValidFrom), nullableTime(req.ValidTo), stamp, stamp); err != nil {
			return graph.Edge{}, fmt.Errorf("insert graph edge with id: %w", err)
		}
	}
	return s.GetEdge(ctx, edgeID)
}

// SetEdgeStatus updates an edge lifecycle status.
func (s *Store) SetEdgeStatus(ctx context.Context, edgeID graph.EdgeID, status graph.LifecycleStatus, actor string) (graph.Edge, error) {
	if edgeID == "" {
		return graph.Edge{}, errors.New("edge_id is required")
	}
	if !graph.ValidLifecycleStatus(status) {
		return graph.Edge{}, fmt.Errorf("invalid edge status %q", status)
	}
	actor = normalize.Default(actor, "agent")
	result, err := s.runner.ExecContext(ctx, `UPDATE graph_edges SET status = ?, actor = ?, updated_at = ? WHERE id = ?`, status, actor, timeString(s.now()), edgeID)
	if err != nil {
		return graph.Edge{}, fmt.Errorf("set graph edge status: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return graph.Edge{}, fmt.Errorf("set graph edge status rows: %w", err)
	} else if rows == 0 {
		return graph.Edge{}, sql.ErrNoRows
	}
	return s.GetEdge(ctx, edgeID)
}

// GetEdge loads one directed graph edge by id.
func (s *Store) GetEdge(ctx context.Context, edgeID graph.EdgeID) (graph.Edge, error) {
	row := s.runner.QueryRowContext(ctx, `SELECT id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, COALESCE(valid_from, ''), COALESCE(valid_to, ''), created_at, updated_at FROM graph_edges WHERE id = ?`, edgeID)
	return scanEdge(row)
}

// ListOutgoingEdges returns active edges that start at a node.
func (s *Store) ListOutgoingEdges(ctx context.Context, nodeID graph.NodeID, types []graph.RelationType) ([]graph.Edge, error) {
	return s.listEdges(ctx, "from_node_id", nodeID, types)
}

// ListIncomingEdges returns active edges that point to a node.
func (s *Store) ListIncomingEdges(ctx context.Context, nodeID graph.NodeID, types []graph.RelationType) ([]graph.Edge, error) {
	return s.listEdges(ctx, "to_node_id", nodeID, types)
}

// ListEdges returns active edges filtered by relationship type.
func (s *Store) ListEdges(ctx context.Context, types []graph.RelationType, limit int) ([]graph.Edge, error) {
	if limit <= 0 || limit > 1000 {
		limit = 100
	}
	args := []any{graph.StatusActive}
	clauses := []string{"status = ?"}
	if len(types) > 0 {
		clauses = append(clauses, inClause("relation_type", len(types)))
		for _, relation := range types {
			if !graph.ValidRelationType(relation) {
				return nil, fmt.Errorf("invalid relation type %q", relation)
			}
			args = append(args, relation)
		}
	}
	args = append(args, limit)
	query := fmt.Sprintf(`SELECT id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, COALESCE(valid_from, ''), COALESCE(valid_to, ''), created_at, updated_at FROM graph_edges WHERE %s ORDER BY created_at, id LIMIT ?`, strings.Join(clauses, " AND "))
	rows, err := s.runner.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list graph edges: %w", err)
	}
	defer rows.Close()
	edges := []graph.Edge{}
	for rows.Next() {
		edge, err := scanEdge(rows)
		if err != nil {
			return nil, err
		}
		edges = append(edges, edge)
	}
	return edges, rows.Err()
}

// edgeIDByIdentity returns an existing edge id by semantic identity.
func (s *Store) edgeIDByIdentity(ctx context.Context, from graph.NodeID, relation graph.RelationType, to graph.NodeID, source graph.NodeID) (graph.EdgeID, bool, error) {
	var value string
	sourceValue := string(source)
	err := s.runner.QueryRowContext(ctx, `SELECT id FROM graph_edges
		WHERE from_node_id = ? AND relation_type = ? AND to_node_id = ?
		  AND ((source_node_id IS NULL AND ? = '') OR source_node_id = ?)`,
		from, relation, to, sourceValue, sourceValue).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph edge identity: %w", err)
	}
	return graph.EdgeID(value), true, nil
}

// listEdges returns active edges filtered by one endpoint column.
func (s *Store) listEdges(ctx context.Context, endpointColumn string, nodeID graph.NodeID, types []graph.RelationType) ([]graph.Edge, error) {
	if endpointColumn != "from_node_id" && endpointColumn != "to_node_id" {
		return nil, fmt.Errorf("unsupported edge endpoint %q", endpointColumn)
	}
	args := []any{nodeID, graph.StatusActive}
	clauses := []string{endpointColumn + " = ?", "status = ?"}
	if len(types) > 0 {
		clauses = append(clauses, inClause("relation_type", len(types)))
		for _, relation := range types {
			if !graph.ValidRelationType(relation) {
				return nil, fmt.Errorf("invalid relation type %q", relation)
			}
			args = append(args, relation)
		}
	}
	query := fmt.Sprintf(`SELECT id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, COALESCE(valid_from, ''), COALESCE(valid_to, ''), created_at, updated_at FROM graph_edges WHERE %s ORDER BY created_at, id`, strings.Join(clauses, " AND "))
	rows, err := s.runner.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list graph edges: %w", err)
	}
	defer rows.Close()
	edges := []graph.Edge{}
	for rows.Next() {
		edge, err := scanEdge(rows)
		if err != nil {
			return nil, err
		}
		edges = append(edges, edge)
	}
	return edges, rows.Err()
}
