// This file executes graph query mutations and audited property writes.
package query

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	graph "memory/internal/memory/graph/domain"
)

// mutationContext stores required provenance for graph writes.
type mutationContext struct {
	actor  string
	source graph.NodeID
}

// mutationContextFromRequest validates required mutation provenance.
func mutationContextFromRequest(stmt Statement, req Request, rawActor string) (mutationContext, error) {
	if !stmt.Mutating() {
		return mutationContext{}, nil
	}
	if rawActor == "" {
		return mutationContext{}, fmt.Errorf("actor is required for graph mutations")
	}
	if req.SourceNodeID == "" {
		return mutationContext{}, fmt.Errorf("source_node_id is required for graph mutations")
	}
	return mutationContext{actor: req.Actor, source: graph.NodeID(req.SourceNodeID)}, nil
}

// executeInsertNode creates or upserts one graph node and its properties.
func (e *Executor) executeInsertNode(ctx context.Context, stmt Statement, mutationCtx mutationContext) (executionResult, error) {
	request := graph.UpsertNodeRequest{
		Kind:         stmt.Kind,
		SourceNodeID: mutationCtx.source,
		Actor:        mutationCtx.actor,
	}
	properties := []Assignment{}
	if err := applyNodeAssignments(&request, &properties, stmt.Set); err != nil {
		return executionResult{}, err
	}
	node, err := e.store.UpsertNode(ctx, request)
	if err != nil {
		return executionResult{}, err
	}
	if err := e.auditNodeMutation(ctx, "query_insert_node", mutationCtx, node.ID, "inserted graph node", stmt.Set); err != nil {
		return executionResult{}, err
	}
	if err := e.upsertNodeProperties(ctx, node.ID, properties, mutationCtx); err != nil {
		return executionResult{}, err
	}
	return e.nodeMutationResult(ctx, node.ID, stmt.Return)
}

// executeInsertEdge creates or upserts one graph edge and its properties.
func (e *Executor) executeInsertEdge(ctx context.Context, stmt Statement, mutationCtx mutationContext) (executionResult, error) {
	request := graph.UpsertEdgeRequest{
		FromNodeID:   stmt.FromID,
		Type:         stmt.Relation,
		ToNodeID:     stmt.ToID,
		SourceNodeID: mutationCtx.source,
		Actor:        mutationCtx.actor,
	}
	properties := []Assignment{}
	if err := applyEdgeAssignments(&request, &properties, stmt.Set); err != nil {
		return executionResult{}, err
	}
	edge, err := e.store.UpsertEdge(ctx, request)
	if err != nil {
		return executionResult{}, err
	}
	if err := e.auditEdgeMutation(ctx, "query_insert_edge", mutationCtx, edge.ID, "inserted graph edge", stmt.Set); err != nil {
		return executionResult{}, err
	}
	if err := e.upsertEdgeProperties(ctx, edge.ID, properties, mutationCtx); err != nil {
		return executionResult{}, err
	}
	return e.edgeMutationResult(ctx, edge.ID, stmt.Return)
}

// executeSetNode updates node metadata or properties.
func (e *Executor) executeSetNode(ctx context.Context, stmt Statement, mutationCtx mutationContext) (executionResult, error) {
	node, err := e.store.GetNode(ctx, stmt.NodeID)
	if err != nil {
		return executionResult{}, err
	}
	request := graph.UpsertNodeRequest{
		NodeID:       node.ID,
		Kind:         node.Kind,
		StableKey:    node.StableKey,
		Title:        node.Title,
		Summary:      node.Summary,
		Status:       node.Status,
		Firewall:     node.Firewall,
		Sensitivity:  node.Sensitivity,
		TrustLevel:   node.TrustLevel,
		Confidence:   node.Confidence,
		SourceNodeID: mutationCtx.source,
		Actor:        mutationCtx.actor,
	}
	properties := []Assignment{}
	if err := applyNodeAssignments(&request, &properties, stmt.Set); err != nil {
		return executionResult{}, err
	}
	updated, err := e.store.UpsertNode(ctx, request)
	if err != nil {
		return executionResult{}, err
	}
	if err := e.auditNodeMutation(ctx, "query_set_node", mutationCtx, updated.ID, "updated graph node", stmt.Set); err != nil {
		return executionResult{}, err
	}
	if err := e.upsertNodeProperties(ctx, updated.ID, properties, mutationCtx); err != nil {
		return executionResult{}, err
	}
	return e.nodeMutationResult(ctx, updated.ID, stmt.Return)
}

