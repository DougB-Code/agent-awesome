package query

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
	"memory/internal/memory/normalize"
)

const maxTraversalCandidates = 1000

// Store is the graph storage surface required by query execution.
type Store interface {
	SearchNodes(context.Context, graph.SearchNodesQuery) ([]graph.Node, error)
	ListEdges(context.Context, []graph.RelationType, int) ([]graph.Edge, error)
	ListOutgoingEdges(context.Context, graph.NodeID, []graph.RelationType) ([]graph.Edge, error)
	GetNode(context.Context, graph.NodeID) (graph.Node, error)
	GetEdge(context.Context, graph.EdgeID) (graph.Edge, error)
	UpsertNode(context.Context, graph.UpsertNodeRequest) (graph.Node, error)
	UpsertEdge(context.Context, graph.UpsertEdgeRequest) (graph.Edge, error)
	SetNodeStatus(context.Context, graph.NodeID, graph.LifecycleStatus, string) (graph.Node, error)
	SetEdgeStatus(context.Context, graph.EdgeID, graph.LifecycleStatus, string) (graph.Edge, error)
	UpsertNodeProperty(context.Context, graph.UpsertNodePropertyRequest) (graph.NodeProperty, error)
	UpsertEdgeProperty(context.Context, graph.UpsertEdgePropertyRequest) (graph.EdgeProperty, error)
	AppendAudit(context.Context, graph.AppendAuditRequest) (graph.AuditEvent, error)
	ListNodeProperties(context.Context, graph.NodeID) ([]graph.NodeProperty, error)
	ListEdgeProperties(context.Context, graph.EdgeID) ([]graph.EdgeProperty, error)
}

// Executor evaluates parsed graph statements against graph storage.
type Executor struct {
	store Store
}

// graphQueryAccessPolicy stores node visibility rules for one query.
type graphQueryAccessPolicy struct {
	scope                 graph.Scope
	allowedSensitivities  []graph.Sensitivity
	allowedSensitivitySet map[graph.Sensitivity]bool
}

// executionResult stores rows and optional paths produced by one query.
type executionResult struct {
	rows  []domain.GraphQueryRow
	paths []domain.GraphQueryPath
}

// mutationContext stores required provenance for graph writes.
type mutationContext struct {
	actor  string
	source graph.NodeID
}

// NewExecutor creates a graph query executor.
func NewExecutor(store Store) *Executor {
	return &Executor{store: store}
}

// Execute parses and evaluates one graph query or audited mutation.
func (e *Executor) Execute(ctx context.Context, req domain.GraphQueryRequest) (domain.GraphQueryResult, error) {
	rawActor := strings.TrimSpace(req.Actor)
	req, err := domain.NormalizeGraphQueryRequest(req)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	stmt, err := Parse(req.Query)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	mutationCtx, err := mutationContextFromRequest(stmt, req, rawActor)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	policy := graphQueryAccessPolicyFromRequest(req)
	output, err := e.executeStatement(ctx, stmt, policy, mutationCtx)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	return domain.GraphQueryResult{
		Columns: stmt.Return,
		Rows:    output.rows,
		Paths:   output.paths,
		Limit:   stmt.Limit,
		Query:   req.Query,
	}, nil
}

