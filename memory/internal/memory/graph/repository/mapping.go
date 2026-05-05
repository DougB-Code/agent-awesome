package repository

import (
	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
)

// toGraphScope maps memory scope vocabulary onto graph scope vocabulary.
func toGraphScope(scope domain.Scope) graph.Scope {
	return graph.Scope(scope)
}

// fromGraphScope maps graph scope vocabulary onto memory scope vocabulary.
func fromGraphScope(scope graph.Scope) domain.Scope {
	return domain.Scope(scope)
}

// toGraphSensitivity maps memory sensitivity vocabulary onto graph sensitivity vocabulary.
func toGraphSensitivity(sensitivity domain.Sensitivity) graph.Sensitivity {
	return graph.Sensitivity(sensitivity)
}

// fromGraphSensitivity maps graph sensitivity vocabulary onto memory sensitivity vocabulary.
func fromGraphSensitivity(sensitivity graph.Sensitivity) domain.Sensitivity {
	return domain.Sensitivity(sensitivity)
}

// toGraphSensitivities maps a memory sensitivity list onto graph vocabulary.
func toGraphSensitivities(values []domain.Sensitivity) []graph.Sensitivity {
	mapped := make([]graph.Sensitivity, 0, len(values))
	for _, value := range values {
		mapped = append(mapped, toGraphSensitivity(value))
	}
	return mapped
}

// toGraphTrust maps memory trust vocabulary onto graph trust vocabulary.
func toGraphTrust(trust domain.TrustLevel) graph.TrustLevel {
	return graph.TrustLevel(trust)
}

// fromGraphTrust maps graph trust vocabulary onto memory trust vocabulary.
func fromGraphTrust(trust graph.TrustLevel) domain.TrustLevel {
	return domain.TrustLevel(trust)
}

// toGraphStatus maps memory lifecycle vocabulary onto graph lifecycle vocabulary.
func toGraphStatus(status domain.Status) graph.LifecycleStatus {
	return graph.LifecycleStatus(status)
}

// fromGraphStatus maps graph lifecycle vocabulary onto memory lifecycle vocabulary.
func fromGraphStatus(status graph.LifecycleStatus) domain.Status {
	if status == graph.StatusDeleted {
		return domain.StatusArchived
	}
	return domain.Status(status)
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
