// This file projects graph query candidates into rows and traversal paths.
package query

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	graph "memory/internal/memory/graph/domain"
)

const maxTraversalCandidates = 1000

// edgeMutationCandidate stores one edge and its property lookup map.
type edgeMutationCandidate struct {
	edge       graph.Edge
	properties map[string]any
}

// row returns selected fields for one edge mutation result.
func (c edgeMutationCandidate) row(fields []string) Row {
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
func (c matchCandidate) row(fields []string) Row {
	return projectorRow(c, fields)
}

// path returns graph path metadata associated with one match row.
func (c matchCandidate) path(rowIndex int) Path {
	return Path{
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
func projectorRow(candidate graphQueryProjector, fields []string) Row {
	row := Row{}
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
func groupCandidateRows[T graphQueryProjector](candidates []T, stmt Statement) []Row {
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
	rows := make([]Row, 0, len(keys))
	for _, key := range keys {
		group := groups[key]
		rows = append(rows, Row{
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
func sortRows(rows []Row, field string, order SortOrder) {
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
func limitRows(rows []Row, limit int) []Row {
	if len(rows) > limit {
		return rows[:limit]
	}
	return rows
}

// projectRows returns only the requested aggregate columns.
func projectRows(rows []Row, fields []string) []Row {
	projected := make([]Row, 0, len(rows))
	for _, row := range rows {
		projectedRow := Row{}
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
func (c queryCandidate) row(fields []string) Row {
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
	case "firewall":
		return string(c.node.Firewall)
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
func queryRowsFromCandidates(candidates []queryCandidate, fields []string) []Row {
	rows := make([]Row, 0, len(candidates))
	for _, candidate := range candidates {
		rows = append(rows, candidate.row(fields))
	}
	return rows
}

// matchRowsAndPaths projects match candidates into result rows and path metadata.
func matchRowsAndPaths(candidates []matchCandidate, fields []string) ([]Row, []Path) {
	rows := make([]Row, 0, len(candidates))
	paths := make([]Path, 0, len(candidates))
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
