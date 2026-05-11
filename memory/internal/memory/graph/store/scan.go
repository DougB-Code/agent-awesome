// This file converts SQL rows into graph domain records.
package store

import (
	"fmt"

	graph "memory/internal/memory/graph/domain"
)

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
