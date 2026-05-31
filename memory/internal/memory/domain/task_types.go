package domain

import "time"

// TaskID identifies a graph-backed operational task.
type TaskID string

// TaskRelationID identifies one directed task relationship edge.
type TaskRelationID string

// TaskStatus describes task lifecycle state.
type TaskStatus string

const (
	// TaskStatusBlocked means the task cannot proceed.
	TaskStatusBlocked TaskStatus = "blocked"
	// TaskStatusCanceled means the task is intentionally abandoned.
	TaskStatusCanceled TaskStatus = "canceled"
	// TaskStatusDone means the task has been completed.
	TaskStatusDone TaskStatus = "done"
	// TaskStatusOpen means the task is ready to work.
	TaskStatusOpen TaskStatus = "open"
	// TaskStatusWaiting means progress depends on someone or something else.
	TaskStatusWaiting TaskStatus = "waiting"
)

// TaskPriority describes task urgency for sorting and triage.
type TaskPriority string

const (
	// TaskPriorityHigh marks important work.
	TaskPriorityHigh TaskPriority = "high"
	// TaskPriorityLow marks low-urgency work.
	TaskPriorityLow TaskPriority = "low"
	// TaskPriorityNormal marks default urgency.
	TaskPriorityNormal TaskPriority = "normal"
	// TaskPriorityUrgent marks critical time-sensitive work.
	TaskPriorityUrgent TaskPriority = "urgent"
)

// TaskMemoryRelationship describes how a task relates to memory.
type TaskMemoryRelationship string

const (
	// TaskMemoryContext means memory provides useful background.
	TaskMemoryContext TaskMemoryRelationship = "context"
	// TaskMemoryOriginatedFrom means memory caused the task to exist.
	TaskMemoryOriginatedFrom TaskMemoryRelationship = "originated_from"
	// TaskMemoryRelated means memory is generally related.
	TaskMemoryRelated TaskMemoryRelationship = "related"
	// TaskMemorySupporting means memory supports task details or decisions.
	TaskMemorySupporting TaskMemoryRelationship = "supporting"
)

// TaskRelationType describes directed task-to-task graph semantics.
type TaskRelationType string

const (
	// TaskRelationBlocks means the source task blocks the target task.
	TaskRelationBlocks TaskRelationType = "blocks"
	// TaskRelationDependsOn means the source task depends on the target task.
	TaskRelationDependsOn TaskRelationType = "depends_on"
	// TaskRelationEnables means the source task enables the target task.
	TaskRelationEnables TaskRelationType = "enables"
	// TaskRelationPartOf means the source task is part of the target task.
	TaskRelationPartOf TaskRelationType = "part_of"
	// TaskRelationRelated means the tasks are generally related.
	TaskRelationRelated TaskRelationType = "related_to"
)

// Task stores an operational todo projected from the context graph.
type Task struct {
	ID              TaskID            `json:"id"`
	DomainID        DomainID          `json:"domain_id,omitempty"`
	Firewall        Firewall          `json:"firewall,omitempty"`
	Title           string            `json:"title"`
	Description     string            `json:"description,omitempty"`
	Status          TaskStatus        `json:"status"`
	Priority        TaskPriority      `json:"priority"`
	DueAt           *time.Time        `json:"due_at,omitempty"`
	ScheduledAt     *time.Time        `json:"scheduled_at,omitempty"`
	FollowUpAt      *time.Time        `json:"follow_up_at,omitempty"`
	Topics          []string          `json:"topics,omitempty"`
	EstimateMinutes int               `json:"estimate_minutes,omitempty"`
	Urgency         float64           `json:"urgency,omitempty"`
	Risk            float64           `json:"risk,omitempty"`
	Project         string            `json:"project,omitempty"`
	Location        string            `json:"location,omitempty"`
	Person          string            `json:"person,omitempty"`
	Actor           string            `json:"actor"`
	IdempotencyKey  string            `json:"idempotency_key,omitempty"`
	CreatedAt       time.Time         `json:"created_at"`
	UpdatedAt       time.Time         `json:"updated_at"`
	CompletedAt     *time.Time        `json:"completed_at,omitempty"`
	CanceledAt      *time.Time        `json:"canceled_at,omitempty"`
	Overdue         bool              `json:"overdue"`
	MemoryLinks     []MemoryLink      `json:"memory_links,omitempty"`
	WorkBreakdown   TaskWorkBreakdown `json:"work_breakdown,omitempty"`
}

// TaskWorkBreakdown stores WBS planning metadata for one graph-backed task.
type TaskWorkBreakdown struct {
	Code               string                    `json:"code,omitempty"`
	Deliverable        string                    `json:"deliverable,omitempty"`
	StartCriteria      []string                  `json:"start_criteria,omitempty"`
	AcceptanceCriteria []string                  `json:"acceptance_criteria,omitempty"`
	RequirementRefs    []string                  `json:"requirement_refs,omitempty"`
	RubricRefs         []string                  `json:"rubric_refs,omitempty"`
	Resources          []TaskResourceRequirement `json:"resources,omitempty"`
	SpendCents         int                       `json:"spend_cents,omitempty"`
	SpendCurrency      string                    `json:"spend_currency,omitempty"`
}

