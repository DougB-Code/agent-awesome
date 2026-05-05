package domain

import (
	"errors"
	"fmt"
	"strings"
)

// NormalizeCreateTaskRequest fills defaults and validates task creation.
func NormalizeCreateTaskRequest(req CreateTaskRequest) (CreateTaskRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "user")
	req.Title = strings.TrimSpace(req.Title)
	if req.Title == "" {
		return req, errors.New("title is required")
	}
	req.Description = strings.TrimSpace(req.Description)
	if req.Status == "" {
		req.Status = TaskStatusOpen
	}
	if !ValidTaskStatus(req.Status) {
		return req, fmt.Errorf("invalid task status %q", req.Status)
	}
	if req.Priority == "" {
		req.Priority = TaskPriorityNormal
	}
	if !ValidTaskPriority(req.Priority) {
		return req, fmt.Errorf("invalid task priority %q", req.Priority)
	}
	req.Topics = NormalizeStrings(req.Topics)
	req.EnergyRequired = strings.TrimSpace(req.EnergyRequired)
	req.Context = strings.TrimSpace(req.Context)
	req.View = strings.TrimSpace(req.View)
	req.Project = strings.TrimSpace(req.Project)
	req.Location = strings.TrimSpace(req.Location)
	req.Person = strings.TrimSpace(req.Person)
	req.Source = strings.TrimSpace(req.Source)
	req.IdempotencyKey = strings.TrimSpace(req.IdempotencyKey)
	req.WorkBreakdown = NormalizeTaskWorkBreakdown(req.WorkBreakdown)
	if err := validateTaskMetadata(req.EstimateMinutes, req.Effort, req.Value, req.Urgency, req.Risk, req.Confidence); err != nil {
		return req, err
	}
	if err := normalizeTaskMemoryLinks(req.MemoryLinks, &req.MemoryLinks); err != nil {
		return req, err
	}
	return req, nil
}

// NormalizeUpdateTaskRequest fills defaults and validates task patches.
func NormalizeUpdateTaskRequest(req UpdateTaskRequest) (UpdateTaskRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "user")
	if req.TaskID == "" {
		return req, errors.New("task_id is required")
	}
	if req.Title != nil {
		value := strings.TrimSpace(*req.Title)
		if value == "" {
			return req, errors.New("title cannot be blank")
		}
		req.Title = &value
	}
	trimStringPointer(req.Description)
	trimStringPointer(req.EnergyRequired)
	trimStringPointer(req.Context)
	trimStringPointer(req.View)
	trimStringPointer(req.Project)
	trimStringPointer(req.Location)
	trimStringPointer(req.Person)
	trimStringPointer(req.Source)
	if req.WorkBreakdown != nil {
		value := NormalizeTaskWorkBreakdown(*req.WorkBreakdown)
		req.WorkBreakdown = &value
	}
	if req.Status != nil && !ValidTaskStatus(*req.Status) {
		return req, fmt.Errorf("invalid task status %q", *req.Status)
	}
	if req.Priority != nil && !ValidTaskPriority(*req.Priority) {
		return req, fmt.Errorf("invalid task priority %q", *req.Priority)
	}
	if req.Topics != nil {
		req.Topics = NormalizeStrings(req.Topics)
	}
	if err := validateTaskMetadataPointers(req.EstimateMinutes, req.Effort, req.Value, req.Urgency, req.Risk, req.Confidence); err != nil {
		return req, err
	}
	if !taskUpdateHasChanges(req) {
		return req, errors.New("at least one task field is required")
	}
	return req, nil
}

// NormalizeTaskQuery fills safe defaults and validates task filters.
func NormalizeTaskQuery(q TaskQuery) (TaskQuery, error) {
	for _, status := range q.Statuses {
		if !ValidTaskStatus(status) {
			return q, fmt.Errorf("invalid task status %q", status)
		}
	}
	for _, priority := range q.Priorities {
		if !ValidTaskPriority(priority) {
			return q, fmt.Errorf("invalid task priority %q", priority)
		}
	}
	q.Topics = NormalizeStrings(q.Topics)
	q.Search = strings.TrimSpace(q.Search)
	if q.Limit <= 0 || q.Limit > 100 {
		q.Limit = 50
	}
	return q, nil
}

