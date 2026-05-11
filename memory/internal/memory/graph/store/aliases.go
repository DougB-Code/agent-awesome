// This file stores aliases and prepares alias text for graph search.
package store

import (
	"context"
	"fmt"
	"strings"

	graph "memory/internal/memory/graph/domain"
)

// UpsertAlias creates or updates one node alias.
func (s *Store) UpsertAlias(ctx context.Context, req graph.UpsertAliasRequest) (graph.Alias, error) {
	req, err := graph.NormalizeUpsertAliasRequest(req)
	if err != nil {
		return graph.Alias{}, err
	}
	stamp := timeString(s.now())
	if _, err := s.runner.ExecContext(ctx, `INSERT INTO graph_aliases (node_id, locale, alias, alias_kind, created_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(node_id, locale, alias) DO UPDATE SET alias_kind = excluded.alias_kind`,
		req.NodeID, req.Locale, req.Alias, req.Kind, stamp); err != nil {
		return graph.Alias{}, fmt.Errorf("upsert graph alias: %w", err)
	}
	return graph.Alias{NodeID: req.NodeID, Locale: req.Locale, Alias: req.Alias, Kind: req.Kind, CreatedAt: s.now()}, nil
}

// aliasText returns space-joined aliases for FTS indexing.
func (s *Store) aliasText(ctx context.Context, nodeID graph.NodeID) (string, error) {
	rows, err := s.runner.QueryContext(ctx, `SELECT alias FROM graph_aliases WHERE node_id = ? ORDER BY alias`, nodeID)
	if err != nil {
		return "", fmt.Errorf("load graph aliases: %w", err)
	}
	defer rows.Close()
	values := []string{}
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			return "", fmt.Errorf("scan graph alias: %w", err)
		}
		values = append(values, value)
	}
	return strings.Join(values, " "), rows.Err()
}
