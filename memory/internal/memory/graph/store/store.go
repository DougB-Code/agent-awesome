package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	graph "agent-awesome.com/memoryinternal/agent-awesome.com/memorygraph/domain"
	"agent-awesome.com/memoryinternal/agent-awesome.com/memoryid"

	_ "modernc.org/sqlite"
)

// Config contains filesystem and SQLite settings for the graph store.
type Config struct {
	DBPath   string
	DataRoot string
}

// Store owns SQLite graph metadata and filesystem evidence blobs.
type Store struct {
	db       *sql.DB
	dataRoot string
	now      func() time.Time
}

// Open creates a graph store and applies SQLite schema.
func Open(ctx context.Context, cfg Config) (*Store, error) {
	if strings.TrimSpace(cfg.DBPath) == "" {
		cfg.DBPath = "context_graph.db"
	}
	if strings.TrimSpace(cfg.DataRoot) == "" {
		cfg.DataRoot = "data"
	}
	if err := os.MkdirAll(filepath.Join(cfg.DataRoot, "evidence"), 0o700); err != nil {
		return nil, fmt.Errorf("create graph evidence directory: %w", err)
	}
	db, err := sql.Open("sqlite", cfg.DBPath)
	if err != nil {
		return nil, fmt.Errorf("open graph sqlite: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	store := &Store{db: db, dataRoot: cfg.DataRoot, now: func() time.Time { return time.Now().UTC() }}
	if err := store.configure(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.ExecContext(ctx, schemaSQL); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("apply graph schema: %w", err)
	}
	return store, nil
}

// Close releases SQLite resources.
func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

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
		if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_nodes
			(id, kind, stable_key, title, summary, status, scope, sensitivity, trust_level, confidence, source_node_id, actor, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			nodeID, req.Kind, nullableString(req.StableKey), req.Title, req.Summary, req.Status, req.Scope, req.Sensitivity, req.TrustLevel, req.Confidence, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
			return graph.Node{}, fmt.Errorf("insert graph node: %w", err)
		}
		return s.GetNode(ctx, nodeID)
	}
	result, err := s.db.ExecContext(ctx, `UPDATE graph_nodes
		SET kind = ?, stable_key = ?, title = ?, summary = ?, status = ?, scope = ?, sensitivity = ?, trust_level = ?, confidence = ?, source_node_id = ?, actor = ?, updated_at = ?
		WHERE id = ?`,
		req.Kind, nullableString(req.StableKey), req.Title, req.Summary, req.Status, req.Scope, req.Sensitivity, req.TrustLevel, req.Confidence, nullableNodeID(req.SourceNodeID), req.Actor, timeString(now), nodeID)
	if err != nil {
		return graph.Node{}, fmt.Errorf("update graph node: %w", err)
	}
	if rows, err := result.RowsAffected(); err != nil {
		return graph.Node{}, fmt.Errorf("update graph node rows: %w", err)
	} else if rows == 0 {
		stamp := timeString(now)
		if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_nodes
			(id, kind, stable_key, title, summary, status, scope, sensitivity, trust_level, confidence, source_node_id, actor, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			nodeID, req.Kind, nullableString(req.StableKey), req.Title, req.Summary, req.Status, req.Scope, req.Sensitivity, req.TrustLevel, req.Confidence, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
			return graph.Node{}, fmt.Errorf("insert graph node with id: %w", err)
		}
	}
	return s.GetNode(ctx, nodeID)
}