// NormalizeTaskRelationQuery fills safe defaults and validates edge filters.
func NormalizeTaskRelationQuery(q TaskRelationQuery) (TaskRelationQuery, error) {
	q.Direction = strings.ToLower(strings.TrimSpace(q.Direction))
	if q.Direction == "" {
		q.Direction = "outgoing"
	}
	switch q.Direction {
	case "outgoing", "incoming", "either":
	default:
		return q, fmt.Errorf("invalid task relation direction %q", q.Direction)
	}
	for _, relation := range q.Types {
		if !ValidTaskRelationType(relation) {
			return q, fmt.Errorf("invalid task relation type %q", relation)
		}
	}
	if q.Limit <= 0 || q.Limit > 500 {
		q.Limit = 100
	}
	return q, nil
}

// NormalizeTaskRelationTraversalQuery validates bounded graph traversal input.
func NormalizeTaskRelationTraversalQuery(q TaskRelationTraversalQuery) (TaskRelationTraversalQuery, error) {
	if q.RootTaskID == "" {
		return q, errors.New("root_task_id is required")
	}
	q.Direction = strings.ToLower(strings.TrimSpace(q.Direction))
	if q.Direction == "" {
		q.Direction = "outgoing"
	}
	switch q.Direction {
	case "outgoing", "incoming", "either":
	default:
		return q, fmt.Errorf("invalid task relation direction %q", q.Direction)
	}
	for _, relation := range q.Types {
		if !ValidTaskRelationType(relation) {
			return q, fmt.Errorf("invalid task relation type %q", relation)
		}
	}
	if q.MaxDepth <= 0 || q.MaxDepth > 12 {
		q.MaxDepth = 6
	}
	if q.Limit <= 0 || q.Limit > 500 {
		q.Limit = 100
	}
	return q, nil
}

// NormalizeTaskIDRequest validates a request for one task.
func NormalizeTaskIDRequest(req TaskIDRequest) (TaskIDRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "user")
	if req.TaskID == "" {
		return req, errors.New("task_id is required")
	}
	return req, nil
}

// NormalizeUpsertTaskRelationRequest validates one task relationship edge.
func NormalizeUpsertTaskRelationRequest(req UpsertTaskRelationRequest) (UpsertTaskRelationRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "user")
	req.Note = strings.TrimSpace(req.Note)
	if req.FromTaskID == "" {
		return req, errors.New("from_task_id is required")
	}
	if req.ToTaskID == "" {
		return req, errors.New("to_task_id is required")
	}
	if req.FromTaskID == req.ToTaskID {
		return req, errors.New("task relation cannot point to the same task")
	}
	if req.Type == "" {
		req.Type = TaskRelationRelated
	}
	if !ValidTaskRelationType(req.Type) {
		return req, fmt.Errorf("invalid task relation type %q", req.Type)
	}
	if req.LagMinutes < 0 {
		return req, errors.New("lag_minutes must be zero or greater")
	}
	if req.Confidence < 0 || req.Confidence > 1 {
		return req, errors.New("confidence must be between 0 and 1")
	}
	return req, nil
}

// NormalizeDeleteTaskRelationRequest validates relation deletion.
func NormalizeDeleteTaskRelationRequest(req DeleteTaskRelationRequest) (DeleteTaskRelationRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "user")
	if req.RelationID == "" {
		return req, errors.New("relation_id is required")
	}
	return req, nil
}

// NormalizeLinkTaskMemoryRequest validates a task memory link request.
func NormalizeLinkTaskMemoryRequest(req LinkTaskMemoryRequest) (LinkTaskMemoryRequest, error) {
	if req.TaskID == "" {
		return req, errors.New("task_id is required")
	}
	link, err := NormalizeMemoryLinkRequest(req.Link)
	req.Link = link
	return req, err
}

