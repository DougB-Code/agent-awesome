package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"slices"
	"sort"
	"strings"
	"time"

	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
)

const (
	propertyCanceledAt      = "canceled_at"
	propertyCompletedAt     = "completed_at"
	propertyDescription     = "description"
	propertyDueAt           = "due_at"
	propertyEstimateMinutes = "estimate_minutes"
	propertyFollowUpAt      = "follow_up_at"
	propertyLagMinutes      = "lag_minutes"
	propertyLinkNote        = "note"
	propertyPriority        = "priority"
	propertyScheduledAt     = "scheduled_at"
	propertyStatus          = "status"
	propertyUrgency         = "urgency"
	propertyWorkBreakdown   = "work_breakdown"
)

// taskRelationMapping binds task relation DTOs to graph edge vocabulary.
type taskRelationMapping struct {
	task  domain.TaskRelationType
	graph graph.RelationType
}

// taskMemoryRelationMapping binds task memory link DTOs to graph edges.
type taskMemoryRelationMapping struct {
	task  domain.TaskMemoryRelationship
	graph graph.RelationType
}

var taskRelationMappings = []taskRelationMapping{
	{task: domain.TaskRelationBlocks, graph: graph.RelationBlocks},
	{task: domain.TaskRelationDependsOn, graph: graph.RelationDependsOn},
	{task: domain.TaskRelationEnables, graph: graph.RelationEnables},
	{task: domain.TaskRelationPartOf, graph: graph.RelationPartOf},
	{task: domain.TaskRelationRelated, graph: graph.RelationRelatedTo},
}

var taskMemoryRelationMappings = []taskMemoryRelationMapping{
	{task: domain.TaskMemoryContext, graph: graph.RelationHasContext},
	{task: domain.TaskMemoryOriginatedFrom, graph: graph.RelationSourcedFrom},
	{task: domain.TaskMemorySupporting, graph: graph.RelationSupportedBy},
	{task: domain.TaskMemoryRelated, graph: graph.RelationRelatedTo},
}

// CreateTask stores one operational task as graph facts.
func (r *Repository) CreateTask(ctx context.Context, req domain.CreateTaskRequest) (domain.Task, error) {
	req, err := domain.NormalizeCreateTaskRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	if req.IdempotencyKey != "" {
		if node, err := r.graph.GetNodeByStableKey(ctx, graph.KindTask, taskStableKey(req.IdempotencyKey)); err == nil {
			return r.taskFromNode(ctx, node, true)
		} else if err != sql.ErrNoRows {
			return domain.Task{}, err
		}
	}
	node, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:       graph.KindTask,
		StableKey:  taskStableKey(req.IdempotencyKey),
		Title:      req.Title,
		Summary:    req.Description,
		TrustLevel: graph.TrustUserAsserted,
		Actor:      req.Actor,
	})
	if err != nil {
		return domain.Task{}, err
	}
	if err := r.writeTaskProperties(ctx, node.ID, req, node.CreatedAt); err != nil {
		return domain.Task{}, err
	}
	if err := r.writeTaskFacetEdges(ctx, node.ID, req); err != nil {
		return domain.Task{}, err
	}
	for _, link := range req.MemoryLinks {
		if _, err := r.LinkTaskMemory(ctx, domain.LinkTaskMemoryRequest{TaskID: domain.TaskID(node.ID), DomainID: req.DomainID, Link: link}); err != nil {
			return domain.Task{}, err
		}
	}
	if err := r.graph.ReindexNode(ctx, node.ID); err != nil {
		return domain.Task{}, err
	}
	if _, err := r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "create_task",
		Actor:         req.Actor,
		SubjectNodeID: node.ID,
		Message:       "created graph-backed task",
	}); err != nil {
		return domain.Task{}, err
	}
	return r.taskFromNode(ctx, node, true)
}

// GetTask returns one graph-backed task.
func (r *Repository) GetTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	req, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	node, err := r.taskNode(ctx, req.TaskID)
	if err != nil {
		return domain.Task{}, err
	}
	return r.taskFromNode(ctx, node, true)
}

// ListTasks returns graph-backed tasks matching filters.
func (r *Repository) ListTasks(ctx context.Context, q domain.TaskQuery) ([]domain.Task, error) {
	q, err := domain.NormalizeTaskQuery(q)
	if err != nil {
		return nil, err
	}
	nodes, err := r.graph.SearchNodes(ctx, graph.SearchNodesQuery{
		Text:  q.Search,
		Kinds: []graph.NodeKind{graph.KindTask},
		Limit: 100,
	})
	if err != nil {
		return nil, err
	}
	tasks := []domain.Task{}
	for _, node := range nodes {
		task, err := r.taskFromNode(ctx, node, q.IncludeLinks)
		if err != nil {
			return nil, err
		}
		if !taskMatches(task, q) {
			continue
		}
		tasks = append(tasks, task)
		if len(tasks) >= q.Limit {
			break
		}
	}
	sort.Slice(tasks, func(i, j int) bool {
		left := taskSortTime(tasks[i])
		right := taskSortTime(tasks[j])
		if !left.Equal(right) {
			return left.Before(right)
		}
		return tasks[i].Title < tasks[j].Title
	})
	return tasks, nil
}