// executeSetEdge updates edge metadata or properties.
func (e *Executor) executeSetEdge(ctx context.Context, stmt Statement, mutationCtx mutationContext) (executionResult, error) {
	edge, err := e.store.GetEdge(ctx, stmt.EdgeID)
	if err != nil {
		return executionResult{}, err
	}
	request := graph.UpsertEdgeRequest{
		EdgeID:       edge.ID,
		FromNodeID:   edge.FromNodeID,
		Type:         edge.Type,
		ToNodeID:     edge.ToNodeID,
		Status:       edge.Status,
		Confidence:   edge.Confidence,
		TrustLevel:   edge.TrustLevel,
		SourceNodeID: mutationCtx.source,
		Actor:        mutationCtx.actor,
		ValidFrom:    edge.ValidFrom,
		ValidTo:      edge.ValidTo,
	}
	properties := []Assignment{}
	if err := applyEdgeAssignments(&request, &properties, stmt.Set); err != nil {
		return executionResult{}, err
	}
	updated, err := e.store.UpsertEdge(ctx, request)
	if err != nil {
		return executionResult{}, err
	}
	if err := e.auditEdgeMutation(ctx, "query_set_edge", mutationCtx, updated.ID, "updated graph edge", stmt.Set); err != nil {
		return executionResult{}, err
	}
	if err := e.upsertEdgeProperties(ctx, updated.ID, properties, mutationCtx); err != nil {
		return executionResult{}, err
	}
	return e.edgeMutationResult(ctx, updated.ID, stmt.Return)
}

// executeDeleteNode lifecycle-deletes one graph node.
func (e *Executor) executeDeleteNode(ctx context.Context, stmt Statement, mutationCtx mutationContext) (executionResult, error) {
	deleted, err := e.store.SetNodeStatus(ctx, stmt.NodeID, graph.StatusDeleted, mutationCtx.actor)
	if err != nil {
		return executionResult{}, err
	}
	if err := e.auditNodeMutation(ctx, "query_delete_node", mutationCtx, deleted.ID, "deleted graph node", nil); err != nil {
		return executionResult{}, err
	}
	return e.nodeMutationResult(ctx, deleted.ID, stmt.Return)
}

// executeDeleteEdge lifecycle-deletes one graph edge.
func (e *Executor) executeDeleteEdge(ctx context.Context, stmt Statement, mutationCtx mutationContext) (executionResult, error) {
	deleted, err := e.store.SetEdgeStatus(ctx, stmt.EdgeID, graph.StatusDeleted, mutationCtx.actor)
	if err != nil {
		return executionResult{}, err
	}
	if err := e.auditEdgeMutation(ctx, "query_delete_edge", mutationCtx, deleted.ID, "deleted graph edge", nil); err != nil {
		return executionResult{}, err
	}
	return e.edgeMutationResult(ctx, deleted.ID, stmt.Return)
}

// applyNodeAssignments separates node metadata assignments from property writes.
func applyNodeAssignments(request *graph.UpsertNodeRequest, properties *[]Assignment, assignments []Assignment) error {
	for _, assignment := range assignments {
		switch assignment.Field {
		case "stable_key":
			request.StableKey = assignment.Value.Value
		case "title":
			request.Title = assignment.Value.Value
		case "summary":
			request.Summary = assignment.Value.Value
		case "lifecycle_status", "node_status":
			status := graph.LifecycleStatus(strings.ToLower(assignment.Value.Value))
			if !graph.ValidLifecycleStatus(status) {
				return fmt.Errorf("invalid node lifecycle status %q", assignment.Value.Value)
			}
			request.Status = status
		case "firewall":
			firewall := graph.Firewall(strings.ToLower(assignment.Value.Value))
			if !graph.ValidFirewall(firewall) {
				return fmt.Errorf("invalid node firewall %q", assignment.Value.Value)
			}
			request.Firewall = firewall
		case "sensitivity":
			sensitivity := graph.Sensitivity(strings.ToLower(assignment.Value.Value))
			if !graph.ValidSensitivity(sensitivity) {
				return fmt.Errorf("invalid node sensitivity %q", assignment.Value.Value)
			}
			request.Sensitivity = sensitivity
		case "trust_level":
			trust := graph.TrustLevel(strings.ToLower(assignment.Value.Value))
			if !graph.ValidTrustLevel(trust) {
				return fmt.Errorf("invalid node trust level %q", assignment.Value.Value)
			}
			request.TrustLevel = trust
		case "confidence", "node_confidence":
			confidence, err := strconv.ParseFloat(assignment.Value.Value, 64)
			if err != nil {
				return fmt.Errorf("invalid node confidence %q", assignment.Value.Value)
			}
			request.Confidence = confidence
		case "id", "node_id", "kind", "source_node_id", "actor":
			return fmt.Errorf("field %s is controlled by the graph store or request metadata", assignment.Field)
		default:
			*properties = append(*properties, Assignment{Field: propertyField(assignment.Field), Value: assignment.Value})
		}
	}
	return nil
}