// mutationContextFromRequest validates required mutation provenance.
func mutationContextFromRequest(stmt Statement, req domain.GraphQueryRequest, rawActor string) (mutationContext, error) {
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

// graphQueryAccessPolicyFromRequest builds graph read policy from public request metadata.
func graphQueryAccessPolicyFromRequest(req domain.GraphQueryRequest) graphQueryAccessPolicy {
	allowed := make([]graph.Sensitivity, 0, len(req.AllowedSensitivities))
	allowedSet := map[graph.Sensitivity]bool{}
	for _, sensitivity := range req.AllowedSensitivities {
		allowed = append(allowed, sensitivity)
		allowedSet[sensitivity] = true
	}
	return graphQueryAccessPolicy{
		scope:                 req.Scope,
		allowedSensitivities:  allowed,
		allowedSensitivitySet: allowedSet,
	}
}

// canReadNode reports whether a node is visible under the query read policy.
func (p graphQueryAccessPolicy) canReadNode(node graph.Node) bool {
	if node.Status != graph.StatusActive {
		return false
	}
	if node.Scope != p.scope && node.Scope != graph.ScopeGlobal {
		return false
	}
	return p.allowedSensitivitySet[node.Sensitivity]
}

// executeStatement evaluates one parsed statement.
func (e *Executor) executeStatement(ctx context.Context, stmt Statement, policy graphQueryAccessPolicy, mutationCtx mutationContext) (executionResult, error) {
	switch stmt.Mode {
	case StatementMatch:
		return e.executeMatch(ctx, stmt, policy)
	case StatementInsertNode:
		return e.executeInsertNode(ctx, stmt, mutationCtx)
	case StatementInsertEdge:
		return e.executeInsertEdge(ctx, stmt, mutationCtx)
	case StatementSetNode:
		return e.executeSetNode(ctx, stmt, mutationCtx)
	case StatementSetEdge:
		return e.executeSetEdge(ctx, stmt, mutationCtx)
	case StatementDeleteNode:
		return e.executeDeleteNode(ctx, stmt, mutationCtx)
	case StatementDeleteEdge:
		return e.executeDeleteEdge(ctx, stmt, mutationCtx)
	default:
		return e.executeFind(ctx, stmt, policy)
	}
}

// executeFind evaluates one FIND node statement.
func (e *Executor) executeFind(ctx context.Context, stmt Statement, policy graphQueryAccessPolicy) (executionResult, error) {
	nodes, err := e.store.SearchNodes(ctx, graph.SearchNodesQuery{
		Kinds:                []graph.NodeKind{stmt.Kind},
		Scope:                policy.scope,
		AllowedSensitivities: policy.allowedSensitivities,
		Limit:                100,
	})
	if err != nil {
		return executionResult{}, err
	}
	candidates := []queryCandidate{}
	for _, node := range nodes {
		properties, err := e.propertyValues(ctx, node.ID)
		if err != nil {
			return executionResult{}, err
		}
		candidate := queryCandidate{node: node, properties: properties}
		if !candidate.matches(stmt.Where) {
			continue
		}
		candidates = append(candidates, candidate)
	}
	if stmt.GroupBy != "" {
		return executionResult{rows: groupCandidateRows(candidates, stmt)}, nil
	}
	sortCandidates(candidates, stmt.OrderBy, stmt.Order)
	if len(candidates) > stmt.Limit {
		candidates = candidates[:stmt.Limit]
	}
	return executionResult{rows: queryRowsFromCandidates(candidates, stmt.Return)}, nil
}

// executeMatch evaluates one-hop directed edge traversal.
func (e *Executor) executeMatch(ctx context.Context, stmt Statement, policy graphQueryAccessPolicy) (executionResult, error) {
	if stmt.MaxDepth > 1 {
		return e.executeVariableMatch(ctx, stmt, policy)
	}
	edges, err := e.store.ListEdges(ctx, []graph.RelationType{stmt.Relation}, 1000)
	if err != nil {
		return executionResult{}, err
	}
	candidates := []matchCandidate{}
	for _, edge := range edges {
		from, err := e.store.GetNode(ctx, edge.FromNodeID)
		if err != nil {
			return executionResult{}, err
		}
		to, err := e.store.GetNode(ctx, edge.ToNodeID)
		if err != nil {
			return executionResult{}, err
		}
		if from.Kind != stmt.FromKind || to.Kind != stmt.ToKind || !policy.canReadNode(from) || !policy.canReadNode(to) {
			continue
		}
		fromProperties, err := e.propertyValues(ctx, from.ID)
		if err != nil {
			return executionResult{}, err
		}
		toProperties, err := e.propertyValues(ctx, to.ID)
		if err != nil {
			return executionResult{}, err
		}
		candidate := matchCandidate{
			from:        queryCandidate{node: from, properties: fromProperties},
			edge:        edge,
			to:          queryCandidate{node: to, properties: toProperties},
			pathNodeIDs: []graph.NodeID{from.ID, to.ID},
			pathEdgeIDs: []graph.EdgeID{edge.ID},
		}
		if !candidate.matches(stmt.Where) {
			continue
		}
		candidates = append(candidates, candidate)
	}
	if stmt.GroupBy != "" {
		return executionResult{rows: groupCandidateRows(candidates, stmt)}, nil
	}
	sortMatchCandidates(candidates, stmt.OrderBy, stmt.Order)
	if len(candidates) > stmt.Limit {
		candidates = candidates[:stmt.Limit]
	}
	rows, paths := matchRowsAndPaths(candidates, stmt.Return)
	return executionResult{rows: rows, paths: paths}, nil
}

// executeVariableMatch evaluates bounded variable-length directed traversal.
func (e *Executor) executeVariableMatch(ctx context.Context, stmt Statement, policy graphQueryAccessPolicy) (executionResult, error) {
	roots, err := e.store.SearchNodes(ctx, graph.SearchNodesQuery{
		Kinds:                []graph.NodeKind{stmt.FromKind},
		Scope:                policy.scope,
		AllowedSensitivities: policy.allowedSensitivities,
		Limit:                100,
	})
	if err != nil {
		return executionResult{}, err
	}
	candidates := []matchCandidate{}
	for _, root := range roots {
		if !policy.canReadNode(root) {
			continue
		}
		rootProperties, err := e.propertyValues(ctx, root.ID)
		if err != nil {
			return executionResult{}, err
		}
		walker := variableMatchWalker{
			executor: e,
			stmt:     stmt,
			root:     queryCandidate{node: root, properties: rootProperties},
			policy:   policy,
		}
		state := variableMatchState{
			current:     root,
			pathNodeIDs: []graph.NodeID{root.ID},
			seen:        map[graph.NodeID]bool{root.ID: true},
		}
		if err := walker.walk(ctx, state, &candidates); err != nil {
			return executionResult{}, err
		}
		if len(candidates) >= maxTraversalCandidates {
			break
		}
	}
	if stmt.GroupBy != "" {
		return executionResult{rows: groupCandidateRows(candidates, stmt)}, nil
	}
	sortMatchCandidates(candidates, stmt.OrderBy, stmt.Order)
	if len(candidates) > stmt.Limit {
		candidates = candidates[:stmt.Limit]
	}
	rows, paths := matchRowsAndPaths(candidates, stmt.Return)
	return executionResult{rows: rows, paths: paths}, nil
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
		Scope:        node.Scope,
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
		case "scope":
			scope := graph.Scope(strings.ToLower(assignment.Value.Value))
			if !graph.ValidScope(scope) {
				return fmt.Errorf("invalid node scope %q", assignment.Value.Value)
			}
			request.Scope = scope
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
	return executionResult{rows: []domain.GraphQueryRow{candidate.row(fields)}}, nil
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
	return executionResult{rows: []domain.GraphQueryRow{candidate.row(fields)}}, nil
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

// edgeMutationCandidate stores one edge and its property lookup map.
type edgeMutationCandidate struct {
	edge       graph.Edge
	properties map[string]any
}

// row returns selected fields for one edge mutation result.
func (c edgeMutationCandidate) row(fields []string) domain.GraphQueryRow {
	return projectorRow(c, fields)
}

// typedField returns a JSON-friendly value for one edge mutation field.
func (c edgeMutationCandidate) typedField(field string) any {
	if strings.HasPrefix(field, "edge.") {
		return edgeTypedField(c.edge, strings.TrimPrefix(field, "edge."))
	}
	if value, ok := c.properties[field]; ok {
		return value
	}
	return edgeTypedField(c.edge, field)
}

// matchCandidate stores one directed edge plus endpoint nodes.
type matchCandidate struct {
	from        queryCandidate
	edge        graph.Edge
	to          queryCandidate
	pathNodeIDs []graph.NodeID
	pathEdgeIDs []graph.EdgeID
}

// matches reports whether a match candidate satisfies every condition.
func (c matchCandidate) matches(conditions []Condition) bool {
	return projectorMatches(c, conditions)
}

// row returns selected fields for one match candidate.
func (c matchCandidate) row(fields []string) domain.GraphQueryRow {
	return projectorRow(c, fields)
}

// path returns graph path metadata associated with one match row.
func (c matchCandidate) path(rowIndex int) domain.GraphQueryPath {
	return domain.GraphQueryPath{
		RowIndex: rowIndex,
		Depth:    len(c.pathEdgeIDs),
		NodeIDs:  graphNodeIDStrings(c.pathNodeIDs),
		EdgeIDs:  graphEdgeIDStrings(c.pathEdgeIDs),
	}
}

// typedField returns a JSON-friendly value for one match field.
func (c matchCandidate) typedField(field string) any {
	switch {
	case strings.HasPrefix(field, "from."):
		return c.from.typedField(strings.TrimPrefix(field, "from."))
	case strings.HasPrefix(field, "to."):
		return c.to.typedField(strings.TrimPrefix(field, "to."))
	case strings.HasPrefix(field, "edge."):
		return edgeTypedField(c.edge, strings.TrimPrefix(field, "edge."))
	case strings.HasPrefix(field, "path."):
		return pathTypedField(c.pathNodeIDs, c.pathEdgeIDs, strings.TrimPrefix(field, "path."))
	default:
		return ""
	}
}

// variableMatchState stores one traversal branch.
type variableMatchState struct {
	current     graph.Node
	lastEdge    graph.Edge
	pathNodeIDs []graph.NodeID
	pathEdgeIDs []graph.EdgeID
	seen        map[graph.NodeID]bool
}

// variableMatchWalker builds bounded traversal candidates.
type variableMatchWalker struct {
	executor *Executor
	stmt     Statement
	root     queryCandidate
	policy   graphQueryAccessPolicy
}

// walk follows outgoing relation edges while enforcing max depth and cycle protection.
func (w variableMatchWalker) walk(ctx context.Context, state variableMatchState, candidates *[]matchCandidate) error {
	if len(*candidates) >= maxTraversalCandidates || len(state.pathEdgeIDs) >= w.stmt.MaxDepth {
		return nil
	}
	edges, err := w.executor.store.ListOutgoingEdges(ctx, state.current.ID, []graph.RelationType{w.stmt.Relation})
	if err != nil {
		return err
	}
	for _, edge := range edges {
		if len(*candidates) >= maxTraversalCandidates {
			return nil
		}
		target, err := w.executor.store.GetNode(ctx, edge.ToNodeID)
		if err != nil {
			return err
		}
		if !w.policy.canReadNode(target) || state.seen[target.ID] {
			continue
		}
		nextState := state.extend(edge, target)
		if len(nextState.pathEdgeIDs) >= w.stmt.MinDepth && target.Kind == w.stmt.ToKind {
			targetProperties, err := w.executor.propertyValues(ctx, target.ID)
			if err != nil {
				return err
			}
			candidate := matchCandidate{
				from:        w.root,
				edge:        edge,
				to:          queryCandidate{node: target, properties: targetProperties},
				pathNodeIDs: append([]graph.NodeID{}, nextState.pathNodeIDs...),
				pathEdgeIDs: append([]graph.EdgeID{}, nextState.pathEdgeIDs...),
			}
			if candidate.matches(w.stmt.Where) {
				*candidates = append(*candidates, candidate)
			}
		}
		if len(nextState.pathEdgeIDs) < w.stmt.MaxDepth {
			nextState.seen[target.ID] = true
			if err := w.walk(ctx, nextState, candidates); err != nil {
				return err
			}
		}
	}
	return nil
}

// extend returns a copied traversal branch with one more edge.
func (s variableMatchState) extend(edge graph.Edge, target graph.Node) variableMatchState {
	return variableMatchState{
		current:     target,
		lastEdge:    edge,
		pathNodeIDs: append(append([]graph.NodeID{}, s.pathNodeIDs...), target.ID),
		pathEdgeIDs: append(append([]graph.EdgeID{}, s.pathEdgeIDs...), edge.ID),
		seen:        cloneSeenNodeIDs(s.seen),
	}
}

// cloneSeenNodeIDs copies cycle state for one traversal branch.
func cloneSeenNodeIDs(input map[graph.NodeID]bool) map[graph.NodeID]bool {
	output := make(map[graph.NodeID]bool, len(input))
	for key, value := range input {
		output[key] = value
	}
	return output
}

// graphQueryProjector exposes typed values that can be grouped into aggregate rows.
type graphQueryProjector interface {
	typedField(string) any
}

// projectorMatches reports whether a projected candidate satisfies every condition.
func projectorMatches(candidate graphQueryProjector, conditions []Condition) bool {
	for _, condition := range conditions {
		if !conditionMatches(condition, candidate.typedField(condition.Field)) {
			return false
		}
	}
	return true
}

// projectorRow returns selected fields for one projected candidate.
func projectorRow(candidate graphQueryProjector, fields []string) domain.GraphQueryRow {
	row := domain.GraphQueryRow{}
	for _, field := range fields {
		row[field] = candidate.typedField(field)
	}
	return row
}

// groupAccumulator stores one aggregate bucket.
type groupAccumulator struct {
	value any
	count int
}

// groupCandidateRows groups filtered FIND or MATCH candidates and returns aggregate rows.
func groupCandidateRows[T graphQueryProjector](candidates []T, stmt Statement) []domain.GraphQueryRow {
	groups := map[string]groupAccumulator{}
	for _, candidate := range candidates {
		value := candidate.typedField(stmt.GroupBy)
		key := comparableString(value)
		group := groups[key]
		if group.count == 0 {
			group.value = value
		}
		group.count++
		groups[key] = group
	}
	keys := make([]string, 0, len(groups))
	for key := range groups {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	rows := make([]domain.GraphQueryRow, 0, len(keys))
	for _, key := range keys {
		group := groups[key]
		rows = append(rows, domain.GraphQueryRow{
			stmt.GroupBy: group.value,
			"count":      group.count,
		})
	}
	sortRows(rows, groupOrderField(stmt), stmt.Order)
	rows = limitRows(rows, stmt.Limit)
	return projectRows(rows, stmt.Return)
}

// groupOrderField returns the implicit aggregate order field.
func groupOrderField(stmt Statement) string {
	if stmt.OrderBy != "" {
		return stmt.OrderBy
	}
	return stmt.GroupBy
}

// sortRows orders already projected aggregate rows by a typed value.
func sortRows(rows []domain.GraphQueryRow, field string, order SortOrder) {
	if field == "" {
		return
	}
	sort.SliceStable(rows, func(i, j int) bool {
		comparison := compareRowValues(rows[i][field], rows[j][field])
		if order == SortDescending {
			return comparison > 0
		}
		return comparison < 0
	})
}

// compareRowValues compares numeric aggregate values before falling back to strings.
func compareRowValues(left any, right any) int {
	if leftTime, ok := timeConditionValue(left); ok {
		if rightTime, ok := timeConditionValue(right); ok {
			return compareTimes(leftTime, rightTime)
		}
	}
	leftNumber, leftNumeric := numericValue(left, false)
	rightNumber, rightNumeric := numericValue(right, false)
	if leftNumeric && rightNumeric {
		switch {
		case leftNumber < rightNumber:
			return -1
		case leftNumber > rightNumber:
			return 1
		default:
			return 0
		}
	}
	return strings.Compare(strings.ToLower(comparableString(left)), strings.ToLower(comparableString(right)))
}

// limitRows applies the validated row limit to aggregate output.
func limitRows(rows []domain.GraphQueryRow, limit int) []domain.GraphQueryRow {
	if len(rows) > limit {
		return rows[:limit]
	}
	return rows
}

// projectRows returns only the requested aggregate columns.
func projectRows(rows []domain.GraphQueryRow, fields []string) []domain.GraphQueryRow {
	projected := make([]domain.GraphQueryRow, 0, len(rows))
	for _, row := range rows {
		projectedRow := domain.GraphQueryRow{}
		for _, field := range fields {
			projectedRow[field] = row[field]
		}
		projected = append(projected, projectedRow)
	}
	return projected
}

// field returns a comparable string for one match field.
func (c matchCandidate) field(field string) string {
	return comparableString(c.typedField(field))
}

// queryCandidate stores a node and its property lookup map.
type queryCandidate struct {
	node       graph.Node
	properties map[string]any
}

// matches reports whether candidate satisfies every condition.
func (c queryCandidate) matches(conditions []Condition) bool {
	return projectorMatches(c, conditions)
}

// row returns selected fields for one candidate.
func (c queryCandidate) row(fields []string) domain.GraphQueryRow {
	return projectorRow(c, fields)
}

// typedField returns a JSON-friendly value for one field.
func (c queryCandidate) typedField(field string) any {
	switch field {
	case "id":
		return string(c.node.ID)
	case "kind":
		return string(c.node.Kind)
	case "title":
		return c.node.Title
	case "summary":
		return c.node.Summary
	case "lifecycle_status", "node_status":
		return string(c.node.Status)
	case "scope":
		return string(c.node.Scope)
	case "sensitivity":
		return string(c.node.Sensitivity)
	case "trust_level":
		return string(c.node.TrustLevel)
	case "node_confidence":
		return c.node.Confidence
	case "node_actor":
		return c.node.Actor
	case "created_at":
		return c.node.CreatedAt
	case "updated_at":
		return c.node.UpdatedAt
	default:
		if value, ok := c.properties[field]; ok {
			return value
		}
		switch field {
		case "status":
			return string(c.node.Status)
		case "confidence":
			return c.node.Confidence
		case "actor":
			return c.node.Actor
		default:
			return ""
		}
	}
}

// field returns a comparable string for one field.
func (c queryCandidate) field(field string) string {
	return comparableString(c.typedField(field))
}

// queryRowsFromCandidates projects node candidates into result rows.
func queryRowsFromCandidates(candidates []queryCandidate, fields []string) []domain.GraphQueryRow {
	rows := make([]domain.GraphQueryRow, 0, len(candidates))
	for _, candidate := range candidates {
		rows = append(rows, candidate.row(fields))
	}
	return rows
}

// matchRowsAndPaths projects match candidates into result rows and path metadata.
func matchRowsAndPaths(candidates []matchCandidate, fields []string) ([]domain.GraphQueryRow, []domain.GraphQueryPath) {
	rows := make([]domain.GraphQueryRow, 0, len(candidates))
	paths := make([]domain.GraphQueryPath, 0, len(candidates))
	for index, candidate := range candidates {
		rows = append(rows, candidate.row(fields))
		paths = append(paths, candidate.path(index))
	}
	return rows, paths
}

// edgeTypedField returns a JSON-friendly value for one edge field.
func edgeTypedField(edge graph.Edge, field string) any {
	switch field {
	case "id":
		return string(edge.ID)
	case "type", "relation_type":
		return string(edge.Type)
	case "status", "lifecycle_status":
		return string(edge.Status)
	case "confidence":
		return edge.Confidence
	case "actor":
		return edge.Actor
	case "from_id", "from_node_id":
		return string(edge.FromNodeID)
	case "to_id", "to_node_id":
		return string(edge.ToNodeID)
	case "created_at":
		return edge.CreatedAt
	case "updated_at":
		return edge.UpdatedAt
	default:
		return ""
	}
}

// pathTypedField returns a JSON-friendly value for one path field.
func pathTypedField(nodeIDs []graph.NodeID, edgeIDs []graph.EdgeID, field string) any {
	switch field {
	case "depth":
		return len(edgeIDs)
	case "node_ids":
		return graphNodeIDStrings(nodeIDs)
	case "edge_ids":
		return graphEdgeIDStrings(edgeIDs)
	default:
		return ""
	}
}

// graphNodeIDStrings returns string IDs for node path metadata.
func graphNodeIDStrings(nodeIDs []graph.NodeID) []string {
	return graphIDStrings(nodeIDs)
}

// graphEdgeIDStrings returns string IDs for edge path metadata.
func graphEdgeIDStrings(edgeIDs []graph.EdgeID) []string {
	return graphIDStrings(edgeIDs)
}

// graphIDStrings returns string IDs for typed graph identifiers.
func graphIDStrings[T ~string](ids []T) []string {
	values := make([]string, 0, len(ids))
	for _, id := range ids {
		values = append(values, string(id))
	}
	return values
}

// comparableString returns a string used for equality and sorting.
func comparableString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case bool:
		return strconv.FormatBool(typed)
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	case int:
		return strconv.Itoa(typed)
	case time.Time:
		return typed.UTC().Format(time.RFC3339Nano)
	case []string:
		return strings.Join(typed, ",")
	default:
		return fmt.Sprint(value)
	}
}

// conditionMatches applies one parsed WHERE condition to a resolved field value.
func conditionMatches(condition Condition, actual any) bool {
	if orderedOperator(condition.Operator) && strings.TrimSpace(comparableString(actual)) == "" {
		return false
	}
	comparison := compareConditionValues(actual, condition.Value)
	switch condition.Operator {
	case OperatorEqual:
		return comparison == 0
	case OperatorNotEqual:
		return comparison != 0
	case OperatorLessThan:
		return comparison < 0
	case OperatorLessOrEqual:
		return comparison <= 0
	case OperatorGreaterThan:
		return comparison > 0
	case OperatorGreaterOrEqual:
		return comparison >= 0
	default:
		return false
	}
}

// orderedOperator reports whether an operator requires an existing sortable field.
func orderedOperator(operator ConditionOperator) bool {
	switch operator {
	case OperatorLessThan, OperatorLessOrEqual, OperatorGreaterThan, OperatorGreaterOrEqual:
		return true
	default:
		return false
	}
}

// compareConditionValues compares time, numeric, then case-folded string values.
func compareConditionValues(actual any, expected string) int {
	if left, ok := timeConditionValue(actual); ok {
		if right, ok := parseConditionTime(expected); ok {
			return compareTimes(left, right)
		}
	}
	if left, ok := numericValue(actual, true); ok {
		if right, ok := numericValue(expected, true); ok {
			return compareNumbers(left, right)
		}
	}
	return strings.Compare(strings.ToLower(comparableString(actual)), strings.ToLower(expected))
}

// timeConditionValue extracts a comparable time from a field value.
func timeConditionValue(value any) (time.Time, bool) {
	switch typed := value.(type) {
	case time.Time:
		return typed, true
	case *time.Time:
		if typed == nil {
			return time.Time{}, false
		}
		return *typed, true
	case string:
		return parseConditionTime(typed)
	default:
		return time.Time{}, false
	}
}

// parseConditionTime parses graph query time literals.
func parseConditionTime(value string) (time.Time, bool) {
	return normalize.ParseFlexibleTime(value)
}

// compareTimes compares two timestamp values.
func compareTimes(left time.Time, right time.Time) int {
	switch {
	case left.Before(right):
		return -1
	case left.After(right):
		return 1
	default:
		return 0
	}
}

// numericValue extracts numeric values, optionally parsing strings.
func numericValue(value any, parseStrings bool) (float64, bool) {
	switch typed := value.(type) {
	case int:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case float64:
		return typed, true
	case string:
		if !parseStrings {
			return 0, false
		}
		parsed, err := strconv.ParseFloat(strings.TrimSpace(typed), 64)
		return parsed, err == nil
	default:
		return 0, false
	}
}

// compareNumbers compares two numeric values.
func compareNumbers(left float64, right float64) int {
	switch {
	case left < right:
		return -1
	case left > right:
		return 1
	default:
		return 0
	}
}

// sortCandidates sorts query candidates by a metadata or property field.
func sortCandidates(candidates []queryCandidate, field string, order SortOrder) {
	if field == "" {
		sort.Slice(candidates, func(i, j int) bool {
			return candidates[i].node.UpdatedAt.After(candidates[j].node.UpdatedAt)
		})
		return
	}
	sort.Slice(candidates, func(i, j int) bool {
		comparison := compareRowValues(candidates[i].typedField(field), candidates[j].typedField(field))
		if order == SortDescending {
			return comparison > 0
		}
		return comparison < 0
	})
}

// sortMatchCandidates sorts match rows by a requested field.
func sortMatchCandidates(candidates []matchCandidate, field string, order SortOrder) {
	if field == "" {
		sort.Slice(candidates, func(i, j int) bool {
			if candidates[i].from.node.Title != candidates[j].from.node.Title {
				return candidates[i].from.node.Title < candidates[j].from.node.Title
			}
			return candidates[i].to.node.Title < candidates[j].to.node.Title
		})
		return
	}
	sort.Slice(candidates, func(i, j int) bool {
		comparison := compareRowValues(candidates[i].typedField(field), candidates[j].typedField(field))
		if order == SortDescending {
			return comparison > 0
		}
		return comparison < 0
	})
}

// queryValue returns the typed row value for a stored graph property.
func queryValue(value graph.Value) any {
	switch value.Type {
	case graph.ValueText:
		return value.Text
	case graph.ValueBool:
		parsed, err := strconv.ParseBool(value.Text)
		if err != nil {
			return value.Text
		}
		return parsed
	case graph.ValueNumber:
		return value.Number
	case graph.ValueTime:
		if value.Time == nil {
			return ""
		}
		return value.Time.UTC()
	case graph.ValueJSON:
		return value.JSON
	default:
		return ""
	}
}