// UpdateTask patches graph facts for one operational task.
func (r *Repository) UpdateTask(ctx context.Context, req domain.UpdateTaskRequest) (domain.Task, error) {
	req, err := domain.NormalizeUpdateTaskRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	node, err := r.taskNode(ctx, req.TaskID)
	if err != nil {
		return domain.Task{}, err
	}
	title := node.Title
	summary := node.Summary
	if req.Title != nil {
		title = *req.Title
	}
	if req.Description != nil {
		summary = *req.Description
	}
	if title != node.Title || summary != node.Summary {
		node, err = r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
			NodeID:       node.ID,
			Kind:         node.Kind,
			StableKey:    node.StableKey,
			Title:        title,
			Summary:      summary,
			Status:       node.Status,
			Sensitivity:  node.Sensitivity,
			TrustLevel:   node.TrustLevel,
			Confidence:   node.Confidence,
			SourceNodeID: node.SourceNodeID,
			Actor:        req.Actor,
		})
		if err != nil {
			return domain.Task{}, err
		}
	}
	if err := r.writeTaskPatchProperties(ctx, node.ID, req); err != nil {
		return domain.Task{}, err
	}
	if err := r.writeTaskPatchFacets(ctx, node.ID, req); err != nil {
		return domain.Task{}, err
	}
	if err := r.graph.ReindexNode(ctx, node.ID); err != nil {
		return domain.Task{}, err
	}
	if _, err := r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "update_task",
		Actor:         req.Actor,
		SubjectNodeID: node.ID,
		Message:       "updated graph-backed task",
	}); err != nil {
		return domain.Task{}, err
	}
	return r.GetTask(ctx, domain.TaskIDRequest{TaskID: req.TaskID, Actor: req.Actor, DomainID: req.DomainID})
}

// CompleteTask marks one graph-backed task done.
func (r *Repository) CompleteTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	req, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	status := domain.TaskStatusDone
	return r.UpdateTask(ctx, domain.UpdateTaskRequest{TaskID: req.TaskID, Actor: req.Actor, DomainID: req.DomainID, Status: &status})
}

// CancelTask marks one graph-backed task canceled.
func (r *Repository) CancelTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	req, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	status := domain.TaskStatusCanceled
	return r.UpdateTask(ctx, domain.UpdateTaskRequest{TaskID: req.TaskID, Actor: req.Actor, DomainID: req.DomainID, Status: &status})
}

// DeleteTask lifecycle-deletes one graph-backed task node.
func (r *Repository) DeleteTask(ctx context.Context, req domain.TaskIDRequest) error {
	req, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return err
	}
	node, err := r.taskNode(ctx, req.TaskID)
	if err != nil {
		return err
	}
	if _, err := r.graph.SetNodeStatus(ctx, node.ID, graph.StatusDeleted, req.Actor); err != nil {
		return err
	}
	_, err = r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "delete_task",
		Actor:         req.Actor,
		SubjectNodeID: node.ID,
		Message:       "deleted graph-backed task",
	})
	return err
}

// LinkTaskMemory attaches contextual memory to a graph-backed task.
func (r *Repository) LinkTaskMemory(ctx context.Context, req domain.LinkTaskMemoryRequest) (domain.MemoryLink, error) {
	req, err := domain.NormalizeLinkTaskMemoryRequest(req)
	if err != nil {
		return domain.MemoryLink{}, err
	}
	task, err := r.graph.GetNode(ctx, graph.NodeID(req.TaskID))
	if err != nil {
		return domain.MemoryLink{}, err
	}
	if task.Kind != graph.KindTask {
		return domain.MemoryLink{}, sql.ErrNoRows
	}
	targetID := graph.NodeID(req.Link.MemoryID)
	if targetID == "" {
		targetID = graph.NodeID(req.Link.MemoryEvidenceID)
	}
	sourceID := graph.NodeID(req.Link.MemoryEvidenceID)
	if sourceID == "" {
		sourceID = targetID
	}
	edge, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID:   task.ID,
		Type:         taskMemoryRelation(req.Link.Relationship),
		ToNodeID:     targetID,
		SourceNodeID: sourceID,
		Actor:        task.Actor,
	})
	if err != nil {
		return domain.MemoryLink{}, err
	}
	if req.Link.Note != "" {
		if _, err := r.graph.UpsertEdgeProperty(ctx, graph.UpsertEdgePropertyRequest{
			EdgeID: edge.ID,
			Key:    propertyLinkNote,
			Value:  graph.Value{Type: graph.ValueText, Text: req.Link.Note},
			Actor:  task.Actor,
		}); err != nil {
			return domain.MemoryLink{}, err
		}
	}
	return r.memoryLinkFromEdge(ctx, edge)
}

// ListTaskRelations returns directed task-to-task graph edges.
func (r *Repository) ListTaskRelations(ctx context.Context, q domain.TaskRelationQuery) ([]domain.TaskRelation, error) {
	q, err := domain.NormalizeTaskRelationQuery(q)
	if err != nil {
		return nil, err
	}
	types := taskRelationGraphTypes(q.Types)
	edges := []graph.Edge{}
	if q.TaskID == "" {
		edges, err = r.graph.ListEdges(ctx, types, q.Limit*4)
	} else {
		if _, err := r.taskNode(ctx, q.TaskID); err != nil {
			return nil, err
		}
		edges, err = r.taskRelationEdgesForTask(ctx, graph.NodeID(q.TaskID), types, q.Direction)
	}
	if err != nil {
		return nil, err
	}
	relations := []domain.TaskRelation{}
	seen := map[graph.EdgeID]bool{}
	for _, edge := range edges {
		if seen[edge.ID] {
			continue
		}
		seen[edge.ID] = true
		relation, ok, err := r.taskRelationFromEdge(ctx, edge)
		if err != nil {
			return nil, err
		}
		if !ok {
			continue
		}
		relations = append(relations, relation)
		if len(relations) >= q.Limit {
			break
		}
	}
	return relations, nil
}