// TaskResourceRequirement stores one resource needed by WBS work.
type TaskResourceRequirement struct {
	Name          string  `json:"name,omitempty"`
	Type          string  `json:"type,omitempty"`
	Quantity      float64 `json:"quantity,omitempty"`
	Unit          string  `json:"unit,omitempty"`
	SpendCents    int     `json:"spend_cents,omitempty"`
	SpendCurrency string  `json:"spend_currency,omitempty"`
	Notes         string  `json:"notes,omitempty"`
}

// TaskRelation stores a directed relationship between two graph-backed tasks.
type TaskRelation struct {
	ID         TaskRelationID   `json:"id"`
	DomainID   DomainID         `json:"domain_id,omitempty"`
	Firewall   Firewall         `json:"firewall,omitempty"`
	FromTaskID TaskID           `json:"from_task_id"`
	FromTitle  string           `json:"from_title,omitempty"`
	Type       TaskRelationType `json:"type"`
	ToTaskID   TaskID           `json:"to_task_id"`
	ToTitle    string           `json:"to_title,omitempty"`
	Note       string           `json:"note,omitempty"`
	LagMinutes int              `json:"lag_minutes,omitempty"`
	Confidence float64          `json:"confidence,omitempty"`
	Actor      string           `json:"actor,omitempty"`
	CreatedAt  time.Time        `json:"created_at"`
	UpdatedAt  time.Time        `json:"updated_at"`
}

// TaskRelationPath stores one directed traversal path through task edges.
type TaskRelationPath struct {
	RootTaskID  TaskID           `json:"root_task_id"`
	TaskIDs     []TaskID         `json:"task_ids"`
	RelationIDs []TaskRelationID `json:"relation_ids,omitempty"`
	Tasks       []Task           `json:"tasks,omitempty"`
	Relations   []TaskRelation   `json:"relations,omitempty"`
	Depth       int              `json:"depth"`
	Cycle       bool             `json:"cycle,omitempty"`
}

// TaskRelationTraversal stores paths found by a task relation traversal.
type TaskRelationTraversal struct {
	RootTaskID TaskID             `json:"root_task_id"`
	Types      []TaskRelationType `json:"types,omitempty"`
	Direction  string             `json:"direction"`
	MaxDepth   int                `json:"max_depth"`
	Paths      []TaskRelationPath `json:"paths"`
}

// CreateTaskRequest asks the service to create a graph-backed task.
type CreateTaskRequest struct {
	Actor           string              `json:"actor"`
	DomainID        DomainID            `json:"domain_id,omitempty"`
	Firewall        Firewall            `json:"firewall,omitempty"`
	Title           string              `json:"title"`
	Description     string              `json:"description,omitempty"`
	Status          TaskStatus          `json:"status,omitempty"`
	Priority        TaskPriority        `json:"priority,omitempty"`
	DueAt           *time.Time          `json:"due_at,omitempty"`
	ScheduledAt     *time.Time          `json:"scheduled_at,omitempty"`
	FollowUpAt      *time.Time          `json:"follow_up_at,omitempty"`
	Topics          []string            `json:"topics,omitempty"`
	EstimateMinutes int                 `json:"estimate_minutes,omitempty"`
	Urgency         float64             `json:"urgency,omitempty"`
	Project         string              `json:"project,omitempty"`
	Location        string              `json:"location,omitempty"`
	Person          string              `json:"person,omitempty"`
	MemoryLinks     []MemoryLinkRequest `json:"memory_links,omitempty"`
	WorkBreakdown   TaskWorkBreakdown   `json:"work_breakdown,omitempty"`
	IdempotencyKey  string              `json:"idempotency_key,omitempty"`
}

// UpdateTaskRequest asks the service to patch graph-backed task facts.
type UpdateTaskRequest struct {
	TaskID           TaskID             `json:"task_id"`
	Actor            string             `json:"actor,omitempty"`
	DomainID         DomainID           `json:"domain_id,omitempty"`
	Firewall         Firewall           `json:"firewall,omitempty"`
	Title            *string            `json:"title,omitempty"`
	Description      *string            `json:"description,omitempty"`
	Status           *TaskStatus        `json:"status,omitempty"`
	Priority         *TaskPriority      `json:"priority,omitempty"`
	DueAt            *time.Time         `json:"due_at,omitempty"`
	ClearDueAt       bool               `json:"clear_due_at,omitempty"`
	ScheduledAt      *time.Time         `json:"scheduled_at,omitempty"`
	ClearScheduledAt bool               `json:"clear_scheduled_at,omitempty"`
	FollowUpAt       *time.Time         `json:"follow_up_at,omitempty"`
	ClearFollowUpAt  bool               `json:"clear_follow_up_at,omitempty"`
	Topics           []string           `json:"topics,omitempty"`
	EstimateMinutes  *int               `json:"estimate_minutes,omitempty"`
	Urgency          *float64           `json:"urgency,omitempty"`
	Project          *string            `json:"project,omitempty"`
	Location         *string            `json:"location,omitempty"`
	Person           *string            `json:"person,omitempty"`
	WorkBreakdown    *TaskWorkBreakdown `json:"work_breakdown,omitempty"`
}

