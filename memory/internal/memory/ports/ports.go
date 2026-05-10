package ports

import (
	"context"

	"memory/internal/memory/domain"
)

// Repository stores source content, memory records, jobs, pages, and audit events.
type Repository interface {
	Capture(ctx context.Context, req domain.CaptureRequest) (domain.CaptureResult, error)
	Search(ctx context.Context, q domain.RetrievalQuery) ([]domain.MemoryRecord, error)
	GetMemory(ctx context.Context, id domain.MemoryID) (domain.MemoryRecord, error)
	GetEvidenceContent(ctx context.Context, id domain.EvidenceID) (string, error)
	RepairMemory(ctx context.Context, req domain.RepairRequest) (domain.MemoryRecord, error)
	CreateCorrection(ctx context.Context, req domain.CorrectionRequest) (domain.CaptureResult, error)
	RefreshCompiledPage(ctx context.Context, req domain.RefreshPageRequest) (domain.CompiledPage, error)
	LoadEntityPage(ctx context.Context, scope domain.Scope, entityID domain.EntityID, title string) (domain.CompiledPage, error)
	LoadTimeline(ctx context.Context, scope domain.Scope, topic string, entityID domain.EntityID) (domain.CompiledPage, error)
	LeaseJob(ctx context.Context, worker string) (domain.Job, bool, error)
	CompleteJob(ctx context.Context, id domain.JobID, message string) error
	FailJob(ctx context.Context, id domain.JobID, err error) error
	ReindexMemory(ctx context.Context, id domain.MemoryID) error
	AddAudit(ctx context.Context, event domain.AuditEvent) error
	Metrics(ctx context.Context) (domain.Metrics, error)
	Close() error
}

// TaskRepository stores graph-backed operational tasks.
type TaskRepository interface {
	CreateTask(context.Context, domain.CreateTaskRequest) (domain.Task, error)
	GetTask(context.Context, domain.TaskIDRequest) (domain.Task, error)
	ListTasks(context.Context, domain.TaskQuery) ([]domain.Task, error)
	TaskGraphProjection(context.Context, domain.TaskGraphProjectionQuery) (domain.TaskGraphProjection, error)
	UpdateTask(context.Context, domain.UpdateTaskRequest) (domain.Task, error)
	CompleteTask(context.Context, domain.TaskIDRequest) (domain.Task, error)
	CancelTask(context.Context, domain.TaskIDRequest) (domain.Task, error)
	DeleteTask(context.Context, domain.TaskIDRequest) error
	LinkTaskMemory(context.Context, domain.LinkTaskMemoryRequest) (domain.MemoryLink, error)
	ListTaskRelations(context.Context, domain.TaskRelationQuery) ([]domain.TaskRelation, error)
	TraverseTaskRelations(context.Context, domain.TaskRelationTraversalQuery) (domain.TaskRelationTraversal, error)
	UpsertTaskRelation(context.Context, domain.UpsertTaskRelationRequest) (domain.TaskRelation, error)
	DeleteTaskRelation(context.Context, domain.DeleteTaskRelationRequest) error
}

// GraphQueryRepository executes graph queries and audited mutations.
type GraphQueryRepository interface {
	QueryContextGraph(context.Context, domain.GraphQueryRequest) (domain.GraphQueryResult, error)
}

// Steward performs optional model-assisted memory enrichment and maintenance.
type Steward interface {
	Classify(ctx context.Context, record domain.MemoryRecord, content string) (domain.RepairRequest, error)
	Summarize(ctx context.Context, record domain.MemoryRecord, content string) (string, error)
	ReviewContradictions(ctx context.Context, record domain.MemoryRecord, content string) ([]domain.Relationship, error)
}