// applyEdgeAssignments separates edge metadata assignments from property writes.
func applyEdgeAssignments(request *graph.UpsertEdgeRequest, properties *[]Assignment, assignments []Assignment) error {
	for _, assignment := range assignments {
		switch assignment.Field {
		case "lifecycle_status", "edge_status":
			status := graph.LifecycleStatus(strings.ToLower(assignment.Value.Value))
			if !graph.ValidLifecycleStatus(status) {
				return fmt.Errorf("invalid edge lifecycle status %q", assignment.Value.Value)
			}
			request.Status = status
		case "confidence", "edge_confidence":
			confidence, err := strconv.ParseFloat(assignment.Value.Value, 64)
			if err != nil {
				return fmt.Errorf("invalid edge confidence %q", assignment.Value.Value)
			}
			request.Confidence = confidence
		case "trust_level":
			trust := graph.TrustLevel(strings.ToLower(assignment.Value.Value))
			if !graph.ValidTrustLevel(trust) {
				return fmt.Errorf("invalid edge trust level %q", assignment.Value.Value)
			}
			request.TrustLevel = trust
		case "valid_from":
			value, err := literalTime(assignment.Value)
			if err != nil {
				return err
			}
			request.ValidFrom = &value
		case "valid_to":
			value, err := literalTime(assignment.Value)
			if err != nil {
				return err
			}
			request.ValidTo = &value
		case "id", "edge.id", "edge_id", "type", "relation_type", "from_id", "from_node_id", "to_id", "to_node_id", "source_node_id", "actor":
			return fmt.Errorf("field %s is controlled by the graph store or request metadata", assignment.Field)
		default:
			*properties = append(*properties, Assignment{Field: propertyField(assignment.Field), Value: assignment.Value})
		}
	}
	return nil
}

// propertyField normalizes explicit property assignment prefixes.
func propertyField(field string) string {
	field = strings.TrimPrefix(field, "property.")
	field = strings.TrimPrefix(field, "prop.")
	return field
}

// upsertNodeProperties writes node properties with required provenance and audit.
func (e *Executor) upsertNodeProperties(ctx context.Context, nodeID graph.NodeID, assignments []Assignment, mutationCtx mutationContext) error {
	for _, assignment := range assignments {
		if assignment.Field == "" {
			return fmt.Errorf("property field is required")
		}
		if _, err := e.store.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
			NodeID:       nodeID,
			Key:          assignment.Field,
			Value:        assignmentValue(assignment),
			SourceNodeID: mutationCtx.source,
			Actor:        mutationCtx.actor,
		}); err != nil {
			return err
		}
		if err := e.auditNodeMutation(ctx, "query_set_node_property", mutationCtx, nodeID, "set graph node property", []Assignment{assignment}); err != nil {
			return err
		}
	}
	return nil
}

// upsertEdgeProperties writes edge properties with required provenance and audit.
func (e *Executor) upsertEdgeProperties(ctx context.Context, edgeID graph.EdgeID, assignments []Assignment, mutationCtx mutationContext) error {
	for _, assignment := range assignments {
		if assignment.Field == "" {
			return fmt.Errorf("property field is required")
		}
		if _, err := e.store.UpsertEdgeProperty(ctx, graph.UpsertEdgePropertyRequest{
			EdgeID:       edgeID,
			Key:          assignment.Field,
			Value:        assignmentValue(assignment),
			SourceNodeID: mutationCtx.source,
			Actor:        mutationCtx.actor,
		}); err != nil {
			return err
		}
		if err := e.auditEdgeMutation(ctx, "query_set_edge_property", mutationCtx, edgeID, "set graph edge property", []Assignment{assignment}); err != nil {
			return err
		}
	}
	return nil
}

// assignmentValue converts a parsed assignment into a typed graph value.
func assignmentValue(assignment Assignment) graph.Value {
	field := assignment.Field
	literal := assignment.Value
	if literal.Token == TokenNumber {
		number, err := strconv.ParseFloat(literal.Value, 64)
		if err == nil {
			return graph.Value{Type: graph.ValueNumber, Number: number}
		}
	}
	if literal.Token == TokenIdentifier {
		if parsed, ok := parseBoolLiteral(literal.Value); ok {
			return graph.Value{Type: graph.ValueBool, Text: strconv.FormatBool(parsed)}
		}
	}
	if timeLikeField(field) {
		if parsed, err := literalTime(literal); err == nil {
			return graph.Value{Type: graph.ValueTime, Time: &parsed}
		}
	}
	return graph.Value{Type: graph.ValueText, Text: literal.Value}
}

