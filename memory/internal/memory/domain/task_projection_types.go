package domain

import "time"

// TaskGraphProjectionQuery filters a graph-backed task projection snapshot.
type TaskGraphProjectionQuery struct {
	Tasks         TaskQuery          `json:"tasks,omitempty"`
	RelationTypes []TaskRelationType `json:"relation_types,omitempty"`
	IncludeFacets bool               `json:"include_facets,omitempty"`
}

// TaskGraphProjection stores a client-neutral task graph snapshot.
type TaskGraphProjection struct {
	SchemaVersion string                     `json:"schema_version"`
	GeneratedAt   time.Time                  `json:"generated_at"`
	Tasks         []Task                     `json:"tasks"`
	Relations     []TaskRelation             `json:"relations"`
	Nodes         []TaskGraphProjectionNode  `json:"nodes"`
	Edges         []TaskGraphProjectionEdge  `json:"edges"`
	Facets        []TaskGraphProjectionNode  `json:"facets,omitempty"`
	Quality       TaskGraphProjectionQuality `json:"quality"`
}

// TaskGraphProjectionNode stores one task or facet graph node for UI reads.
type TaskGraphProjectionNode struct {
	ID         string            `json:"id"`
	Kind       string            `json:"kind"`
	Label      string            `json:"label"`
	TaskID     TaskID            `json:"task_id,omitempty"`
	Task       *Task             `json:"task,omitempty"`
	Properties map[string]string `json:"properties,omitempty"`
}

// TaskGraphProjectionEdge stores one projected graph edge.
type TaskGraphProjectionEdge struct {
	ID                 string         `json:"id"`
	FromNodeID         string         `json:"from_node_id"`
	ToNodeID           string         `json:"to_node_id"`
	Type               string         `json:"type"`
	DirectionSemantics string         `json:"direction_semantics,omitempty"`
	RelationID         TaskRelationID `json:"relation_id,omitempty"`
	Relation           *TaskRelation  `json:"relation,omitempty"`
	Confidence         float64        `json:"confidence,omitempty"`
}

// TaskGraphProjectionQuality stores coverage counters for graph consumers.
type TaskGraphProjectionQuality struct {
	TaskCount        int     `json:"task_count"`
	RelationCount    int     `json:"relation_count"`
	FacetCount       int     `json:"facet_count"`
	RelationCoverage float64 `json:"relation_coverage"`
}
