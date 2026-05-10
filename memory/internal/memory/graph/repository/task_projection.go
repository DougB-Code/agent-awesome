package repository

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"memory/internal/memory/domain"
)

const taskGraphProjectionSchemaVersion = "task-graph-projection/v1"

// TaskGraphProjection returns a graph-backed task snapshot for UI reads.
func (r *Repository) TaskGraphProjection(ctx context.Context, q domain.TaskGraphProjectionQuery) (domain.TaskGraphProjection, error) {
	q, err := domain.NormalizeTaskGraphProjectionQuery(q)
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	tasks, err := r.ListTasks(ctx, q.Tasks)
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	relations, err := r.projectedTaskRelations(ctx, tasks, q.RelationTypes)
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	nodes := projectedTaskNodes(tasks)
	edges := projectedRelationEdges(relations)
	facets := []domain.TaskGraphProjectionNode{}
	if q.IncludeFacets {
		facets, edges = projectedFacetGraph(tasks, edges)
	}
	return domain.TaskGraphProjection{
		SchemaVersion: taskGraphProjectionSchemaVersion,
		GeneratedAt:   time.Now().UTC(),
		Tasks:         tasks,
		Relations:     relations,
		Nodes:         nodes,
		Edges:         edges,
		Facets:        facets,
		Quality: domain.TaskGraphProjectionQuality{
			TaskCount:        len(tasks),
			RelationCount:    len(relations),
			FacetCount:       len(facets),
			RelationCoverage: projectedRelationCoverage(tasks, relations),
		},
	}, nil
}

// projectedTaskRelations returns visible task-to-task relations for projected tasks.
func (r *Repository) projectedTaskRelations(ctx context.Context, tasks []domain.Task, types []domain.TaskRelationType) ([]domain.TaskRelation, error) {
	taskIDs := map[domain.TaskID]bool{}
	for _, task := range tasks {
		taskIDs[task.ID] = true
	}
	relations, err := r.ListTaskRelations(ctx, domain.TaskRelationQuery{Types: types, Direction: "either", Limit: 500})
	if err != nil {
		return nil, err
	}
	projected := []domain.TaskRelation{}
	for _, relation := range relations {
		if taskIDs[relation.FromTaskID] && taskIDs[relation.ToTaskID] {
			projected = append(projected, relation)
		}
	}
	sort.Slice(projected, func(i, j int) bool {
		if projected[i].FromTaskID != projected[j].FromTaskID {
			return projected[i].FromTaskID < projected[j].FromTaskID
		}
		if projected[i].ToTaskID != projected[j].ToTaskID {
			return projected[i].ToTaskID < projected[j].ToTaskID
		}
		if projected[i].Type != projected[j].Type {
			return projected[i].Type < projected[j].Type
		}
		return projected[i].ID < projected[j].ID
	})
	return projected, nil
}

// projectedTaskNodes converts tasks to graph projection nodes.
func projectedTaskNodes(tasks []domain.Task) []domain.TaskGraphProjectionNode {
	nodes := make([]domain.TaskGraphProjectionNode, 0, len(tasks))
	for _, task := range tasks {
		taskCopy := task
		nodes = append(nodes, domain.TaskGraphProjectionNode{
			ID:     string(task.ID),
			Kind:   "task",
			Label:  task.Title,
			TaskID: task.ID,
			Task:   &taskCopy,
			Properties: map[string]string{
				"status":   string(task.Status),
				"priority": string(task.Priority),
				"project":  task.Project,
				"person":   task.Person,
				"risk":     fmt.Sprintf("%.3g", task.Risk),
				"value":    fmt.Sprintf("%.3g", task.Value),
				"urgency":  fmt.Sprintf("%.3g", task.Urgency),
			},
		})
	}
	return nodes
}