// parseBoolLiteral parses unquoted boolean identifiers.
func parseBoolLiteral(value string) (bool, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "true":
		return true, true
	case "false":
		return false, true
	default:
		return false, false
	}
}

// timeLikeField reports whether an assignment field should be parsed as time.
func timeLikeField(field string) bool {
	return strings.HasSuffix(field, "_at") || strings.HasSuffix(field, "_time") || field == "valid_from" || field == "valid_to"
}

// literalTime parses a mutation time literal.
func literalTime(literal Literal) (time.Time, error) {
	if parsed, ok := parseConditionTime(literal.Value); ok {
		return parsed, nil
	}
	return time.Time{}, fmt.Errorf("invalid time literal %q", literal.Value)
}

// nodeMutationResult projects a mutated node into a query result.
func (e *Executor) nodeMutationResult(ctx context.Context, nodeID graph.NodeID, fields []string) (executionResult, error) {
	node, err := e.store.GetNode(ctx, nodeID)
	if err != nil {
		return executionResult{}, err
	}
	properties, err := e.propertyValues(ctx, node.ID)
	if err != nil {
		return executionResult{}, err
	}
	candidate := queryCandidate{node: node, properties: properties}
	return executionResult{rows: []Row{candidate.row(fields)}}, nil
}

// edgeMutationResult projects a mutated edge and its properties into a result.
func (e *Executor) edgeMutationResult(ctx context.Context, edgeID graph.EdgeID, fields []string) (executionResult, error) {
	edge, err := e.store.GetEdge(ctx, edgeID)
	if err != nil {
		return executionResult{}, err
	}
	properties, err := e.edgePropertyValues(ctx, edge.ID)
	if err != nil {
		return executionResult{}, err
	}
	candidate := edgeMutationCandidate{edge: edge, properties: properties}
	return executionResult{rows: []Row{candidate.row(fields)}}, nil
}

// auditNodeMutation appends an audit event for a node mutation.
func (e *Executor) auditNodeMutation(ctx context.Context, kind string, mutationCtx mutationContext, nodeID graph.NodeID, message string, assignments []Assignment) error {
	_, err := e.store.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          kind,
		Actor:         mutationCtx.actor,
		SubjectNodeID: nodeID,
		SourceNodeID:  mutationCtx.source,
		Message:       message,
		DetailsJSON:   assignmentDetails(assignments),
	})
	return err
}

// auditEdgeMutation appends an audit event for an edge mutation.
func (e *Executor) auditEdgeMutation(ctx context.Context, kind string, mutationCtx mutationContext, edgeID graph.EdgeID, message string, assignments []Assignment) error {
	_, err := e.store.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          kind,
		Actor:         mutationCtx.actor,
		SubjectEdgeID: edgeID,
		SourceNodeID:  mutationCtx.source,
		Message:       message,
		DetailsJSON:   assignmentDetails(assignments),
	})
	return err
}

// assignmentDetails serializes mutation assignment metadata for audit records.
func assignmentDetails(assignments []Assignment) string {
	if len(assignments) == 0 {
		return ""
	}
	values := make(map[string]string, len(assignments))
	for _, assignment := range assignments {
		values[assignment.Field] = assignment.Value.Value
	}
	bytes, err := json.Marshal(values)
	if err != nil {
		return ""
	}
	return string(bytes)
}

// propertyValues loads active node properties as typed query values.
func (e *Executor) propertyValues(ctx context.Context, nodeID graph.NodeID) (map[string]any, error) {
	properties, err := e.store.ListNodeProperties(ctx, nodeID)
	if err != nil {
		return nil, err
	}
	values := map[string]any{}
	for _, property := range properties {
		values[property.Key] = queryValue(property.Value)
	}
	return values, nil
}

// edgePropertyValues loads active edge properties as typed query values.
func (e *Executor) edgePropertyValues(ctx context.Context, edgeID graph.EdgeID) (map[string]any, error) {
	properties, err := e.store.ListEdgeProperties(ctx, edgeID)
	if err != nil {
		return nil, err
	}
	values := map[string]any{}
	for _, property := range properties {
		values[property.Key] = queryValue(property.Value)
	}
	return values, nil
}