// GetNode loads one graph node by id.
func (s *Store) GetNode(ctx context.Context, nodeID graph.NodeID) (graph.Node, error) {
	var node graph.Node
	var sourceNodeID, stableKey, createdAt, updatedAt string
	row := s.db.QueryRowContext(ctx, `SELECT id, kind, COALESCE(stable_key, ''), title, summary, status, scope, sensitivity, trust_level, confidence, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_nodes WHERE id = ?`, nodeID)
	if err := row.Scan(&node.ID, &node.Kind, &stableKey, &node.Title, &node.Summary, &node.Status, &node.Scope, &node.Sensitivity, &node.TrustLevel, &node.Confidence, &sourceNodeID, &node.Actor, &createdAt, &updatedAt); err != nil {
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
	actor = defaultString(actor, "agent")
	result, err := s.db.ExecContext(ctx, `UPDATE graph_nodes SET status = ?, actor = ?, updated_at = ? WHERE id = ?`, status, actor, timeString(s.now()), nodeID)
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
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM graph_nodes WHERE kind = ?`+statusClause, args...).Scan(&count); err != nil {
		return 0, fmt.Errorf("count graph nodes: %w", err)
	}
	return count, nil
}

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
		if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_edges
			(id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, source_node_id, actor, valid_from, valid_to, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			edgeID, req.FromNodeID, req.Type, req.ToNodeID, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, nullableTime(req.ValidFrom), nullableTime(req.ValidTo), stamp, stamp); err != nil {
			return graph.Edge{}, fmt.Errorf("insert graph edge: %w", err)
		}
		return s.GetEdge(ctx, edgeID)
	}
	result, err := s.db.ExecContext(ctx, `UPDATE graph_edges
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
		if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_edges
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
	actor = defaultString(actor, "agent")
	result, err := s.db.ExecContext(ctx, `UPDATE graph_edges SET status = ?, actor = ?, updated_at = ? WHERE id = ?`, status, actor, timeString(s.now()), edgeID)
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
	row := s.db.QueryRowContext(ctx, `SELECT id, from_node_id, relation_type, to_node_id, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, COALESCE(valid_from, ''), COALESCE(valid_to, ''), created_at, updated_at FROM graph_edges WHERE id = ?`, edgeID)
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
	rows, err := s.db.QueryContext(ctx, query, args...)
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
	row := s.db.QueryRowContext(ctx, `SELECT id, node_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_properties WHERE id = ?`, propertyID)
	return scanNodeProperty(row)
}

// ListNodeProperties returns active properties attached to one node.
func (s *Store) ListNodeProperties(ctx context.Context, nodeID graph.NodeID) ([]graph.NodeProperty, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, node_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_properties WHERE node_id = ? AND status = ? ORDER BY property_key, position, id`, nodeID, graph.StatusActive)
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
	row := s.db.QueryRowContext(ctx, `SELECT id, edge_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_edge_properties WHERE id = ?`, propertyID)
	return scanEdgeProperty(row)
}

// ListEdgeProperties returns active properties attached to one edge.
func (s *Store) ListEdgeProperties(ctx context.Context, edgeID graph.EdgeID) ([]graph.EdgeProperty, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, edge_id, property_key, value_type, value_text, COALESCE(value_number, 0), COALESCE(value_time, ''), value_json, position, status, confidence, trust_level, COALESCE(source_node_id, ''), actor, created_at, updated_at FROM graph_edge_properties WHERE edge_id = ? AND status = ? ORDER BY property_key, position, id`, edgeID, graph.StatusActive)
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

// UpsertAlias creates or updates one node alias.
func (s *Store) UpsertAlias(ctx context.Context, req graph.UpsertAliasRequest) (graph.Alias, error) {
	req, err := graph.NormalizeUpsertAliasRequest(req)
	if err != nil {
		return graph.Alias{}, err
	}
	stamp := timeString(s.now())
	if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_aliases (node_id, locale, alias, alias_kind, created_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(node_id, locale, alias) DO UPDATE SET alias_kind = excluded.alias_kind`,
		req.NodeID, req.Locale, req.Alias, req.Kind, stamp); err != nil {
		return graph.Alias{}, fmt.Errorf("upsert graph alias: %w", err)
	}
	return graph.Alias{NodeID: req.NodeID, Locale: req.Locale, Alias: req.Alias, Kind: req.Kind, CreatedAt: s.now()}, nil
}

// WriteEvidenceBlob writes source content for an evidence node.
func (s *Store) WriteEvidenceBlob(ctx context.Context, req graph.WriteEvidenceBlobRequest) (graph.EvidenceBlob, error) {
	req, err := graph.NormalizeWriteEvidenceBlobRequest(req)
	if err != nil {
		return graph.EvidenceBlob{}, err
	}
	checksum, relPath, size, err := s.writeEvidenceFile(req.NodeID, req.Content)
	if err != nil {
		return graph.EvidenceBlob{}, err
	}
	now := s.now()
	_, hadExisting, lookupErr := s.evidenceBlobExists(ctx, req.NodeID)
	if lookupErr != nil {
		_ = s.removeEvidenceFile(relPath)
		return graph.EvidenceBlob{}, lookupErr
	}
	if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_evidence_blobs
		(node_id, checksum, path, media_type, source_system, source_id, size_bytes, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(node_id) DO UPDATE SET checksum = excluded.checksum, path = excluded.path, media_type = excluded.media_type, source_system = excluded.source_system, source_id = excluded.source_id, size_bytes = excluded.size_bytes`,
		req.NodeID, checksum, relPath, req.MediaType, req.SourceSystem, req.SourceID, size, timeString(now)); err != nil {
		if !hadExisting {
			_ = s.removeEvidenceFile(relPath)
		}
		return graph.EvidenceBlob{}, fmt.Errorf("write graph evidence blob: %w", err)
	}
	if _, err := s.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "write_evidence_blob",
		Actor:         req.Actor,
		SubjectNodeID: req.NodeID,
		SourceNodeID:  req.SourceNodeID,
		Message:       "wrote graph evidence content",
		DetailsJSON:   evidenceBlobAuditDetails(req, checksum, size),
	}); err != nil {
		return graph.EvidenceBlob{}, err
	}
	return s.GetEvidenceBlob(ctx, req.NodeID)
}