// NormalizeMemoryLinkRequest validates one contextual memory link.
func NormalizeMemoryLinkRequest(req MemoryLinkRequest) (MemoryLinkRequest, error) {
	req.MemoryID = strings.TrimSpace(req.MemoryID)
	req.MemoryEvidenceID = strings.TrimSpace(req.MemoryEvidenceID)
	req.Note = strings.TrimSpace(req.Note)
	if req.MemoryID == "" && req.MemoryEvidenceID == "" {
		return req, errors.New("memory_id or memory_evidence_id is required")
	}
	if req.Relationship == "" {
		req.Relationship = TaskMemoryRelated
	}
	if !ValidTaskMemoryRelationship(req.Relationship) {
		return req, fmt.Errorf("invalid memory relationship %q", req.Relationship)
	}
	return req, nil
}

// ValidTaskStatus reports whether status is in the controlled vocabulary.
func ValidTaskStatus(status TaskStatus) bool {
	switch status {
	case TaskStatusBlocked, TaskStatusCanceled, TaskStatusDone, TaskStatusOpen, TaskStatusWaiting:
		return true
	default:
		return false
	}
}

// ValidTaskPriority reports whether priority is in the controlled vocabulary.
func ValidTaskPriority(priority TaskPriority) bool {
	switch priority {
	case TaskPriorityHigh, TaskPriorityLow, TaskPriorityNormal, TaskPriorityUrgent:
		return true
	default:
		return false
	}
}

// ValidTaskMemoryRelationship reports whether relationship is controlled.
func ValidTaskMemoryRelationship(relationship TaskMemoryRelationship) bool {
	switch relationship {
	case TaskMemoryContext, TaskMemoryOriginatedFrom, TaskMemoryRelated, TaskMemorySupporting:
		return true
	default:
		return false
	}
}

// ValidTaskRelationType reports whether relation is controlled.
func ValidTaskRelationType(relation TaskRelationType) bool {
	switch relation {
	case TaskRelationBlocks, TaskRelationDependsOn, TaskRelationEnables, TaskRelationPartOf, TaskRelationRelated:
		return true
	default:
		return false
	}
}

// TerminalTaskStatus reports whether status means no further work is expected.
func TerminalTaskStatus(status TaskStatus) bool {
	return status == TaskStatusCanceled || status == TaskStatusDone
}

// validateTaskMetadata checks numeric task scores.
func validateTaskMetadata(estimate int, effort float64, value float64, urgency float64, risk float64, confidence float64) error {
	if estimate < 0 {
		return errors.New("estimate_minutes must be zero or greater")
	}
	for label, score := range map[string]float64{
		"effort":     effort,
		"value":      value,
		"urgency":    urgency,
		"risk":       risk,
		"confidence": confidence,
	} {
		if score < 0 || score > 1 {
			return fmt.Errorf("%s must be between 0 and 1", label)
		}
	}
	return nil
}

// validateTaskMetadataPointers checks optional numeric task scores.
func validateTaskMetadataPointers(estimate *int, effort *float64, value *float64, urgency *float64, risk *float64, confidence *float64) error {
	if estimate != nil && *estimate < 0 {
		return errors.New("estimate_minutes must be zero or greater")
	}
	for label, score := range map[string]*float64{
		"effort":     effort,
		"value":      value,
		"urgency":    urgency,
		"risk":       risk,
		"confidence": confidence,
	} {
		if score != nil && (*score < 0 || *score > 1) {
			return fmt.Errorf("%s must be between 0 and 1", label)
		}
	}
	return nil
}

// normalizeTaskMemoryLinks validates memory links in-place.
func normalizeTaskMemoryLinks(input []MemoryLinkRequest, output *[]MemoryLinkRequest) error {
	links := make([]MemoryLinkRequest, 0, len(input))
	for _, link := range input {
		normalized, err := NormalizeMemoryLinkRequest(link)
		if err != nil {
			return err
		}
		links = append(links, normalized)
	}
	*output = links
	return nil
}