// TraverseTaskRelations returns bounded paths through directed task relation edges.
func (r *Repository) TraverseTaskRelations(ctx context.Context, q domain.TaskRelationTraversalQuery) (domain.TaskRelationTraversal, error) {
	q, err := domain.NormalizeTaskRelationTraversalQuery(q)
	if err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	if _, err := r.taskNode(ctx, q.RootTaskID); err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	walker := taskRelationWalker{
		repo:  r,
		query: q,
		paths: []domain.TaskRelationPath{},
	}
	state := taskRelationPathState{
		taskIDs: []domain.TaskID{q.RootTaskID},
		seen:    map[domain.TaskID]bool{q.RootTaskID: true},
	}
	if err := walker.walk(ctx, q.RootTaskID, state); err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	return domain.TaskRelationTraversal{
		RootTaskID: q.RootTaskID,
		Types:      normalizedTaskRelationTypes(q.Types),
		Direction:  q.Direction,
		MaxDepth:   q.MaxDepth,
		Paths:      walker.paths,
	}, nil
}

// UpsertTaskRelation creates or updates a directed task relationship edge.
func (r *Repository) UpsertTaskRelation(ctx context.Context, req domain.UpsertTaskRelationRequest) (domain.TaskRelation, error) {
	req, err := domain.NormalizeUpsertTaskRelationRequest(req)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	from, err := r.taskNode(ctx, req.FromTaskID)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	to, err := r.taskNode(ctx, req.ToTaskID)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	edge, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID: from.ID,
		Type:       taskRelationGraphType(req.Type),
		ToNodeID:   to.ID,
		Confidence: req.Confidence,
		Actor:      req.Actor,
	})
	if err != nil {
		return domain.TaskRelation{}, err
	}
	if _, err := r.graph.UpsertEdgeProperty(ctx, graph.UpsertEdgePropertyRequest{
		EdgeID: edge.ID,
		Key:    propertyLinkNote,
		Value:  graph.Value{Type: graph.ValueText, Text: req.Note},
		Actor:  req.Actor,
	}); err != nil {
		return domain.TaskRelation{}, err
	}
	if _, err := r.graph.UpsertEdgeProperty(ctx, graph.UpsertEdgePropertyRequest{
		EdgeID: edge.ID,
		Key:    propertyLagMinutes,
		Value:  graph.Value{Type: graph.ValueNumber, Number: float64(req.LagMinutes)},
		Actor:  req.Actor,
	}); err != nil {
		return domain.TaskRelation{}, err
	}
	if _, err := r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "upsert_task_relation",
		Actor:         req.Actor,
		SubjectEdgeID: edge.ID,
		Message:       "upserted graph-backed task relation",
	}); err != nil {
		return domain.TaskRelation{}, err
	}
	relation, ok, err := r.taskRelationFromEdge(ctx, edge)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	if !ok {
		return domain.TaskRelation{}, sql.ErrNoRows
	}
	return relation, nil
}

// DeleteTaskRelation lifecycle-deletes one directed task relationship edge.
func (r *Repository) DeleteTaskRelation(ctx context.Context, req domain.DeleteTaskRelationRequest) error {
	req, err := domain.NormalizeDeleteTaskRelationRequest(req)
	if err != nil {
		return err
	}
	edge, err := r.graph.GetEdge(ctx, graph.EdgeID(req.RelationID))
	if err != nil {
		return err
	}
	if _, ok, err := r.taskRelationFromEdge(ctx, edge); err != nil || !ok {
		if err != nil {
			return err
		}
		return sql.ErrNoRows
	}
	if _, err := r.graph.SetEdgeStatus(ctx, edge.ID, graph.StatusDeleted, req.Actor); err != nil {
		return err
	}
	_, err = r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "delete_task_relation",
		Actor:         req.Actor,
		SubjectEdgeID: edge.ID,
		Message:       "deleted graph-backed task relation",
	})
	return err
}

// writeTaskProperties stores scalar task facts as typed graph properties.
func (r *Repository) writeTaskProperties(ctx context.Context, nodeID graph.NodeID, req domain.CreateTaskRequest, createdAt time.Time) error {
	properties := []graph.UpsertNodePropertyRequest{
		taskTextProperty(nodeID, propertyDescription, req.Description, req.Actor),
		taskTextProperty(nodeID, propertyStatus, string(req.Status), req.Actor),
		taskTextProperty(nodeID, propertyPriority, string(req.Priority), req.Actor),
		taskNumberProperty(nodeID, propertyEstimateMinutes, float64(req.EstimateMinutes), req.Actor),
		taskNumberProperty(nodeID, propertyUrgency, req.Urgency, req.Actor),
	}
	if req.IdempotencyKey != "" {
		properties = append(properties, taskTextProperty(nodeID, propertyIdempotencyKey, req.IdempotencyKey, req.Actor))
	}
	if req.DueAt != nil {
		properties = append(properties, taskTimeProperty(nodeID, propertyDueAt, req.DueAt, req.Actor))
	}
	if req.ScheduledAt != nil {
		properties = append(properties, taskTimeProperty(nodeID, propertyScheduledAt, req.ScheduledAt, req.Actor))
	}
	if req.FollowUpAt != nil {
		properties = append(properties, taskTimeProperty(nodeID, propertyFollowUpAt, req.FollowUpAt, req.Actor))
	}
	if domain.TaskWorkBreakdownHasContent(req.WorkBreakdown) {
		property, err := taskWorkBreakdownProperty(nodeID, req.WorkBreakdown, req.Actor)
		if err != nil {
			return err
		}
		properties = append(properties, property)
	}
	if req.Status == domain.TaskStatusDone {
		properties = append(properties, taskTimeProperty(nodeID, propertyCompletedAt, &createdAt, req.Actor))
	}
	if req.Status == domain.TaskStatusCanceled {
		properties = append(properties, taskTimeProperty(nodeID, propertyCanceledAt, &createdAt, req.Actor))
	}
	for _, property := range properties {
		if emptyTaskProperty(property) {
			continue
		}
		if _, err := r.graph.UpsertNodeProperty(ctx, property); err != nil {
			return err
		}
	}
	return nil
}