// evidenceBlobAuditDetails serializes evidence write metadata for auditing.
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
	if err := s.db.QueryRowContext(ctx, `SELECT node_id, checksum, path, media_type, source_system, source_id, size_bytes, created_at FROM graph_evidence_blobs WHERE node_id = ?`, nodeID).
		Scan(&blob.NodeID, &blob.Checksum, &blob.Path, &blob.MediaType, &blob.SourceSystem, &blob.SourceID, &blob.SizeBytes, &createdAt); err != nil {
		return graph.EvidenceBlob{}, fmt.Errorf("load graph evidence blob: %w", err)
	}
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.EvidenceBlob{}, err
	}
	blob.CreatedAt = created
	return blob, nil
}

// ReadEvidenceBlobContent reads evidence content from disk.
func (s *Store) ReadEvidenceBlobContent(ctx context.Context, nodeID graph.NodeID) (string, error) {
	blob, err := s.GetEvidenceBlob(ctx, nodeID)
	if err != nil {
		return "", err
	}
	bytes, err := os.ReadFile(s.safePath(blob.Path))
	if err != nil {
		return "", fmt.Errorf("read graph evidence file: %w", err)
	}
	return string(bytes), nil
}

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
	if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_audit_events
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
	rows, err := s.db.QueryContext(ctx, `SELECT id, event_kind, actor, COALESCE(subject_node_id, ''), COALESCE(subject_edge_id, ''), COALESCE(source_node_id, ''), message, details_json, created_at FROM graph_audit_events ORDER BY created_at DESC, id DESC LIMIT ?`, limit)
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
	if _, err := s.db.ExecContext(ctx, `DELETE FROM graph_text_fts WHERE node_id = ?`, nodeID); err != nil {
		return fmt.Errorf("delete graph fts row: %w", err)
	}
	if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_text_fts (node_id, title, summary, aliases, properties, evidence_text) VALUES (?, ?, ?, ?, ?, ?)`,
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
	rows, err := s.db.QueryContext(ctx, query, args...)
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

// configure applies SQLite pragmas needed for concurrent local service use.
func (s *Store) configure(ctx context.Context) error {
	pragmas := []string{
		"PRAGMA journal_mode = WAL",
		"PRAGMA busy_timeout = 5000",
		"PRAGMA foreign_keys = ON",
		"PRAGMA synchronous = NORMAL",
	}
	for _, pragma := range pragmas {
		if _, err := s.db.ExecContext(ctx, pragma); err != nil {
			return fmt.Errorf("configure graph sqlite %q: %w", pragma, err)
		}
	}
	return nil
}

// nodeIDByStableKey returns an existing node id by kind and stable key.
func (s *Store) nodeIDByStableKey(ctx context.Context, kind graph.NodeKind, stableKey string) (graph.NodeID, bool, error) {
	var value string
	err := s.db.QueryRowContext(ctx, `SELECT id FROM graph_nodes WHERE kind = ? AND stable_key = ?`, kind, stableKey).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph node stable key: %w", err)
	}
	return graph.NodeID(value), true, nil
}

// edgeIDByIdentity returns an existing edge id by semantic identity.
func (s *Store) edgeIDByIdentity(ctx context.Context, from graph.NodeID, relation graph.RelationType, to graph.NodeID, source graph.NodeID) (graph.EdgeID, bool, error) {
	var value string
	sourceValue := string(source)
	err := s.db.QueryRowContext(ctx, `SELECT id FROM graph_edges
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