// taskUpdateHasChanges reports whether a task patch contains any write.
func taskUpdateHasChanges(req UpdateTaskRequest) bool {
	return req.Title != nil ||
		req.Description != nil ||
		req.Status != nil ||
		req.Priority != nil ||
		req.DueAt != nil ||
		req.ClearDueAt ||
		req.ScheduledAt != nil ||
		req.ClearScheduledAt ||
		req.Topics != nil ||
		req.EstimateMinutes != nil ||
		req.EnergyRequired != nil ||
		req.Effort != nil ||
		req.Value != nil ||
		req.Urgency != nil ||
		req.Risk != nil ||
		req.Context != nil ||
		req.View != nil ||
		req.Project != nil ||
		req.Location != nil ||
		req.Person != nil ||
		req.Source != nil ||
		req.Confidence != nil ||
		req.WorkBreakdown != nil
}

// NormalizeTaskWorkBreakdown trims WBS metadata without changing meaning.
func NormalizeTaskWorkBreakdown(workBreakdown TaskWorkBreakdown) TaskWorkBreakdown {
	workBreakdown.Code = strings.TrimSpace(workBreakdown.Code)
	workBreakdown.Deliverable = strings.TrimSpace(workBreakdown.Deliverable)
	workBreakdown.StartCriteria = NormalizeStrings(workBreakdown.StartCriteria)
	workBreakdown.AcceptanceCriteria = NormalizeStrings(workBreakdown.AcceptanceCriteria)
	workBreakdown.RequirementRefs = NormalizeStrings(workBreakdown.RequirementRefs)
	workBreakdown.RubricRefs = NormalizeStrings(workBreakdown.RubricRefs)
	workBreakdown.SpendCurrency = strings.TrimSpace(workBreakdown.SpendCurrency)
	resources := make([]TaskResourceRequirement, 0, len(workBreakdown.Resources))
	for _, resource := range workBreakdown.Resources {
		normalized := NormalizeTaskResourceRequirement(resource)
		if TaskResourceRequirementHasContent(normalized) {
			resources = append(resources, normalized)
		}
	}
	workBreakdown.Resources = resources
	return workBreakdown
}

// NormalizeTaskResourceRequirement trims one WBS resource requirement.
func NormalizeTaskResourceRequirement(resource TaskResourceRequirement) TaskResourceRequirement {
	resource.Name = strings.TrimSpace(resource.Name)
	resource.Type = strings.TrimSpace(resource.Type)
	resource.Unit = strings.TrimSpace(resource.Unit)
	resource.SpendCurrency = strings.TrimSpace(resource.SpendCurrency)
	resource.Notes = strings.TrimSpace(resource.Notes)
	return resource
}

// TaskWorkBreakdownHasContent reports whether WBS metadata has useful data.
func TaskWorkBreakdownHasContent(workBreakdown TaskWorkBreakdown) bool {
	return workBreakdown.Code != "" ||
		workBreakdown.Deliverable != "" ||
		len(workBreakdown.StartCriteria) > 0 ||
		len(workBreakdown.AcceptanceCriteria) > 0 ||
		len(workBreakdown.RequirementRefs) > 0 ||
		len(workBreakdown.RubricRefs) > 0 ||
		len(workBreakdown.Resources) > 0 ||
		workBreakdown.SpendCents > 0 ||
		workBreakdown.SpendCurrency != ""
}

// TaskResourceRequirementHasContent reports whether one WBS resource is useful.
func TaskResourceRequirementHasContent(resource TaskResourceRequirement) bool {
	return resource.Name != "" ||
		resource.Type != "" ||
		resource.Quantity > 0 ||
		resource.Unit != "" ||
		resource.SpendCents > 0 ||
		resource.SpendCurrency != "" ||
		resource.Notes != ""
}

// trimStringPointer trims an optional string field in place.
func trimStringPointer(value *string) {
	if value == nil {
		return
	}
	*value = strings.TrimSpace(*value)
}
