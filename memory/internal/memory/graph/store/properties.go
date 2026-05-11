// This file stores and retrieves context graph node and edge properties.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	graph "memory/internal/memory/graph/domain"
)

// UpsertNodeProperty creates or updates one node property.
func (s *Store) UpsertNodeProperty(ctx context.Context, req graph.UpsertNodePropertyRequest) (graph.NodeProperty, error) {
	req, err := graph.NormalizeUpsertNodePropertyRequest(req)
	if err != nil {
		return graph.NodeProperty{}, err
	}
	propertyID := req.PropertyID
	if propertyID == "" {
		existing, ok, err := s.nodePropertyIDByIdentity(ctx, req.NodeID, req.Key, req.Position, req.SourceNodeID)
		if err != nil {
			return graph.NodeProperty{}, err
		}
		if ok {
			propertyID = existing
		}
	}
	if propertyID == "" {
		propertyID, err = newPropertyID()
		if err != nil {
			return graph.NodeProperty{}, err
		}
		if err := s.insertNodeProperty(ctx, propertyID, req); err != nil {
			return graph.NodeProperty{}, err
		}
		return s.GetNodeProperty(ctx, propertyID)
	}
	if err := s.updateNodeProperty(ctx, propertyID, req); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			if err := s.insertNodeProperty(ctx, propertyID, req); err != nil {
				return graph.NodeProperty{}, err
			}
			return s.GetNodeProperty(ctx, propertyID)
		}
		return graph.NodeProperty{}, err
	}
	return s.GetNodeProperty(ctx, propertyID)
}

// GetNodeProperty loads one node property by id.
func (s *Store) GetNodeProperty(ctx context.Context, propertyID graph.PropertyID) (graph.NodeProperty, error) {
	row := s.runner.QueryRowContext(ctx, `SELECT id, node_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_properties WHERE id = ?`, propertyID)
	return scanNodeProperty(row)
}

// ListNodeProperties returns active properties attached to one node.
func (s *Store) ListNodeProperties(ctx context.Context, nodeID graph.NodeID) ([]graph.NodeProperty, error) {
	rows, err := s.runner.QueryContext(ctx, `SELECT id, node_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_properties WHERE node_id = ? AND status = ? ORDER BY property_key, position, id`, nodeID, graph.StatusActive)
	if err != nil {
		return nil, fmt.Errorf("list node properties: %w", err)
	}
	defer rows.Close()
	properties := []graph.NodeProperty{}
	for rows.Next() {
		property, err := scanNodeProperty(rows)
		if err != nil {
			return nil, err
		}
		properties = append(properties, property)
	}
	return properties, rows.Err()
}

// UpsertEdgeProperty creates or updates one edge property.
func (s *Store) UpsertEdgeProperty(ctx context.Context, req graph.UpsertEdgePropertyRequest) (graph.EdgeProperty, error) {
	req, err := graph.NormalizeUpsertEdgePropertyRequest(req)
	if err != nil {
		return graph.EdgeProperty{}, err
	}
	propertyID := req.PropertyID
	if propertyID == "" {
		existing, ok, err := s.edgePropertyIDByIdentity(ctx, req.EdgeID, req.Key, req.Position, req.SourceNodeID)
		if err != nil {
			return graph.EdgeProperty{}, err
		}
		if ok {
			propertyID = existing
		}
	}
	if propertyID == "" {
		propertyID, err = newPropertyID()
		if err != nil {
			return graph.EdgeProperty{}, err
		}
		if err := s.insertEdgeProperty(ctx, propertyID, req); err != nil {
			return graph.EdgeProperty{}, err
		}
		return s.GetEdgeProperty(ctx, propertyID)
	}
	if err := s.updateEdgeProperty(ctx, propertyID, req); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			if err := s.insertEdgeProperty(ctx, propertyID, req); err != nil {
				return graph.EdgeProperty{}, err
			}
			return s.GetEdgeProperty(ctx, propertyID)
		}
		return graph.EdgeProperty{}, err
	}
	return s.GetEdgeProperty(ctx, propertyID)
}

// GetEdgeProperty loads one edge property by id.
func (s *Store) GetEdgeProperty(ctx context.Context, propertyID graph.PropertyID) (graph.EdgeProperty, error) {
	row := s.runner.QueryRowContext(ctx, `SELECT id, edge_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_edge_properties WHERE id = ?`, propertyID)
	return scanEdgeProperty(row)
}