// writeTaskPatchProperties stores scalar task changes as typed graph properties.
func (r *Repository) writeTaskPatchProperties(ctx context.Context, nodeID graph.NodeID, req domain.UpdateTaskRequest) error {
	if req.Description != nil {
		if err := r.upsertTaskProperty(ctx, taskTextProperty(nodeID, propertyDescription, *req.Description, req.Actor)); err != nil {
			return err
		}
	}
	if req.Status != nil {
		if err := r.upsertTaskProperty(ctx, taskTextProperty(nodeID, propertyStatus, string(*req.Status), req.Actor)); err != nil {
			return err
		}
		now := time.Now().UTC()
		switch *req.Status {
		case domain.TaskStatusDone:
			if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyCompletedAt, &now, req.Actor)); err != nil {
				return err
			}
			if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyCanceledAt, nil, req.Actor)); err != nil {
				return err
			}
		case domain.TaskStatusCanceled:
			if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyCanceledAt, &now, req.Actor)); err != nil {
				return err
			}
			if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyCompletedAt, nil, req.Actor)); err != nil {
				return err
			}
		default:
			if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyCompletedAt, nil, req.Actor)); err != nil {
				return err
			}
			if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyCanceledAt, nil, req.Actor)); err != nil {
				return err
			}
		}
	}
	if req.Priority != nil {
		if err := r.upsertTaskProperty(ctx, taskTextProperty(nodeID, propertyPriority, string(*req.Priority), req.Actor)); err != nil {
			return err
		}
	}
	if req.DueAt != nil || req.ClearDueAt {
		if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyDueAt, req.DueAt, req.Actor)); err != nil {
			return err
		}
	}
	if req.ScheduledAt != nil || req.ClearScheduledAt {
		if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyScheduledAt, req.ScheduledAt, req.Actor)); err != nil {
			return err
		}
	}
	if req.FollowUpAt != nil || req.ClearFollowUpAt {
		if err := r.upsertTaskProperty(ctx, taskTimeProperty(nodeID, propertyFollowUpAt, req.FollowUpAt, req.Actor)); err != nil {
			return err
		}
	}
	if req.EstimateMinutes != nil {
		if err := r.upsertTaskProperty(ctx, taskNumberProperty(nodeID, propertyEstimateMinutes, float64(*req.EstimateMinutes), req.Actor)); err != nil {
			return err
		}
	}
	numberProperties := []struct {
		key   string
		value *float64
	}{
		{key: propertyUrgency, value: req.Urgency},
	}
	for _, property := range numberProperties {
		if property.value == nil {
			continue
		}
		if err := r.upsertTaskProperty(ctx, taskNumberProperty(nodeID, property.key, *property.value, req.Actor)); err != nil {
			return err
		}
	}
	if req.WorkBreakdown != nil {
		property, err := taskWorkBreakdownProperty(nodeID, *req.WorkBreakdown, req.Actor)
		if err != nil {
			return err
		}
		if err := r.upsertTaskProperty(ctx, property); err != nil {
			return err
		}
	}
	return nil
}

// upsertTaskProperty writes one task property without treating zero as empty.
func (r *Repository) upsertTaskProperty(ctx context.Context, req graph.UpsertNodePropertyRequest) error {
	_, err := r.graph.UpsertNodeProperty(ctx, req)
	return err
}

// writeTaskFacetEdges stores task relationships to topic and entity nodes.
func (r *Repository) writeTaskFacetEdges(ctx context.Context, taskID graph.NodeID, req domain.CreateTaskRequest) error {
	for _, topic := range req.Topics {
		node, err := r.upsertFacetNode(ctx, graph.KindTopic, "topic:"+topic, topic, req.Actor)
		if err != nil {
			return err
		}
		if _, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{FromNodeID: taskID, Type: graph.RelationTaggedWith, ToNodeID: node.ID, Actor: req.Actor}); err != nil {
			return err
		}
	}
	facets := []struct {
		kind     graph.NodeKind
		stable   string
		title    string
		relation graph.RelationType
	}{
		{kind: graph.KindProject, stable: "project:" + strings.ToLower(req.Project), title: req.Project, relation: graph.RelationPartOf},
		{kind: graph.KindPerson, stable: "person:" + strings.ToLower(req.Person), title: req.Person, relation: graph.RelationAssignedTo},
		{kind: graph.KindLocation, stable: "location:" + strings.ToLower(req.Location), title: req.Location, relation: graph.RelationLocatedAt},
	}
	for _, facet := range facets {
		if strings.TrimSpace(facet.title) == "" {
			continue
		}
		node, err := r.upsertFacetNode(ctx, facet.kind, facet.stable, facet.title, req.Actor)
		if err != nil {
			return err
		}
		if _, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{FromNodeID: taskID, Type: facet.relation, ToNodeID: node.ID, Actor: req.Actor}); err != nil {
			return err
		}
	}
	return nil
}