// nodePropertyIDByIdentity returns an existing node property by semantic identity.
func (s *Store) nodePropertyIDByIdentity(ctx context.Context, nodeID graph.NodeID, key string, position int, source graph.NodeID) (graph.PropertyID, bool, error) {
	var value string
	sourceValue := string(source)
	err := s.db.QueryRowContext(ctx, `SELECT id FROM graph_properties
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
	err := s.db.QueryRowContext(ctx, `SELECT id FROM graph_edge_properties
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

// evidenceBlobExists reports whether an evidence blob row already exists.
func (s *Store) evidenceBlobExists(ctx context.Context, nodeID graph.NodeID) (string, bool, error) {
	var path string
	err := s.db.QueryRowContext(ctx, `SELECT path FROM graph_evidence_blobs WHERE node_id = ?`, nodeID).Scan(&path)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("lookup graph evidence blob: %w", err)
	}
	return path, true, nil
}

// insertNodeProperty stores a new node property.
func (s *Store) insertNodeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertNodePropertyRequest) error {
	now := s.now()
	stamp := timeString(now)
	if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_properties
		(id, node_id, property_key, value_type, value_text, value_number, value_time, value_json, position, status, confidence, trust_level, source_node_id, actor, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		propertyID, req.NodeID, req.Key, req.Value.Type, req.Value.Text, nullableNumber(req.Value), nullableValueTime(req.Value), req.Value.JSON, req.Position, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
		return fmt.Errorf("insert graph node property: %w", err)
	}
	return nil
}

