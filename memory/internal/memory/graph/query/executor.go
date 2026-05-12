package query

import (
	"context"
	"strings"

	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
)

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
	firewall              graph.Firewall
	includeGlobal         bool
	allowedSensitivities  []graph.Sensitivity
	allowedSensitivitySet map[graph.Sensitivity]bool
}

// executionResult stores rows and optional paths produced by one query.
type executionResult struct {
	rows  []domain.GraphQueryRow
	paths []domain.GraphQueryPath
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

// graphQueryAccessPolicyFromRequest builds graph read policy from public request metadata.
func graphQueryAccessPolicyFromRequest(req domain.GraphQueryRequest) graphQueryAccessPolicy {
	allowed := make([]graph.Sensitivity, 0, len(req.AllowedSensitivities))
	allowedSet := map[graph.Sensitivity]bool{}
	for _, sensitivity := range req.AllowedSensitivities {
		allowed = append(allowed, sensitivity)
		allowedSet[sensitivity] = true
	}
	return graphQueryAccessPolicy{
		firewall:              req.Firewall,
		includeGlobal:         req.IncludeGlobal,
		allowedSensitivities:  allowed,
		allowedSensitivitySet: allowedSet,
	}
}

// canReadNode reports whether a node is visible under the query read policy.
func (p graphQueryAccessPolicy) canReadNode(node graph.Node) bool {
	if node.Status != graph.StatusActive {
		return false
	}
	if node.Firewall != p.firewall && !(p.includeGlobal && node.Firewall == graph.FirewallGlobal) {
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
		Firewall:             policy.firewall,
		IncludeGlobal:        policy.includeGlobal,
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
		Firewall:             policy.firewall,
		IncludeGlobal:        policy.includeGlobal,
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