// writeTaskPatchFacets replaces requested task facet edges.
func (r *Repository) writeTaskPatchFacets(ctx context.Context, taskID graph.NodeID, req domain.UpdateTaskRequest) error {
	if req.Topics != nil {
		if err := r.replaceTaskFacetEdges(ctx, taskID, graph.RelationTaggedWith, graph.KindTopic, req.Actor); err != nil {
			return err
		}
		for _, topic := range req.Topics {
			if err := r.writeTaskFacetEdge(ctx, taskID, graph.KindTopic, "topic:"+topic, topic, graph.RelationTaggedWith, req.Actor); err != nil {
				return err
			}
		}
	}
	facets := []struct {
		kind     graph.NodeKind
		stable   string
		title    *string
		relation graph.RelationType
	}{
		{kind: graph.KindProject, stable: "project:", title: req.Project, relation: graph.RelationPartOf},
		{kind: graph.KindPerson, stable: "person:", title: req.Person, relation: graph.RelationAssignedTo},
		{kind: graph.KindLocation, stable: "location:", title: req.Location, relation: graph.RelationLocatedAt},
	}
	for _, facet := range facets {
		if facet.title == nil {
			continue
		}
		if err := r.replaceTaskFacetEdges(ctx, taskID, facet.relation, facet.kind, req.Actor); err != nil {
			return err
		}
		if strings.TrimSpace(*facet.title) == "" {
			continue
		}
		stable := facet.stable + strings.ToLower(strings.TrimSpace(*facet.title))
		if err := r.writeTaskFacetEdge(ctx, taskID, facet.kind, stable, *facet.title, facet.relation, req.Actor); err != nil {
			return err
		}
	}
	return nil
}

// writeTaskFacetEdge stores one edge from a task to a facet node.
func (r *Repository) writeTaskFacetEdge(ctx context.Context, taskID graph.NodeID, kind graph.NodeKind, stableKey string, title string, relation graph.RelationType, actor string) error {
	node, err := r.upsertFacetNode(ctx, kind, stableKey, title, actor)
	if err != nil {
		return err
	}
	_, err = r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{FromNodeID: taskID, Type: relation, ToNodeID: node.ID, Actor: actor})
	return err
}

// replaceTaskFacetEdges archives active facet edges without touching task-to-task or memory edges.
func (r *Repository) replaceTaskFacetEdges(ctx context.Context, taskID graph.NodeID, relation graph.RelationType, targetKind graph.NodeKind, actor string) error {
	edges, err := r.graph.ListOutgoingEdges(ctx, taskID, []graph.RelationType{relation})
	if err != nil {
		return err
	}
	for _, edge := range edges {
		target, err := r.graph.GetNode(ctx, edge.ToNodeID)
		if err != nil {
			return err
		}
		if target.Kind != targetKind {
			continue
		}
		if _, err := r.graph.SetEdgeStatus(ctx, edge.ID, graph.StatusArchived, actor); err != nil {
			return err
		}
	}
	return nil
}

// upsertFacetNode creates or reuses one graph facet node.
func (r *Repository) upsertFacetNode(ctx context.Context, kind graph.NodeKind, stableKey string, title string, actor string) (graph.Node, error) {
	return r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:      kind,
		StableKey: stableKey,
		Title:     strings.TrimSpace(title),
		Actor:     actor,
	})
}

// taskNode loads an active graph task node.
func (r *Repository) taskNode(ctx context.Context, taskID domain.TaskID) (graph.Node, error) {
	node, err := r.graph.GetNode(ctx, graph.NodeID(taskID))
	if err != nil {
		return graph.Node{}, err
	}
	if node.Kind != graph.KindTask || node.Status == graph.StatusDeleted {
		return graph.Node{}, sql.ErrNoRows
	}
	return node, nil
}

// taskFromNode projects one graph task node into the task DTO.
func (r *Repository) taskFromNode(ctx context.Context, node graph.Node, includeLinks bool) (domain.Task, error) {
	properties, err := r.propertyMap(ctx, node.ID)
	if err != nil {
		return domain.Task{}, err
	}
	task := domain.Task{
		ID:              domain.TaskID(node.ID),
		Title:           node.Title,
		Description:     propertyText(properties[propertyDescription], node.Summary),
		Status:          domain.TaskStatus(propertyText(properties[propertyStatus], string(domain.TaskStatusOpen))),
		Priority:        domain.TaskPriority(propertyText(properties[propertyPriority], string(domain.TaskPriorityNormal))),
		DueAt:           propertyTime(properties[propertyDueAt]),
		ScheduledAt:     propertyTime(properties[propertyScheduledAt]),
		FollowUpAt:      propertyTime(properties[propertyFollowUpAt]),
		EstimateMinutes: int(propertyNumber(properties[propertyEstimateMinutes])),
		Urgency:         propertyNumber(properties[propertyUrgency]),
		Actor:           node.Actor,
		IdempotencyKey:  propertyText(properties[propertyIdempotencyKey], ""),
		CreatedAt:       node.CreatedAt,
		UpdatedAt:       node.UpdatedAt,
		CompletedAt:     propertyTime(properties[propertyCompletedAt]),
		CanceledAt:      propertyTime(properties[propertyCanceledAt]),
		WorkBreakdown:   taskWorkBreakdownFromProperty(properties[propertyWorkBreakdown]),
	}
	task.Topics, err = r.edgeNodeTitles(ctx, node.ID, graph.RelationTaggedWith)
	if err != nil {
		return domain.Task{}, err
	}
	task.Project = firstTitleOfKind(ctx, r, node.ID, graph.RelationPartOf, graph.KindProject)
	task.Person = firstTitleOfKind(ctx, r, node.ID, graph.RelationAssignedTo, graph.KindPerson)
	task.Location = firstTitleOfKind(ctx, r, node.ID, graph.RelationLocatedAt, graph.KindLocation)
	task.Overdue = task.DueAt != nil && task.DueAt.Before(time.Now().UTC()) && !domain.TerminalTaskStatus(task.Status)
	task.Risk = domain.CalculateTaskRisk(task, time.Now().UTC())
	if includeLinks {
		task.MemoryLinks, err = r.taskMemoryLinks(ctx, node.ID)
		if err != nil {
			return domain.Task{}, err
		}
	}
	return task, nil
}