// projectedRelationEdges converts task relations to graph projection edges.
func projectedRelationEdges(relations []domain.TaskRelation) []domain.TaskGraphProjectionEdge {
	edges := make([]domain.TaskGraphProjectionEdge, 0, len(relations))
	for _, relation := range relations {
		relationCopy := relation
		edges = append(edges, domain.TaskGraphProjectionEdge{
			ID:                 string(relation.ID),
			FromNodeID:         string(relation.FromTaskID),
			ToNodeID:           string(relation.ToTaskID),
			Type:               string(relation.Type),
			DirectionSemantics: domain.TaskRelationDirectionSemantics(relation.Type),
			RelationID:         relation.ID,
			Relation:           &relationCopy,
			Confidence:         relation.Confidence,
		})
	}
	return edges
}

// projectedFacetGraph adds project, person, and topic nodes plus membership edges.
func projectedFacetGraph(tasks []domain.Task, edges []domain.TaskGraphProjectionEdge) ([]domain.TaskGraphProjectionNode, []domain.TaskGraphProjectionEdge) {
	facetsByID := map[string]domain.TaskGraphProjectionNode{}
	for _, task := range tasks {
		edges = appendTaskFacet(&facetsByID, edges, task, "project", task.Project)
		edges = appendTaskFacet(&facetsByID, edges, task, "person", task.Person)
		for _, topic := range task.Topics {
			edges = appendTaskFacet(&facetsByID, edges, task, "topic", topic)
		}
	}
	facets := make([]domain.TaskGraphProjectionNode, 0, len(facetsByID))
	for _, facet := range facetsByID {
		facets = append(facets, facet)
	}
	sort.Slice(facets, func(i, j int) bool { return facets[i].ID < facets[j].ID })
	sort.Slice(edges, func(i, j int) bool {
		if edges[i].FromNodeID != edges[j].FromNodeID {
			return edges[i].FromNodeID < edges[j].FromNodeID
		}
		if edges[i].ToNodeID != edges[j].ToNodeID {
			return edges[i].ToNodeID < edges[j].ToNodeID
		}
		if edges[i].Type != edges[j].Type {
			return edges[i].Type < edges[j].Type
		}
		return edges[i].ID < edges[j].ID
	})
	return facets, edges
}

// appendTaskFacet adds one facet membership edge when the value is present.
func appendTaskFacet(facetsByID *map[string]domain.TaskGraphProjectionNode, edges []domain.TaskGraphProjectionEdge, task domain.Task, kind string, value string) []domain.TaskGraphProjectionEdge {
	value = strings.TrimSpace(value)
	if value == "" {
		return edges
	}
	facetID := projectionFacetID(kind, value)
	if _, ok := (*facetsByID)[facetID]; !ok {
		(*facetsByID)[facetID] = domain.TaskGraphProjectionNode{
			ID:    facetID,
			Kind:  kind,
			Label: value,
			Properties: map[string]string{
				"source": "task_projection",
			},
		}
	}
	return append(edges, domain.TaskGraphProjectionEdge{
		ID:         fmt.Sprintf("%s:%s:%s", task.ID, kind, projectionKey(value)),
		FromNodeID: string(task.ID),
		ToNodeID:   facetID,
		Type:       "tagged_with_" + kind,
	})
}

// projectionFacetID returns a deterministic projection node id for a facet.
func projectionFacetID(kind string, value string) string {
	return kind + ":" + projectionKey(value)
}

// projectionKey normalizes a label into a stable projection key.
func projectionKey(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(strings.TrimSpace(value))), "-")
}

// projectedRelationCoverage reports the share of projected tasks with graph relations.
func projectedRelationCoverage(tasks []domain.Task, relations []domain.TaskRelation) float64 {
	if len(tasks) == 0 {
		return 0
	}
	related := map[domain.TaskID]bool{}
	for _, relation := range relations {
		related[relation.FromTaskID] = true
		related[relation.ToTaskID] = true
	}
	return float64(len(related)) / float64(len(tasks))
}