// ListEdgeProperties returns active properties attached to one edge.
func (s *Store) ListEdgeProperties(ctx context.Context, edgeID graph.EdgeID) ([]graph.EdgeProperty, error) {
	rows, err := s.runner.QueryContext(ctx, `SELECT id, edge_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_edge_properties WHERE edge_id = ? AND status = ? ORDER BY property_key, position, id`, edgeID, graph.StatusActive)
	if err != nil {
		return nil, fmt.Errorf("list edge properties: %w", err)
	}
	defer rows.Close()
	properties := []graph.EdgeProperty{}
	for rows.Next() {
		property, err := scanEdgeProperty(rows)
		if err != nil {
			return nil, err
		}
		properties = append(properties, property)
	}
	return properties, rows.Err()
}

// nodePropertyIDByIdentity returns an existing node property by semantic identity.
func (s *Store) nodePropertyIDByIdentity(ctx context.Context, nodeID graph.NodeID, key string, position int, source graph.NodeID) (graph.PropertyID, bool, error) {
	var value string
	sourceValue := string(source)
	err := s.runner.QueryRowContext(ctx, `SELECT id FROM graph_properties
		WHERE node_id = ? AND property_key = ? AND position = ?
		  AND ((source_node_id IS NULL AND ? = '') OR source_node_id = ?)`,
		nodeID, key, position, sourceValue, sourceValue).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph node property identity: %w", err)
	}
	return graph.PropertyID(value), true, nil
}

// edgePropertyIDByIdentity returns an existing edge property by semantic identity.
func (s *Store) edgePropertyIDByIdentity(ctx context.Context, edgeID graph.EdgeID, key string, position int, source graph.NodeID) (graph.PropertyID, bool, error) {
	var value string
	sourceValue := string(source)
	err := s.runner.QueryRowContext(ctx, `SELECT id FROM graph_edge_properties
		WHERE edge_id = ? AND property_key = ? AND position = ?
		  AND ((source_node_id IS NULL AND ? = '') OR source_node_id = ?)`,
		edgeID, key, position, sourceValue, sourceValue).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph edge property identity: %w", err)
	}
	return graph.PropertyID(value), true, nil
}

// insertNodeProperty stores a new node property.
func (s *Store) insertNodeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertNodePropertyRequest) error {
	now := s.now()
	stamp := timeString(now)
	if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_properties
		(id, node_id, property_key, value_type, value_text, value_number, value_time, value_json, position, status, confidence, trust_level, source_node_id, actor, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		propertyID, req.NodeID, req.Key, req.Value.Type, req.Value.Text, nullableNumber(req.Value), nullableValueTime(req.Value), req.Value.JSON, req.Position, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
		return fmt.Errorf("insert graph node property: %w", err)
	}
	return nil
}

// updateNodeProperty updates an existing node property.
func (s *Store) updateNodeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertNodePropertyRequest) error {
	result, err := s.runner.ExecContext(ctx, `UPDATE graph_properties
		SET node_id = ?, property_key = ?, value_type = ?, value_text = ?, value_number = ?, value_time = ?, value_json = ?, position = ?, status = ?, confidence = ?, trust_level = ?, source_node_id = ?, actor = ?, updated_at = ?
		WHERE id = ?`,
		req.NodeID, req.Key, req.Value.Type, req.Value.Text, nullableNumber(req.Value), nullableValueTime(req.Value), req.Value.JSON, req.Position, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, timeString(s.now()), propertyID)
	if err != nil {
		return fmt.Errorf("update graph node property: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return fmt.Errorf("update graph node property rows: %w", err)
	} else if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// insertEdgeProperty stores a new edge property.
func (s *Store) insertEdgeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertEdgePropertyRequest) error {
	now := s.now()
	stamp := timeString(now)
	if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_edge_properties
		(id, edge_id, property_key, value_type, value_text, value_number, value_time, value_json, position, status, confidence, trust_level, source_node_id, actor, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		propertyID, req.EdgeID, req.Key, req.Value.Type, req.Value.Text, nullableNumber(req.Value), nullableValueTime(req.Value), req.Value.JSON, req.Position, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
		return fmt.Errorf("insert graph edge property: %w", err)
	}
	return nil
}

// updateEdgeProperty updates an existing edge property.
func (s *Store) updateEdgeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertEdgePropertyRequest) error {
	result, err := s.runner.ExecContext(ctx, `UPDATE graph_edge_properties
		SET edge_id = ?, property_key = ?, value_type = ?, value_text = ?, value_number = ?, value_time = ?, value_json = ?, position = ?, status = ?, confidence = ?, trust_level = ?, source_node_id = ?, actor = ?, updated_at = ?
		WHERE id = ?`,
		req.EdgeID, req.Key, req.Value.Type, req.Value.Text, nullableNumber(req.Value), nullableValueTime(req.Value), req.Value.JSON, req.Position, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, timeString(s.now()), propertyID)
	if err != nil {
		return fmt.Errorf("update graph edge property: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return fmt.Errorf("update graph edge property rows: %w", err)
	} else if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}