// taskMemoryLinks returns memory links attached to a task.
func (r *Repository) taskMemoryLinks(ctx context.Context, taskID graph.NodeID) ([]domain.MemoryLink, error) {
	relations := []graph.RelationType{graph.RelationSourcedFrom, graph.RelationHasContext, graph.RelationSupportedBy, graph.RelationRelatedTo}
	links := []domain.MemoryLink{}
	for _, relation := range relations {
		edges, err := r.graph.ListOutgoingEdges(ctx, taskID, []graph.RelationType{relation})
		if err != nil {
			return nil, err
		}
		for _, edge := range edges {
			link, err := r.memoryLinkFromEdge(ctx, edge)
			if err != nil {
				return nil, err
			}
			if link.MemoryID == "" && link.MemoryEvidenceID == "" {
				continue
			}
			links = append(links, link)
		}
	}
	sort.Slice(links, func(i, j int) bool { return links[i].CreatedAt.Before(links[j].CreatedAt) })
	return links, nil
}

// memoryLinkFromEdge projects one graph edge into a task memory link.
func (r *Repository) memoryLinkFromEdge(ctx context.Context, edge graph.Edge) (domain.MemoryLink, error) {
	link := domain.MemoryLink{
		ID:           string(edge.ID),
		Relationship: taskMemoryRelationship(edge.Type),
		CreatedAt:    edge.CreatedAt,
	}
	properties, err := r.graph.ListEdgeProperties(ctx, edge.ID)
	if err != nil {
		return domain.MemoryLink{}, err
	}
	for _, property := range properties {
		if property.Key == propertyLinkNote && property.Value.Type == graph.ValueText {
			link.Note = property.Value.Text
		}
	}
	target, err := r.graph.GetNode(ctx, edge.ToNodeID)
	if err != nil {
		return domain.MemoryLink{}, err
	}
	if target.Kind == graph.KindMemory {
		link.MemoryID = string(target.ID)
	} else if target.Kind == graph.KindEvidence {
		link.MemoryEvidenceID = string(target.ID)
	}
	if edge.SourceNodeID != "" {
		link.MemoryEvidenceID = string(edge.SourceNodeID)
	}
	return link, nil
}

// firstTitleOfKind returns the first target title for a relation and node kind.
func firstTitleOfKind(ctx context.Context, r *Repository, nodeID graph.NodeID, relation graph.RelationType, kind graph.NodeKind) string {
	edges, err := r.graph.ListOutgoingEdges(ctx, nodeID, []graph.RelationType{relation})
	if err != nil {
		return ""
	}
	for _, edge := range edges {
		target, err := r.graph.GetNode(ctx, edge.ToNodeID)
		if err != nil {
			return ""
		}
		if target.Kind == kind {
			return target.Title
		}
	}
	return ""
}

// taskMatches reports whether task satisfies a task query.
func taskMatches(task domain.Task, q domain.TaskQuery) bool {
	if !q.IncludeDone && domain.TerminalTaskStatus(task.Status) {
		return false
	}
	if len(q.Statuses) > 0 && !slices.Contains(q.Statuses, task.Status) {
		return false
	}
	if len(q.Priorities) > 0 && !slices.Contains(q.Priorities, task.Priority) {
		return false
	}
	for _, topic := range q.Topics {
		if !slices.Contains(task.Topics, topic) {
			return false
		}
	}
	if q.OverdueOnly && !task.Overdue {
		return false
	}
	return true
}

// taskSortTime returns the best task ordering time.
func taskSortTime(task domain.Task) time.Time {
	if task.DueAt != nil {
		return *task.DueAt
	}
	if task.ScheduledAt != nil {
		return *task.ScheduledAt
	}
	if task.FollowUpAt != nil {
		return *task.FollowUpAt
	}
	return task.CreatedAt
}

// taskStableKey returns an idempotent stable key for task creation.
func taskStableKey(key string) string {
	return idempotencyStableKey("task", key)
}

// taskTextProperty creates one text task property request.
func taskTextProperty(nodeID graph.NodeID, key string, value string, actor string) graph.UpsertNodePropertyRequest {
	return graph.UpsertNodePropertyRequest{NodeID: nodeID, Key: key, Value: graph.Value{Type: graph.ValueText, Text: value}, Actor: actor}
}

// taskNumberProperty creates one numeric task property request.
func taskNumberProperty(nodeID graph.NodeID, key string, value float64, actor string) graph.UpsertNodePropertyRequest {
	return graph.UpsertNodePropertyRequest{NodeID: nodeID, Key: key, Value: graph.Value{Type: graph.ValueNumber, Number: value}, Actor: actor}
}

// taskTimeProperty creates one time task property request.
func taskTimeProperty(nodeID graph.NodeID, key string, value *time.Time, actor string) graph.UpsertNodePropertyRequest {
	return graph.UpsertNodePropertyRequest{NodeID: nodeID, Key: key, Value: graph.Value{Type: graph.ValueTime, Time: value}, Actor: actor}
}

// taskWorkBreakdownProperty stores WBS metadata as one structured graph fact.
func taskWorkBreakdownProperty(nodeID graph.NodeID, value domain.TaskWorkBreakdown, actor string) (graph.UpsertNodePropertyRequest, error) {
	bytes, err := json.Marshal(value)
	if err != nil {
		return graph.UpsertNodePropertyRequest{}, err
	}
	return graph.UpsertNodePropertyRequest{NodeID: nodeID, Key: propertyWorkBreakdown, Value: graph.Value{Type: graph.ValueJSON, JSON: string(bytes)}, Actor: actor}, nil
}