// updateNodeProperty updates an existing node property.
func (s *Store) updateNodeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertNodePropertyRequest) error {
	result, err := s.db.ExecContext(ctx, `UPDATE graph_properties
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
	if _, err := s.db.ExecContext(ctx, `INSERT INTO graph_edge_properties
		(id, edge_id, property_key, value_type, value_text, value_number, value_time, value_json, position, status, confidence, trust_level, source_node_id, actor, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		propertyID, req.EdgeID, req.Key, req.Value.Type, req.Value.Text, nullableNumber(req.Value), nullableValueTime(req.Value), req.Value.JSON, req.Position, req.Status, req.Confidence, req.TrustLevel, nullableNodeID(req.SourceNodeID), req.Actor, stamp, stamp); err != nil {
		return fmt.Errorf("insert graph edge property: %w", err)
	}
	return nil
}

// updateEdgeProperty updates an existing edge property.
func (s *Store) updateEdgeProperty(ctx context.Context, propertyID graph.PropertyID, req graph.UpsertEdgePropertyRequest) error {
	result, err := s.db.ExecContext(ctx, `UPDATE graph_edge_properties
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
	rows, err := s.db.QueryContext(ctx, query, args...)
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

// aliasText returns space-joined aliases for FTS indexing.
func (s *Store) aliasText(ctx context.Context, nodeID graph.NodeID) (string, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT alias FROM graph_aliases WHERE node_id = ? ORDER BY alias`, nodeID)
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

// evidenceText returns evidence content for FTS indexing when present.
func (s *Store) evidenceText(ctx context.Context, nodeID graph.NodeID) (string, error) {
	content, err := s.ReadEvidenceBlobContent(ctx, nodeID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return content, err
}

// writeEvidenceFile writes content to a stable evidence path.
func (s *Store) writeEvidenceFile(nodeID graph.NodeID, content string) (string, string, int64, error) {
	bytes := []byte(content)
	sum := sha256.Sum256(bytes)
	checksum := fmt.Sprintf("%x", sum[:])
	relPath := filepath.Join("evidence", string(nodeID)+".txt")
	fullPath := s.safePath(relPath)
	tmpPath := fullPath + ".tmp"
	if err := os.WriteFile(tmpPath, bytes, 0o600); err != nil {
		return "", "", 0, fmt.Errorf("write graph evidence temp file: %w", err)
	}
	if err := os.Rename(tmpPath, fullPath); err != nil {
		_ = os.Remove(tmpPath)
		return "", "", 0, fmt.Errorf("commit graph evidence file: %w", err)
	}
	return checksum, relPath, int64(len(bytes)), nil
}

// removeEvidenceFile deletes a partially committed evidence file.
func (s *Store) removeEvidenceFile(relPath string) error {
	return os.Remove(s.safePath(relPath))
}

// safePath constrains stored relative paths under the data root.
func (s *Store) safePath(relPath string) string {
	clean := filepath.Clean(string(filepath.Separator) + relPath)
	clean = strings.TrimLeft(clean, string(filepath.Separator))
	return filepath.Join(s.dataRoot, clean)
}

// scanEdge scans a graph edge from a row-like value.
func scanEdge(scanner interface{ Scan(dest ...any) error }) (graph.Edge, error) {
	var edge graph.Edge
	var sourceNodeID, validFrom, validTo, createdAt, updatedAt string
	if err := scanner.Scan(&edge.ID, &edge.FromNodeID, &edge.Type, &edge.ToNodeID, &edge.Status, &edge.Confidence, &edge.TrustLevel, &sourceNodeID, &edge.Actor, &validFrom, &validTo, &createdAt, &updatedAt); err != nil {
		return graph.Edge{}, fmt.Errorf("scan graph edge: %w", err)
	}
	edge.SourceNodeID = graph.NodeID(sourceNodeID)
	if validFrom != "" {
		parsed, err := parseTime(validFrom)
		if err != nil {
			return graph.Edge{}, err
		}
		edge.ValidFrom = &parsed
	}
	if validTo != "" {
		parsed, err := parseTime(validTo)
		if err != nil {
			return graph.Edge{}, err
		}
		edge.ValidTo = &parsed
	}
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.Edge{}, err
	}
	updated, err := parseTime(updatedAt)
	if err != nil {
		return graph.Edge{}, err
	}
	edge.CreatedAt = created
	edge.UpdatedAt = updated
	return edge, nil
}

// scanNodeProperty scans a node property from a row-like value.
func scanNodeProperty(scanner interface{ Scan(dest ...any) error }) (graph.NodeProperty, error) {
	var property graph.NodeProperty
	var sourceNodeID, valueTime, createdAt, updatedAt string
	if err := scanner.Scan(&property.ID, &property.NodeID, &property.Key, &property.Value.Type, &property.Value.Text, &property.Value.Number, &valueTime, &property.Value.JSON, &property.Position, &property.Status, &property.Confidence, &property.TrustLevel, &sourceNodeID, &property.Actor, &createdAt, &updatedAt); err != nil {
		return graph.NodeProperty{}, fmt.Errorf("scan graph node property: %w", err)
	}
	property.SourceNodeID = graph.NodeID(sourceNodeID)
	if valueTime != "" {
		parsed, err := parseTime(valueTime)
		if err != nil {
			return graph.NodeProperty{}, err
		}
		property.Value.Time = &parsed
	}
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.NodeProperty{}, err
	}
	updated, err := parseTime(updatedAt)
	if err != nil {
		return graph.NodeProperty{}, err
	}
	property.CreatedAt = created
	property.UpdatedAt = updated
	return property, nil
}

// scanEdgeProperty scans an edge property from a row-like value.
func scanEdgeProperty(scanner interface{ Scan(dest ...any) error }) (graph.EdgeProperty, error) {
	var property graph.EdgeProperty
	var sourceNodeID, valueTime, createdAt, updatedAt string
	if err := scanner.Scan(&property.ID, &property.EdgeID, &property.Key, &property.Value.Type, &property.Value.Text, &property.Value.Number, &valueTime, &property.Value.JSON, &property.Position, &property.Status, &property.Confidence, &property.TrustLevel, &sourceNodeID, &property.Actor, &createdAt, &updatedAt); err != nil {
		return graph.EdgeProperty{}, fmt.Errorf("scan graph edge property: %w", err)
	}
	property.SourceNodeID = graph.NodeID(sourceNodeID)
	if valueTime != "" {
		parsed, err := parseTime(valueTime)
		if err != nil {
			return graph.EdgeProperty{}, err
		}
		property.Value.Time = &parsed
	}
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.EdgeProperty{}, err
	}
	updated, err := parseTime(updatedAt)
	if err != nil {
		return graph.EdgeProperty{}, err
	}
	property.CreatedAt = created
	property.UpdatedAt = updated
	return property, nil
}

