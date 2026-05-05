package store

// schemaSQL creates canonical graph tables for local personal deployments.
const schemaSQL = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS graph_nodes (
	id TEXT PRIMARY KEY,
	kind TEXT NOT NULL,
	stable_key TEXT,
	title TEXT NOT NULL DEFAULT '',
	summary TEXT NOT NULL DEFAULT '',
	status TEXT NOT NULL DEFAULT 'active',
	scope TEXT NOT NULL DEFAULT 'user',
	sensitivity TEXT NOT NULL DEFAULT 'private',
	trust_level TEXT NOT NULL DEFAULT 'user_asserted',
	confidence REAL NOT NULL DEFAULT 1.0,
	source_node_id TEXT REFERENCES graph_nodes(id),
	actor TEXT NOT NULL DEFAULT '',
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS graph_edges (
	id TEXT PRIMARY KEY,
	from_node_id TEXT NOT NULL REFERENCES graph_nodes(id) ON DELETE CASCADE,
	relation_type TEXT NOT NULL,
	to_node_id TEXT NOT NULL REFERENCES graph_nodes(id) ON DELETE CASCADE,
	status TEXT NOT NULL DEFAULT 'active',
	confidence REAL NOT NULL DEFAULT 1.0,
	trust_level TEXT NOT NULL DEFAULT 'user_asserted',
	source_node_id TEXT REFERENCES graph_nodes(id),
	actor TEXT NOT NULL DEFAULT '',
	valid_from TEXT,
	valid_to TEXT,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS graph_properties (
	id TEXT PRIMARY KEY,
	node_id TEXT NOT NULL REFERENCES graph_nodes(id) ON DELETE CASCADE,
	property_key TEXT NOT NULL,
	value_type TEXT NOT NULL,
	value_text TEXT NOT NULL DEFAULT '',
	value_number REAL,
	value_time TEXT,
	value_json TEXT NOT NULL DEFAULT '',
	position INTEGER NOT NULL DEFAULT 0,
	status TEXT NOT NULL DEFAULT 'active',
	confidence REAL NOT NULL DEFAULT 1.0,
	trust_level TEXT NOT NULL DEFAULT 'user_asserted',
	source_node_id TEXT REFERENCES graph_nodes(id),
	actor TEXT NOT NULL DEFAULT '',
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS graph_edge_properties (
	id TEXT PRIMARY KEY,
	edge_id TEXT NOT NULL REFERENCES graph_edges(id) ON DELETE CASCADE,
	property_key TEXT NOT NULL,
	value_type TEXT NOT NULL,
	value_text TEXT NOT NULL DEFAULT '',
	value_number REAL,
	value_time TEXT,
	value_json TEXT NOT NULL DEFAULT '',
	position INTEGER NOT NULL DEFAULT 0,
	status TEXT NOT NULL DEFAULT 'active',
	confidence REAL NOT NULL DEFAULT 1.0,
	trust_level TEXT NOT NULL DEFAULT 'user_asserted',
	source_node_id TEXT REFERENCES graph_nodes(id),
	actor TEXT NOT NULL DEFAULT '',
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS graph_aliases (
	node_id TEXT NOT NULL REFERENCES graph_nodes(id) ON DELETE CASCADE,
	locale TEXT NOT NULL DEFAULT '',
	alias TEXT NOT NULL,
	alias_kind TEXT NOT NULL DEFAULT 'name',
	created_at TEXT NOT NULL,
	PRIMARY KEY (node_id, locale, alias)
);

CREATE TABLE IF NOT EXISTS graph_evidence_blobs (
	node_id TEXT PRIMARY KEY REFERENCES graph_nodes(id) ON DELETE CASCADE,
	checksum TEXT NOT NULL,
	path TEXT NOT NULL UNIQUE,
	media_type TEXT NOT NULL,
	source_system TEXT NOT NULL DEFAULT '',
	source_id TEXT NOT NULL DEFAULT '',
	size_bytes INTEGER NOT NULL DEFAULT 0,
	created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS graph_audit_events (
	id TEXT PRIMARY KEY,
	event_kind TEXT NOT NULL,
	actor TEXT NOT NULL DEFAULT '',
	subject_node_id TEXT REFERENCES graph_nodes(id),
	subject_edge_id TEXT REFERENCES graph_edges(id),
	source_node_id TEXT REFERENCES graph_nodes(id),
	message TEXT NOT NULL DEFAULT '',
	details_json TEXT NOT NULL DEFAULT '',
	created_at TEXT NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS graph_text_fts USING fts5(
	node_id UNINDEXED,
	title,
	summary,
	aliases,
	properties,
	evidence_text,
	tokenize='porter unicode61'
);

CREATE INDEX IF NOT EXISTS idx_graph_nodes_kind_status ON graph_nodes(kind, status);
CREATE INDEX IF NOT EXISTS idx_graph_nodes_scope_sensitivity ON graph_nodes(scope, sensitivity, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_graph_nodes_stable_key ON graph_nodes(kind, stable_key) WHERE stable_key IS NOT NULL AND stable_key != '';
CREATE INDEX IF NOT EXISTS idx_graph_edges_from_type ON graph_edges(from_node_id, relation_type, status);
CREATE INDEX IF NOT EXISTS idx_graph_edges_to_type ON graph_edges(to_node_id, relation_type, status);
CREATE INDEX IF NOT EXISTS idx_graph_edges_relation ON graph_edges(relation_type, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_graph_edges_identity ON graph_edges(from_node_id, relation_type, to_node_id, COALESCE(source_node_id, ''));
CREATE INDEX IF NOT EXISTS idx_graph_properties_key_text ON graph_properties(property_key, value_text, status);
CREATE INDEX IF NOT EXISTS idx_graph_properties_key_number ON graph_properties(property_key, value_number, status);
CREATE INDEX IF NOT EXISTS idx_graph_properties_key_time ON graph_properties(property_key, value_time, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_graph_properties_identity ON graph_properties(node_id, property_key, position, COALESCE(source_node_id, ''));
CREATE UNIQUE INDEX IF NOT EXISTS idx_graph_edge_properties_identity ON graph_edge_properties(edge_id, property_key, position, COALESCE(source_node_id, ''));
CREATE INDEX IF NOT EXISTS idx_graph_aliases_alias ON graph_aliases(alias);
`