// emptyTaskProperty reports whether a property carries no useful value.
func emptyTaskProperty(property graph.UpsertNodePropertyRequest) bool {
	switch property.Value.Type {
	case graph.ValueText:
		return strings.TrimSpace(property.Value.Text) == ""
	case graph.ValueNumber:
		return property.Value.Number == 0
	case graph.ValueTime:
		return property.Value.Time == nil
	case graph.ValueJSON:
		return strings.TrimSpace(property.Value.JSON) == "" ||
			strings.TrimSpace(property.Value.JSON) == "{}"
	default:
		return false
	}
}

// taskWorkBreakdownFromProperty decodes WBS metadata from one graph property.
func taskWorkBreakdownFromProperty(property graph.NodeProperty) domain.TaskWorkBreakdown {
	if property.Value.Type != graph.ValueJSON ||
		strings.TrimSpace(property.Value.JSON) == "" {
		return domain.TaskWorkBreakdown{}
	}
	var workBreakdown domain.TaskWorkBreakdown
	if err := json.Unmarshal([]byte(property.Value.JSON), &workBreakdown); err != nil {
		return domain.TaskWorkBreakdown{}
	}
	return domain.NormalizeTaskWorkBreakdown(workBreakdown)
}

// propertyNumber returns a numeric property value.
func propertyNumber(property graph.NodeProperty) float64 {
	if property.Value.Type != graph.ValueNumber {
		return 0
	}
	return property.Value.Number
}

// propertyTime returns a time property value.
func propertyTime(property graph.NodeProperty) *time.Time {
	if property.Value.Type != graph.ValueTime {
		return nil
	}
	return property.Value.Time
}

// taskMemoryRelation maps task memory relationship vocabulary to graph edges.
func taskMemoryRelation(relationship domain.TaskMemoryRelationship) graph.RelationType {
	for _, mapping := range taskMemoryRelationMappings {
		if mapping.task == relationship {
			return mapping.graph
		}
	}
	return graph.RelationRelatedTo
}

// taskRelationPathState stores traversal state for one path branch.
type taskRelationPathState struct {
	taskIDs     []domain.TaskID
	relationIDs []domain.TaskRelationID
	relations   []domain.TaskRelation
	seen        map[domain.TaskID]bool
}

// taskRelationWalker performs bounded graph traversal over task relations.
type taskRelationWalker struct {
	repo  *Repository
	query domain.TaskRelationTraversalQuery
	paths []domain.TaskRelationPath
}

// walk follows adjacent task relations until leaves, cycles, depth, or limits.
func (w *taskRelationWalker) walk(ctx context.Context, current domain.TaskID, state taskRelationPathState) error {
	if len(w.paths) >= w.query.Limit {
		return nil
	}
	if len(state.relations) >= w.query.MaxDepth {
		return w.appendPath(ctx, state, false)
	}
	relations, err := w.repo.ListTaskRelations(ctx, domain.TaskRelationQuery{
		TaskID:    current,
		Types:     w.query.Types,
		Direction: w.query.Direction,
		Limit:     w.query.Limit,
	})
	if err != nil {
		return err
	}
	relations = sortTraversalRelations(relations, current, w.query.Direction)
	if len(relations) == 0 {
		if len(state.relations) == 0 {
			return nil
		}
		return w.appendPath(ctx, state, false)
	}
	for _, relation := range relations {
		if len(w.paths) >= w.query.Limit {
			return nil
		}
		next, ok := nextTraversalTaskID(relation, current, w.query.Direction)
		if !ok {
			continue
		}
		nextState := state.extend(relation, next)
		if state.seen[next] {
			if err := w.appendPath(ctx, nextState, true); err != nil {
				return err
			}
			continue
		}
		nextState.seen[next] = true
		if err := w.walk(ctx, next, nextState); err != nil {
			return err
		}
	}
	return nil
}

// appendPath stores one terminal traversal path.
func (w *taskRelationWalker) appendPath(ctx context.Context, state taskRelationPathState, cycle bool) error {
	path := domain.TaskRelationPath{
		RootTaskID:  w.query.RootTaskID,
		TaskIDs:     append([]domain.TaskID{}, state.taskIDs...),
		RelationIDs: append([]domain.TaskRelationID{}, state.relationIDs...),
		Relations:   append([]domain.TaskRelation{}, state.relations...),
		Depth:       len(state.relations),
		Cycle:       cycle,
	}
	if w.query.IncludeTasks {
		for _, taskID := range state.taskIDs {
			task, err := w.repo.GetTask(ctx, domain.TaskIDRequest{TaskID: taskID})
			if err != nil {
				return err
			}
			if !w.query.IncludeLinks {
				task.MemoryLinks = nil
			}
			path.Tasks = append(path.Tasks, task)
		}
	}
	w.paths = append(w.paths, path)
	return nil
}

// extend returns a copied path state with one additional relation step.
func (s taskRelationPathState) extend(relation domain.TaskRelation, next domain.TaskID) taskRelationPathState {
	return taskRelationPathState{
		taskIDs:     append(append([]domain.TaskID{}, s.taskIDs...), next),
		relationIDs: append(append([]domain.TaskRelationID{}, s.relationIDs...), relation.ID),
		relations:   append(append([]domain.TaskRelation{}, s.relations...), relation),
		seen:        cloneTaskSeen(s.seen),
	}
}