// scanAuditEvent scans one append-only graph audit event.
func scanAuditEvent(scanner interface{ Scan(dest ...any) error }) (graph.AuditEvent, error) {
	var event graph.AuditEvent
	var subjectNodeID, subjectEdgeID, sourceNodeID, createdAt string
	if err := scanner.Scan(&event.ID, &event.Kind, &event.Actor, &subjectNodeID, &subjectEdgeID, &sourceNodeID, &event.Message, &event.DetailsJSON, &createdAt); err != nil {
		return graph.AuditEvent{}, fmt.Errorf("scan graph audit event: %w", err)
	}
	event.SubjectNodeID = graph.NodeID(subjectNodeID)
	event.SubjectEdgeID = graph.EdgeID(subjectEdgeID)
	event.SourceNodeID = graph.NodeID(sourceNodeID)
	created, err := parseTime(createdAt)
	if err != nil {
		return graph.AuditEvent{}, err
	}
	event.CreatedAt = created
	return event, nil
}

// nullableNodeID converts blank node ids to nil for SQL nullable columns.
func nullableNodeID(value graph.NodeID) any {
	if value == "" {
		return nil
	}
	return value
}

// nullableEdgeID converts blank edge ids to nil for SQL nullable columns.
func nullableEdgeID(value graph.EdgeID) any {
	if value == "" {
		return nil
	}
	return value
}

// nullableString converts blank strings to nil for SQL nullable columns.
func nullableString(value string) any {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return value
}

// nullableTime converts nil times to nil SQL values.
func nullableTime(value *time.Time) any {
	if value == nil || value.IsZero() {
		return nil
	}
	return timeString(*value)
}

// nullableNumber converts non-number values to nil for SQL nullable columns.
func nullableNumber(value graph.Value) any {
	if value.Type != graph.ValueNumber {
		return nil
	}
	return value.Number
}

// nullableValueTime converts non-time values to nil for SQL nullable columns.
func nullableValueTime(value graph.Value) any {
	if value.Type != graph.ValueTime || value.Time == nil {
		return nil
	}
	return timeString(*value.Time)
}

// valueText returns a searchable string for any typed value.
func valueText(value graph.Value) string {
	switch value.Type {
	case graph.ValueBool, graph.ValueText:
		return value.Text
	case graph.ValueJSON:
		return value.JSON
	case graph.ValueNumber:
		return fmt.Sprintf("%g", value.Number)
	case graph.ValueTime:
		if value.Time == nil {
			return ""
		}
		return timeString(*value.Time)
	default:
		return ""
	}
}

// inClause returns a SQL IN clause placeholder list.
func inClause(column string, count int) string {
	placeholders := make([]string, count)
	for i := range placeholders {
		placeholders[i] = "?"
	}
	return fmt.Sprintf("%s IN (%s)", column, strings.Join(placeholders, ","))
}

// ftsQuery converts user text into a conservative FTS expression.
func ftsQuery(text string) string {
	parts := strings.Fields(strings.ToLower(text))
	terms := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.Trim(part, `"'()[]{}:;,.!?`)
		if part != "" {
			terms = append(terms, fmt.Sprintf("%q", part))
		}
	}
	if len(terms) == 0 {
		return `""`
	}
	return strings.Join(terms, " OR ")
}

// timeString formats times consistently for SQLite text ordering.
func timeString(value time.Time) string {
	return value.UTC().Format(time.RFC3339Nano)
}

// parseTime parses SQLite time strings.
func parseTime(value string) (time.Time, error) {
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return time.Time{}, fmt.Errorf("parse graph time %q: %w", value, err)
	}
	return parsed, nil
}

// defaultString trims a value and substitutes a fallback when blank.
func defaultString(value string, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback
	}
	return value
}

// newNodeID creates a graph node identifier.
func newNodeID() (graph.NodeID, error) {
	value, err := id.New("node")
	return graph.NodeID(value), err
}

// newEdgeID creates a graph edge identifier.
func newEdgeID() (graph.EdgeID, error) {
	value, err := id.New("edge")
	return graph.EdgeID(value), err
}

// newPropertyID creates a graph property identifier.
func newPropertyID() (graph.PropertyID, error) {
	value, err := id.New("prop")
	return graph.PropertyID(value), err
}

// newAuditID creates a graph audit identifier.
func newAuditID() (graph.AuditID, error) {
	value, err := id.New("audit")
	return graph.AuditID(value), err
}
