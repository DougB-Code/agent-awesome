package domain

import (
	"time"

	"memory/internal/memory/vocabulary"
)

// NodeID identifies one durable graph node.
type NodeID string

// EdgeID identifies one directed graph edge.
type EdgeID string

// PropertyID identifies one graph property row.
type PropertyID string

// AuditID identifies one graph audit event.
type AuditID string

// NodeKind classifies a graph node's durable semantic role.
type NodeKind string

const (
	// KindArtifact represents a generated or imported artifact.
	KindArtifact NodeKind = "artifact"
	// KindCodebase represents a durable repository catalog entry.
	KindCodebase NodeKind = "codebase"
	// KindEvidence represents source-backed content.
	KindEvidence NodeKind = "evidence"
	// KindEntity represents a generic named entity.
	KindEntity NodeKind = "entity"
	// KindEvent represents a dated event or timeline point.
	KindEvent NodeKind = "event"
	// KindList represents a named collection.
	KindList NodeKind = "list"
	// KindLocation represents a place or location requirement.
	KindLocation NodeKind = "location"
	// KindMemory represents a durable memory fact or note.
	KindMemory NodeKind = "memory"
	// KindPerson represents a person or actor.
	KindPerson NodeKind = "person"
	// KindProject represents a project or initiative.
	KindProject NodeKind = "project"
	// KindRequirement represents a requirement or acceptance constraint.
	KindRequirement NodeKind = "requirement"
	// KindRisk represents a risk, issue, or materialized problem.
	KindRisk NodeKind = "risk"
	// KindSource represents an external system or origin.
	KindSource NodeKind = "source"
	// KindTask represents operational work.
	KindTask NodeKind = "task"
	// KindTopic represents a topic or tag.
	KindTopic NodeKind = "topic"
)

// RelationType classifies a directed graph edge.
type RelationType string

const (
	// RelationAbout links context to the thing it describes.
	RelationAbout RelationType = "about"
	// RelationAssignedTo links work to a responsible person.
	RelationAssignedTo RelationType = "assigned_to"
	// RelationBlocks means the source prevents the target from progressing.
	RelationBlocks RelationType = "blocks"
	// RelationCapturedFrom links a memory node to source content.
	RelationCapturedFrom RelationType = "captured_from"
	// RelationContradicts links conflicting facts.
	RelationContradicts RelationType = "contradicts"
	// RelationDependsOn means the source depends on the target.
	RelationDependsOn RelationType = "depends_on"
	// RelationDerivedFrom links derived facts to source facts.
	RelationDerivedFrom RelationType = "derived_from"
	// RelationEnables means the source creates upside for the target.
	RelationEnables RelationType = "enables"
	// RelationHasRisk links work or projects to risk nodes.
	RelationHasRisk RelationType = "has_risk"
	// RelationHasContext links work to contextual memory.
	RelationHasContext RelationType = "has_context"
	// RelationLocatedAt links work to a location node.
	RelationLocatedAt RelationType = "located_at"
	// RelationMaterializedAs links a risk to the problem it became.
	RelationMaterializedAs RelationType = "materialized_as"
	// RelationMentions links context to a referenced entity.
	RelationMentions RelationType = "mentions"
	// RelationPartOf links a child node to a parent grouping.
	RelationPartOf RelationType = "part_of"
	// RelationRelatedTo links generally related graph objects.
	RelationRelatedTo RelationType = "related_to"
	// RelationRefersTo links context to another referenced graph object.
	RelationRefersTo RelationType = "refers_to"
	// RelationSourcedFrom links a fact to an origin node.
	RelationSourcedFrom RelationType = "sourced_from"
	// RelationSupportedBy links work to supporting memory.
	RelationSupportedBy RelationType = "supported_by"
	// RelationSupersedes links a newer fact to an older fact.
	RelationSupersedes RelationType = "supersedes"
	// RelationTaggedWith links a node to a topic node.
	RelationTaggedWith RelationType = "tagged_with"
)

// LifecycleStatus describes whether graph facts are active or retained history.
type LifecycleStatus = vocabulary.LifecycleStatus

const (
	// StatusActive marks current graph facts.
	StatusActive = vocabulary.StatusActive
	// StatusArchived marks retained but inactive graph facts.
	StatusArchived = vocabulary.StatusArchived
	// StatusDeleted marks lifecycle-deleted graph facts.
	StatusDeleted = vocabulary.StatusDeleted
	// StatusDeprecated marks discouraged graph facts that remain auditable.
	StatusDeprecated = vocabulary.StatusDeprecated
	// StatusSuperseded marks graph facts replaced by newer facts.
	StatusSuperseded = vocabulary.StatusSuperseded
)

