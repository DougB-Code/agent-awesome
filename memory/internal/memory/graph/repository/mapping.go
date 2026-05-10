package repository

import (
	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
)

// fromGraphStatus maps graph-only lifecycle states onto memory lifecycle states.
func fromGraphStatus(status graph.LifecycleStatus) domain.Status {
	if status == graph.StatusDeleted {
		return domain.StatusArchived
	}
	return status
}

// fromGraphRelationship maps graph relation vocabulary onto memory relationship vocabulary.
func fromGraphRelationship(relation graph.RelationType) domain.RelationshipType {
	switch relation {
	case graph.RelationContradicts:
		return domain.RelationshipContradicts
	case graph.RelationRefersTo:
		return domain.RelationshipRefersTo
	case graph.RelationSupersedes:
		return domain.RelationshipSupersedes
	default:
		return domain.RelationshipRefersTo
	}
}
