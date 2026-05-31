// This file stores and retrieves context graph nodes.
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

// UpsertNode creates or updates one graph node.
func (s *Store) UpsertNode(ctx context.Context, req graph.UpsertNodeRequest) (graph.Node, error) {
	req, err := graph.NormalizeUpsertNodeRequest(req)
	if err != nil {
		return graph.Node{}, err
	}
	now := s.now()
	nodeID := req.NodeID
	if nodeID == "" && req.StableKey != "" {
		existing, ok, err := s.nodeIDByStableKey(ctx, req.Kind, req.StableKey)
		if err != nil {
			return graph.Node{}, err
		}
		if ok {
			nodeID = existing
		}
	}
	if nodeID == "" {
		nodeID, err = newNodeID()
		if err != nil {
			return graph.Node{}, err
		}
		stamp := timeString(now)
		if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_nodes
			(id, kind, stable_key, title, summary, status, sensitivity, trust_level, confidence, source_node_id, actor, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			nodeID, req.Kind, nullableString(req.StableKey), req.Title, req.Summary, req.Status, req.Sensitivity, req.TrustLevel, req.Confidence, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
			return graph.Node{}, fmt.Errorf("insert graph node: %w", err)
		}
		return s.GetNode(ctx, nodeID)
	}
	result, err := s.runner.ExecContext(ctx, `UPDATE graph_nodes
		SET kind = ?, stable_key = ?, title = ?, summary = ?, status = ?, sensitivity = ?, trust_level = ?, confidence = ?, source_node_id = ?, actor = ?, updated_at = ?
		WHERE id = ?`,
		req.Kind, nullableString(req.StableKey), req.Title, req.Summary, req.Status, req.Sensitivity, req.TrustLevel, req.Confidence, nullableNodeID(req.SourceNodeID), req.Actor, timeString(now), nodeID)
	if err != nil {
		return graph.Node{}, fmt.Errorf("update graph node: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return graph.Node{}, fmt.Errorf("update graph node rows: %w", err)
	} else if rows == 0 {
		stamp := timeString(now)
		if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_nodes
			(id, kind, stable_key, title, summary, status, sensitivity, trust_level, confidence, source_node_id, actor, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			nodeID, req.Kind, nullableString(req.StableKey), req.Title, req.Summary, req.Status, req.Sensitivity, req.TrustLevel, req.Confidence, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
			return graph.Node{}, fmt.Errorf("insert graph node with id: %w", err)
		}
	}
	return s.GetNode(ctx, nodeID)
}

// GetNode loads one graph node by id.
func (s *Store) GetNode(ctx context.Context, nodeID graph.NodeID) (graph.Node, error) {
	var node graph.Node
	var sourceNodeID, stableKey, createdAt, updatedAt string
	row := s.runner.QueryRowContext(ctx, `SELECT id, kind, COALESCE(stable_key, ''), title, summary, status, sensitivity, trust_level, confidence, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_nodes WHERE id = ?`, nodeID)
	if err := row.Scan(&node.ID, &node.Kind, &stableKey, &node.Title, &node.Summary, &node.Status, &node.Sensitivity, &node.TrustLevel, &node.Confidence, &sourceNodeID, &node.Actor, &createdAt, &updatedAt); err != nil {
		return graph.Node{}, fmt.Errorf("load graph node: %w", err)
	}
	node.StableKey = stableKey
	node.SourceNodeID = graph.NodeID(sourceNodeID)
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.Node{}, err
	}
	updated, err := parseTime(updatedAt)
	if err != nil {
		return graph.Node{}, err
	}
	node.CreatedAt = created
	node.UpdatedAt = updated
	return node, nil
}

// GetNodeByStableKey loads one graph node by kind and stable key.
func (s *Store) GetNodeByStableKey(ctx context.Context, kind graph.NodeKind, stableKey string) (graph.Node, error) {
	nodeID, ok, err := s.nodeIDByStableKey(ctx, kind, strings.TrimSpace(stableKey))
	if err != nil {
		return graph.Node{}, err
	}
	if !ok {
		return graph.Node{}, sql.ErrNoRows
	}
	return s.GetNode(ctx, nodeID)
}

// SetNodeStatus updates a graph node lifecycle status.
func (s *Store) SetNodeStatus(ctx context.Context, nodeID graph.NodeID, status graph.LifecycleStatus, actor string) (graph.Node, error) {
	if nodeID == "" {
		return graph.Node{}, errors.New("node_id is required")
	}
	if !graph.ValidLifecycleStatus(status) {
		return graph.Node{}, fmt.Errorf("invalid node status %q", status)
	}
	actor = normalize.Default(actor, graph.DefaultActor)
	result, err := s.runner.ExecContext(ctx, `UPDATE graph_nodes SET status = ?, actor = ?, updated_at = ? WHERE id = ?`, status, actor, timeString(s.now()), nodeID)
	if err != nil {
		return graph.Node{}, fmt.Errorf("set graph node status: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return graph.Node{}, fmt.Errorf("set graph node status rows: %w", err)
	} else if rows == 0 {
		return graph.Node{}, sql.ErrNoRows
	}
	return s.GetNode(ctx, nodeID)
}

// CountNodes returns the number of nodes of one kind and status.
func (s *Store) CountNodes(ctx context.Context, kind graph.NodeKind, status graph.LifecycleStatus) (int64, error) {
	if !graph.ValidNodeKind(kind) {
		return 0, fmt.Errorf("invalid node kind %q", kind)
	}
	if status != "" && !graph.ValidLifecycleStatus(status) {
		return 0, fmt.Errorf("invalid node status %q", status)
	}
	args := []any{kind}
	statusClause := ""
	if status != "" {
		statusClause = " AND status = ?"
		args = append(args, status)
	}
	var count int64
	if err := s.runner.QueryRowContext(ctx, `SELECT COUNT(*) FROM graph_nodes WHERE kind = ?`+statusClause, args...).Scan(&count); err != nil {
		return 0, fmt.Errorf("count graph nodes: %w", err)
	}
	return count, nil
}

// nodeIDByStableKey returns an existing node id by kind and stable key.
func (s *Store) nodeIDByStableKey(ctx context.Context, kind graph.NodeKind, stableKey string) (graph.NodeID, bool, error) {
	var value string
	err := s.runner.QueryRowContext(ctx, `SELECT id FROM graph_nodes WHERE kind = ? AND stable_key = ?`, kind, stableKey).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph node stable key: %w", err)
	}
	return graph.NodeID(value), true, nil
}