// TaskQuery filters graph-backed tasks.
type TaskQuery struct {
	DomainID     DomainID       `json:"domain_id,omitempty"`
	Firewall     Firewall       `json:"firewall,omitempty"`
	Statuses     []TaskStatus   `json:"statuses,omitempty"`
	Priorities   []TaskPriority `json:"priorities,omitempty"`
	Topics       []string       `json:"topics,omitempty"`
	Search       string         `json:"search,omitempty"`
	OverdueOnly  bool           `json:"overdue_only,omitempty"`
	IncludeDone  bool           `json:"include_done,omitempty"`
	IncludeLinks bool           `json:"include_links,omitempty"`
	Limit        int            `json:"limit,omitempty"`
}

// TaskRelationQuery filters task-to-task relationships.
type TaskRelationQuery struct {
	DomainID  DomainID           `json:"domain_id,omitempty"`
	Firewall  Firewall           `json:"firewall,omitempty"`
	TaskID    TaskID             `json:"task_id,omitempty"`
	Types     []TaskRelationType `json:"types,omitempty"`
	Direction string             `json:"direction,omitempty"`
	Limit     int                `json:"limit,omitempty"`
}

// TaskRelationTraversalQuery asks for bounded graph traversal from a root task.
type TaskRelationTraversalQuery struct {
	DomainID     DomainID           `json:"domain_id,omitempty"`
	Firewall     Firewall           `json:"firewall,omitempty"`
	RootTaskID   TaskID             `json:"root_task_id"`
	Types        []TaskRelationType `json:"types,omitempty"`
	Direction    string             `json:"direction,omitempty"`
	MaxDepth     int                `json:"max_depth,omitempty"`
	Limit        int                `json:"limit,omitempty"`
	IncludeTasks bool               `json:"include_tasks,omitempty"`
	IncludeLinks bool               `json:"include_links,omitempty"`
}

// TaskIDRequest asks for one task by id.
type TaskIDRequest struct {
	TaskID   TaskID   `json:"task_id"`
	Actor    string   `json:"actor,omitempty"`
	DomainID DomainID `json:"domain_id,omitempty"`
	Firewall Firewall `json:"firewall,omitempty"`
}

// UpsertTaskRelationRequest asks the service to create or update a task edge.
type UpsertTaskRelationRequest struct {
	Actor      string           `json:"actor,omitempty"`
	DomainID   DomainID         `json:"domain_id,omitempty"`
	Firewall   Firewall         `json:"firewall,omitempty"`
	FromTaskID TaskID           `json:"from_task_id"`
	Type       TaskRelationType `json:"type"`
	ToTaskID   TaskID           `json:"to_task_id"`
	Note       string           `json:"note,omitempty"`
	LagMinutes int              `json:"lag_minutes,omitempty"`
	Confidence float64          `json:"confidence,omitempty"`
}

// DeleteTaskRelationRequest asks the service to lifecycle-delete a task edge.
type DeleteTaskRelationRequest struct {
	Actor      string         `json:"actor,omitempty"`
	DomainID   DomainID       `json:"domain_id,omitempty"`
	Firewall   Firewall       `json:"firewall,omitempty"`
	RelationID TaskRelationID `json:"relation_id"`
}

// LinkTaskMemoryRequest asks the system to attach contextual memory to a task.
type LinkTaskMemoryRequest struct {
	TaskID   TaskID            `json:"task_id"`
	DomainID DomainID          `json:"domain_id,omitempty"`
	Firewall Firewall          `json:"firewall,omitempty"`
	Link     MemoryLinkRequest `json:"link"`
}

// MemoryLinkRequest asks the system to attach contextual memory.
type MemoryLinkRequest struct {
	MemoryID         string                 `json:"memory_id,omitempty"`
	MemoryEvidenceID string                 `json:"memory_evidence_id,omitempty"`
	Relationship     TaskMemoryRelationship `json:"relationship"`
	Note             string                 `json:"note,omitempty"`
}

// MemoryLink references contextual memory without duplicating its contents.
type MemoryLink struct {
	ID               string                 `json:"id"`
	MemoryID         string                 `json:"memory_id,omitempty"`
	MemoryEvidenceID string                 `json:"memory_evidence_id,omitempty"`
	Relationship     TaskMemoryRelationship `json:"relationship"`
	Note             string                 `json:"note,omitempty"`
	CreatedAt        time.Time              `json:"created_at"`
}