// cloneTaskSeen copies traversal cycle state for one branch.
func cloneTaskSeen(input map[domain.TaskID]bool) map[domain.TaskID]bool {
	output := make(map[domain.TaskID]bool, len(input))
	for key, value := range input {
		output[key] = value
	}
	return output
}

// sortTraversalRelations produces deterministic traversal output.
func sortTraversalRelations(relations []domain.TaskRelation, current domain.TaskID, direction string) []domain.TaskRelation {
	sorted := append([]domain.TaskRelation{}, relations...)
	sort.Slice(sorted, func(i, j int) bool {
		leftNext, _ := nextTraversalTaskID(sorted[i], current, direction)
		rightNext, _ := nextTraversalTaskID(sorted[j], current, direction)
		if leftNext != rightNext {
			return leftNext < rightNext
		}
		if sorted[i].Type != sorted[j].Type {
			return sorted[i].Type < sorted[j].Type
		}
		return sorted[i].ID < sorted[j].ID
	})
	return sorted
}

// nextTraversalTaskID returns the adjacent task reached by a traversal step.
func nextTraversalTaskID(relation domain.TaskRelation, current domain.TaskID, direction string) (domain.TaskID, bool) {
	switch direction {
	case "incoming":
		if relation.ToTaskID == current {
			return relation.FromTaskID, true
		}
	case "either":
		if relation.FromTaskID == current {
			return relation.ToTaskID, true
		}
		if relation.ToTaskID == current {
			return relation.FromTaskID, true
		}
	default:
		if relation.FromTaskID == current {
			return relation.ToTaskID, true
		}
	}
	return "", false
}

// taskRelationEdgesForTask returns task relation edges adjacent to one task.
func (r *Repository) taskRelationEdgesForTask(ctx context.Context, taskID graph.NodeID, types []graph.RelationType, direction string) ([]graph.Edge, error) {
	edges := []graph.Edge{}
	if direction == "outgoing" || direction == "either" {
		outgoing, err := r.graph.ListOutgoingEdges(ctx, taskID, types)
		if err != nil {
			return nil, err
		}
		edges = append(edges, outgoing...)
	}
	if direction == "incoming" || direction == "either" {
		incoming, err := r.graph.ListIncomingEdges(ctx, taskID, types)
		if err != nil {
			return nil, err
		}
		edges = append(edges, incoming...)
	}
	return edges, nil
}

// taskRelationFromEdge projects one graph edge into a task relation DTO.
func (r *Repository) taskRelationFromEdge(ctx context.Context, edge graph.Edge) (domain.TaskRelation, bool, error) {
	from, err := r.graph.GetNode(ctx, edge.FromNodeID)
	if err != nil {
		return domain.TaskRelation{}, false, err
	}
	to, err := r.graph.GetNode(ctx, edge.ToNodeID)
	if err != nil {
		return domain.TaskRelation{}, false, err
	}
	if from.Kind != graph.KindTask || to.Kind != graph.KindTask || from.Status == graph.StatusDeleted || to.Status == graph.StatusDeleted {
		return domain.TaskRelation{}, false, nil
	}
	relation := domain.TaskRelation{
		ID:         domain.TaskRelationID(edge.ID),
		FromTaskID: domain.TaskID(from.ID),
		FromTitle:  from.Title,
		Type:       taskRelationType(edge.Type),
		ToTaskID:   domain.TaskID(to.ID),
		ToTitle:    to.Title,
		Confidence: edge.Confidence,
		Actor:      edge.Actor,
		CreatedAt:  edge.CreatedAt,
		UpdatedAt:  edge.UpdatedAt,
	}
	properties, err := r.graph.ListEdgeProperties(ctx, edge.ID)
	if err != nil {
		return domain.TaskRelation{}, false, err
	}
	for _, property := range properties {
		switch property.Key {
		case propertyLinkNote:
			if property.Value.Type == graph.ValueText {
				relation.Note = property.Value.Text
			}
		case propertyLagMinutes:
			if property.Value.Type == graph.ValueNumber {
				relation.LagMinutes = int(property.Value.Number)
			}
		}
	}
	return relation, true, nil
}

// taskRelationGraphTypes maps query relation vocabulary to graph edge types.
func taskRelationGraphTypes(types []domain.TaskRelationType) []graph.RelationType {
	types = normalizedTaskRelationTypes(types)
	relations := make([]graph.RelationType, 0, len(types))
	for _, relation := range types {
		relations = append(relations, taskRelationGraphType(relation))
	}
	return relations
}

// normalizedTaskRelationTypes returns explicit relation types when callers omit them.
func normalizedTaskRelationTypes(types []domain.TaskRelationType) []domain.TaskRelationType {
	if len(types) > 0 {
		return append([]domain.TaskRelationType{}, types...)
	}
	return domain.TaskRelationTypes()
}

// taskRelationGraphType maps one task relation to a graph edge type.
func taskRelationGraphType(relation domain.TaskRelationType) graph.RelationType {
	for _, mapping := range taskRelationMappings {
		if mapping.task == relation {
			return mapping.graph
		}
	}
	return graph.RelationRelatedTo
}

// taskRelationType maps one graph edge type to task relation vocabulary.
func taskRelationType(relation graph.RelationType) domain.TaskRelationType {
	for _, mapping := range taskRelationMappings {
		if mapping.graph == relation {
			return mapping.task
		}
	}
	return domain.TaskRelationRelated
}

// taskMemoryRelationship maps graph edges back to task memory vocabulary.
func taskMemoryRelationship(relation graph.RelationType) domain.TaskMemoryRelationship {
	for _, mapping := range taskMemoryRelationMappings {
		if mapping.graph == relation {
			return mapping.task
		}
	}
	return domain.TaskMemoryRelated
}