// Sensitivity controls whether a caller may see a graph fact.
type Sensitivity = vocabulary.Sensitivity

const (
	// SensitivityInternal is visible inside the configured boundary.
	SensitivityInternal = vocabulary.SensitivityInternal
	// SensitivityPrivate is visible to the owning user or household.
	SensitivityPrivate = vocabulary.SensitivityPrivate
	// SensitivityPublic is safe for broad disclosure.
	SensitivityPublic = vocabulary.SensitivityPublic
	// SensitivityRestricted requires an explicit request grant.
	SensitivityRestricted = vocabulary.SensitivityRestricted
)

// DefaultActor is the graph actor used when a caller does not identify itself.
const DefaultActor = vocabulary.DefaultAgentActor

// TrustLevel describes where a graph fact came from.
type TrustLevel = vocabulary.TrustLevel

const (
	// TrustExternallyVerified marks facts checked against an external source.
	TrustExternallyVerified = vocabulary.TrustExternallyVerified
	// TrustModelExtracted marks model-extracted fields.
	TrustModelExtracted = vocabulary.TrustModelExtracted
	// TrustModelSynthesized marks model-written summaries or pages.
	TrustModelSynthesized = vocabulary.TrustModelSynthesized
	// TrustSourceOriginal marks verbatim source artifacts.
	TrustSourceOriginal = vocabulary.TrustSourceOriginal
	// TrustUserAsserted marks user-supplied claims.
	TrustUserAsserted = vocabulary.TrustUserAsserted
)

// ValueType describes which typed property value column is authoritative.
type ValueType string

const (
	// ValueBool stores a boolean in the text column as true or false.
	ValueBool ValueType = "bool"
	// ValueJSON stores structured JSON in the JSON column.
	ValueJSON ValueType = "json"
	// ValueNumber stores a numeric value in the number column.
	ValueNumber ValueType = "number"
	// ValueText stores a string value in the text column.
	ValueText ValueType = "text"
	// ValueTime stores an RFC3339Nano timestamp in the time column.
	ValueTime ValueType = "time"
)

