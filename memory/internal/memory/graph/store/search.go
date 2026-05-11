// This file maintains and queries full-text graph search content.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	graph "memory/internal/memory/graph/domain"
)

// ReindexNode refreshes lexical search content for one node.
func (s *Store) ReindexNode(ctx context.Context, nodeID graph.NodeID) error {
	node, err := s.GetNode(ctx, nodeID)
	if err != nil {
		return err
	}
	aliases, err := s.aliasText(ctx, nodeID)
	if err != nil {
		return err
	}
	properties, err := s.propertyText(ctx, nodeID)
	if err != nil {
		return err
	}
	evidence, err := s.evidenceText(ctx, nodeID)
	if err != nil {
		return err
	}
	if _, err := s.runner.ExecContext(ctx, `DELETE FROM graph_text_fts WHERE node_id = ?`, nodeID); err != nil {
		return fmt.Errorf("delete graph fts row: %w", err)
	}
	if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_text_fts (node_id, title, summary, aliases, properties, evidence_text) VALUES (?, ?, ?, ?, ?, ?)`,
		node.ID, node.Title, node.Summary, aliases, properties, evidence); err != nil {
		return fmt.Errorf("insert graph fts row: %w", err)
	}
	return nil
}

// SearchNodes returns nodes matching a lexical graph search.
func (s *Store) SearchNodes(ctx context.Context, q graph.SearchNodesQuery) ([]graph.Node, error) {
	q, err := graph.NormalizeSearchNodesQuery(q)
	if err != nil {
		return nil, err
	}
	args := []any{graph.StatusActive, q.Scope, graph.ScopeGlobal}
	clauses := []string{"n.status = ?", "(n.scope = ? OR n.scope = ?)"}
	clauses = append(clauses, inClause("n.sensitivity", len(q.AllowedSensitivities)))
	for _, sensitivity := range q.AllowedSensitivities {
		args = append(args, sensitivity)
	}
	if len(q.Kinds) > 0 {
		clauses = append(clauses, inClause("n.kind", len(q.Kinds)))
		for _, kind := range q.Kinds {
			args = append(args, kind)
		}
	}
	join := ""
	order := "ORDER BY n.updated_at DESC, n.id"
	if q.Text != "" {
		join = "JOIN graph_text_fts ON graph_text_fts.node_id = n.id"
		clauses = append(clauses, "graph_text_fts MATCH ?")
		args = append(args, ftsQuery(q.Text))
		order = "ORDER BY bm25(graph_text_fts), n.updated_at DESC"
	}
	args = append(args, q.Limit)
	query := fmt.Sprintf(`SELECT n.id FROM graph_nodes n %s WHERE %s %s LIMIT ?`, join, strings.Join(clauses, " AND "), order)
	rows, err := s.runner.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("search graph nodes: %w", err)
	}
	defer rows.Close()
	ids := []graph.NodeID{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan graph search id: %w", err)
		}
		ids = append(ids, graph.NodeID(id))
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	nodes := make([]graph.Node, 0, len(ids))
	for _, id := range ids {
		node, err := s.GetNode(ctx, id)
		if err != nil {
			return nil, err
		}
		nodes = append(nodes, node)
	}
	return nodes, nil
}

// propertyText returns space-joined active property values for FTS indexing.
func (s *Store) propertyText(ctx context.Context, nodeID graph.NodeID) (string, error) {
	properties, err := s.ListNodeProperties(ctx, nodeID)
	if err != nil {
		return "", err
	}
	values := []string{}
	for _, property := range properties {
		values = append(values, property.Key, valueText(property.Value))
	}
	return strings.Join(values, " "), nil
}

// evidenceText returns source content for FTS indexing when present.
func (s *Store) evidenceText(ctx context.Context, nodeID graph.NodeID) (string, error) {
	content, err := s.ReadEvidenceBlobContent(ctx, nodeID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return content, err
}