// Node stores canonical identity and lifecycle metadata for a graph node.
type Node struct {
	ID           NodeID          `json:"id"`
	Kind         NodeKind        `json:"kind"`
	StableKey    string          `json:"stable_key,omitempty"`
	Title        string          `json:"title,omitempty"`
	Summary      string          `json:"summary,omitempty"`
	Status       LifecycleStatus `json:"status"`
	Sensitivity  Sensitivity     `json:"sensitivity"`
	TrustLevel   TrustLevel      `json:"trust_level"`
	Confidence   float64         `json:"confidence"`
	SourceNodeID NodeID          `json:"source_node_id,omitempty"`
	Actor        string          `json:"actor,omitempty"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

// Edge stores one directed relationship between graph nodes.
type Edge struct {
	ID           EdgeID          `json:"id"`
	FromNodeID   NodeID          `json:"from_node_id"`
	Type         RelationType    `json:"type"`
	ToNodeID     NodeID          `json:"to_node_id"`
	Status       LifecycleStatus `json:"status"`
	Confidence   float64         `json:"confidence"`
	TrustLevel   TrustLevel      `json:"trust_level"`
	SourceNodeID NodeID          `json:"source_node_id,omitempty"`
	Actor        string          `json:"actor,omitempty"`
	ValidFrom    *time.Time      `json:"valid_from,omitempty"`
	ValidTo      *time.Time      `json:"valid_to,omitempty"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

// Value stores one typed graph property value.
type Value struct {
	Type   ValueType  `json:"type"`
	Text   string     `json:"text,omitempty"`
	Number float64    `json:"number,omitempty"`
	Time   *time.Time `json:"time,omitempty"`
	JSON   string     `json:"json,omitempty"`
}

// NodeProperty stores a typed fact attached to a node.
type NodeProperty struct {
	ID           PropertyID      `json:"id"`
	NodeID       NodeID          `json:"node_id"`
	Key          string          `json:"key"`
	Value        Value           `json:"value"`
	Position     int             `json:"position"`
	Status       LifecycleStatus `json:"status"`
	Confidence   float64         `json:"confidence"`
	TrustLevel   TrustLevel      `json:"trust_level"`
	SourceNodeID NodeID          `json:"source_node_id,omitempty"`
	Actor        string          `json:"actor,omitempty"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

// EdgeProperty stores a typed fact attached to an edge.
type EdgeProperty struct {
	ID           PropertyID      `json:"id"`
	EdgeID       EdgeID          `json:"edge_id"`
	Key          string          `json:"key"`
	Value        Value           `json:"value"`
	Position     int             `json:"position"`
	Status       LifecycleStatus `json:"status"`
	Confidence   float64         `json:"confidence"`
	TrustLevel   TrustLevel      `json:"trust_level"`
	SourceNodeID NodeID          `json:"source_node_id,omitempty"`
	Actor        string          `json:"actor,omitempty"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
}

// Alias stores one localized lookup label for a graph node.
type Alias struct {
	NodeID    NodeID    `json:"node_id"`
	Locale    string    `json:"locale,omitempty"`
	Alias     string    `json:"alias"`
	Kind      string    `json:"kind"`
	CreatedAt time.Time `json:"created_at"`
}

// EvidenceBlob stores source content metadata for a source node.
type EvidenceBlob struct {
	NodeID       NodeID    `json:"node_id"`
	Checksum     string    `json:"checksum"`
	Path         string    `json:"path"`
	MediaType    string    `json:"media_type"`
	SourceSystem string    `json:"source_system,omitempty"`
	SourceID     string    `json:"source_id,omitempty"`
	SizeBytes    int64     `json:"size_bytes"`
	CreatedAt    time.Time `json:"created_at"`
}

// AuditEvent stores one append-only graph mutation or retrieval record.
type AuditEvent struct {
	ID            AuditID   `json:"id"`
	Kind          string    `json:"kind"`
	Actor         string    `json:"actor,omitempty"`
	SubjectNodeID NodeID    `json:"subject_node_id,omitempty"`
	SubjectEdgeID EdgeID    `json:"subject_edge_id,omitempty"`
	SourceNodeID  NodeID    `json:"source_node_id,omitempty"`
	Message       string    `json:"message,omitempty"`
	DetailsJSON   string    `json:"details_json,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
}

// UpsertNodeRequest asks the repository to create or update one graph node.
type UpsertNodeRequest struct {
	NodeID       NodeID
	Kind         NodeKind
	StableKey    string
	Title        string
	Summary      string
	Status       LifecycleStatus
	Sensitivity  Sensitivity
	TrustLevel   TrustLevel
	Confidence   float64
	SourceNodeID NodeID
	Actor        string
}

// UpsertEdgeRequest asks the repository to create or update one directed edge.
type UpsertEdgeRequest struct {
	EdgeID       EdgeID
	FromNodeID   NodeID
	Type         RelationType
	ToNodeID     NodeID
	Status       LifecycleStatus
	Confidence   float64
	TrustLevel   TrustLevel
	SourceNodeID NodeID
	Actor        string
	ValidFrom    *time.Time
	ValidTo      *time.Time
}

// UpsertNodePropertyRequest asks the repository to create or update a node property.
type UpsertNodePropertyRequest struct {
	PropertyID   PropertyID
	NodeID       NodeID
	Key          string
	Value        Value
	Position     int
	Status       LifecycleStatus
	Confidence   float64
	TrustLevel   TrustLevel
	SourceNodeID NodeID
	Actor        string
}

// UpsertEdgePropertyRequest asks the repository to create or update an edge property.
type UpsertEdgePropertyRequest struct {
	PropertyID   PropertyID
	EdgeID       EdgeID
	Key          string
	Value        Value
	Position     int
	Status       LifecycleStatus
	Confidence   float64
	TrustLevel   TrustLevel
	SourceNodeID NodeID
	Actor        string
}

// UpsertAliasRequest asks the repository to create or update one node alias.
type UpsertAliasRequest struct {
	NodeID NodeID
	Locale string
	Alias  string
	Kind   string
}

// WriteEvidenceBlobRequest asks the repository to persist source text.
type WriteEvidenceBlobRequest struct {
	NodeID       NodeID
	Content      string
	MediaType    string
	SourceSystem string
	SourceID     string
	SourceNodeID NodeID
	Actor        string
}

// AppendAuditRequest asks the repository to append an audit event.
type AppendAuditRequest struct {
	AuditID       AuditID
	Kind          string
	Actor         string
	SubjectNodeID NodeID
	SubjectEdgeID EdgeID
	SourceNodeID  NodeID
	Message       string
	DetailsJSON   string
}

// SearchNodesQuery filters graph lexical search.
type SearchNodesQuery struct {
	Text                 string
	Kinds                []NodeKind
	AllowedSensitivities []Sensitivity
	Limit                int
}

// AccessPolicy stores graph read/write boundary metadata shared by operations.
type AccessPolicy struct {
	Actor                string
	AllowedSensitivities []Sensitivity
}
