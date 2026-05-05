package service

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sync"
	"time"

	"agent-awesome.com/memoryinternal/agent-awesome.com/memorydomain"
	"agent-awesome.com/memoryinternal/agent-awesome.com/memoryid"
	"agent-awesome.com/memoryinternal/agent-awesome.com/memoryports"
)

// Config controls worker behavior for the memory service.
type Config struct {
	WorkerCount  int
	PollInterval time.Duration
}

// Service provides process-boundary-safe memory operations.
type Service struct {
	repo         ports.Repository
	steward      ports.Steward
	workerCount  int
	pollInterval time.Duration
	cancel       context.CancelFunc
	done         chan struct{}
	startOnce    sync.Once
	stopOnce     sync.Once
}

// New creates a memory service backed by the given repository.
func New(repo ports.Repository, steward ports.Steward, cfg Config) *Service {
	if cfg.WorkerCount <= 0 {
		cfg.WorkerCount = 2
	}
	if cfg.PollInterval <= 0 {
		cfg.PollInterval = 250 * time.Millisecond
	}
	return &Service{
		repo:         repo,
		steward:      steward,
		workerCount:  cfg.WorkerCount,
		pollInterval: cfg.PollInterval,
		done:         make(chan struct{}),
	}
}

// Start launches background workers for asynchronous enrichment.
func (s *Service) Start(ctx context.Context) {
	s.startOnce.Do(func() {
		workerCtx, cancel := context.WithCancel(ctx)
		s.cancel = cancel
		var wg sync.WaitGroup
		for i := 0; i < s.workerCount; i++ {
			wg.Add(1)
			go func(index int) {
				defer wg.Done()
				s.workerLoop(workerCtx, fmt.Sprintf("worker-%d", index+1))
			}(i)
		}
		go func() {
			wg.Wait()
			close(s.done)
		}()
	})
}

// Stop requests worker shutdown and waits for completion.
func (s *Service) Stop(ctx context.Context) error {
	if s.cancel == nil {
		return nil
	}
	s.stopOnce.Do(func() {
		s.cancel()
	})
	select {
	case <-s.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// Capture synchronously stores raw evidence and schedules enrichment.
func (s *Service) Capture(ctx context.Context, req domain.CaptureRequest) (domain.CaptureResult, error) {
	return s.repo.Capture(ctx, req)
}

// SearchMemory returns ordered memory search results.
func (s *Service) SearchMemory(ctx context.Context, q domain.RetrievalQuery) (domain.RetrievalBundle, error) {
	records, err := s.repo.Search(ctx, q)
	if err != nil {
		return domain.RetrievalBundle{}, err
	}
	bundle := domain.RetrievalBundle{Primary: records}
	for _, record := range records {
		bundle.Provenance = append(bundle.Provenance, record.Source)
		for _, rel := range record.Relationships {
			if rel.Type == domain.RelationshipContradicts {
				bundle.Contradictions = append(bundle.Contradictions, rel)
				bundle.Uncertainty = append(bundle.Uncertainty, fmt.Sprintf("record %s has contradiction relationship %s", record.ID, rel.ID))
			}
		}
	}
	if len(records) > 1 {
		bundle.Supporting = records[1:]
	}
	return bundle, nil
}

// SearchSources returns records with raw source text hydrated.
func (s *Service) SearchSources(ctx context.Context, q domain.RetrievalQuery) (domain.RetrievalBundle, error) {
	bundle, err := s.SearchMemory(ctx, q)
	if err != nil {
		return domain.RetrievalBundle{}, err
	}
	for i := range bundle.Primary {
		content, err := s.repo.GetEvidenceContent(ctx, bundle.Primary[i].EvidenceID)
		if err != nil {
			return domain.RetrievalBundle{}, err
		}
		if bundle.Primary[i].Raw != nil {
			bundle.Primary[i].Raw.ContentText = content
		}
	}
	return bundle, nil
}

// LoadEntityPage returns a compiled entity page, creating it if necessary.
func (s *Service) LoadEntityPage(ctx context.Context, scope domain.Scope, entityID domain.EntityID, title string) (domain.CompiledPage, error) {
	return s.repo.LoadEntityPage(ctx, scope, entityID, title)
}

// LoadTimeline returns a compiled timeline, creating it if necessary.
func (s *Service) LoadTimeline(ctx context.Context, scope domain.Scope, topic string, entityID domain.EntityID) (domain.CompiledPage, error) {
	return s.repo.LoadTimeline(ctx, scope, topic, entityID)
}

// RefreshCompiledPage rebuilds a compiled knowledge page.
func (s *Service) RefreshCompiledPage(ctx context.Context, req domain.RefreshPageRequest) (domain.CompiledPage, error) {
	return s.repo.RefreshCompiledPage(ctx, req)
}

// RepairMemoryRecord applies explicit metadata corrections.
func (s *Service) RepairMemoryRecord(ctx context.Context, req domain.RepairRequest) (domain.MemoryRecord, error) {
	return s.repo.RepairMemory(ctx, req)
}

// SubmitMemoryCorrection stores a correction as source evidence.
func (s *Service) SubmitMemoryCorrection(ctx context.Context, req domain.CorrectionRequest) (domain.CaptureResult, error) {
	return s.repo.CreateCorrection(ctx, req)
}

// QueryContextGraph executes one graph query or audited mutation.
func (s *Service) QueryContextGraph(ctx context.Context, req domain.GraphQueryRequest) (domain.GraphQueryResult, error) {
	repo, err := s.graphQueryRepository()
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	return repo.QueryContextGraph(ctx, req)
}

// CreateTask stores a graph-backed operational task.
func (s *Service) CreateTask(ctx context.Context, req domain.CreateTaskRequest) (domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.Task{}, err
	}
	return repo.CreateTask(ctx, req)
}

// GetTask returns one graph-backed operational task.
func (s *Service) GetTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.Task{}, err
	}
	return repo.GetTask(ctx, req)
}

// ListTasks returns graph-backed operational tasks.
func (s *Service) ListTasks(ctx context.Context, q domain.TaskQuery) ([]domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return nil, err
	}
	return repo.ListTasks(ctx, q)
}

// TaskGraphProjection returns a graph-backed task projection snapshot.
func (s *Service) TaskGraphProjection(ctx context.Context, q domain.TaskGraphProjectionQuery) (domain.TaskGraphProjection, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	return repo.TaskGraphProjection(ctx, q)
}

// UpdateTask patches a graph-backed operational task.
func (s *Service) UpdateTask(ctx context.Context, req domain.UpdateTaskRequest) (domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.Task{}, err
	}
	return repo.UpdateTask(ctx, req)
}

// CompleteTask marks a graph-backed operational task done.
func (s *Service) CompleteTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.Task{}, err
	}
	return repo.CompleteTask(ctx, req)
}

// CancelTask marks a graph-backed operational task canceled.
func (s *Service) CancelTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.Task{}, err
	}
	return repo.CancelTask(ctx, req)
}

// DeleteTask lifecycle-deletes a graph-backed operational task.
func (s *Service) DeleteTask(ctx context.Context, req domain.TaskIDRequest) error {
	repo, err := s.taskRepository()
	if err != nil {
		return err
	}
	return repo.DeleteTask(ctx, req)
}

// LinkTaskMemory attaches contextual memory to a graph-backed task.
func (s *Service) LinkTaskMemory(ctx context.Context, req domain.LinkTaskMemoryRequest) (domain.MemoryLink, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.MemoryLink{}, err
	}
	return repo.LinkTaskMemory(ctx, req)
}

// ListTaskRelations returns graph-backed directed task relationships.
func (s *Service) ListTaskRelations(ctx context.Context, q domain.TaskRelationQuery) ([]domain.TaskRelation, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return nil, err
	}
	return repo.ListTaskRelations(ctx, q)
}

// TraverseTaskRelations returns bounded graph paths through task relations.
func (s *Service) TraverseTaskRelations(ctx context.Context, q domain.TaskRelationTraversalQuery) (domain.TaskRelationTraversal, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	return repo.TraverseTaskRelations(ctx, q)
}

// UpsertTaskRelation creates or updates a graph-backed directed task relationship.
func (s *Service) UpsertTaskRelation(ctx context.Context, req domain.UpsertTaskRelationRequest) (domain.TaskRelation, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.TaskRelation{}, err
	}
	return repo.UpsertTaskRelation(ctx, req)
}

// DeleteTaskRelation lifecycle-deletes a graph-backed directed task relationship.
func (s *Service) DeleteTaskRelation(ctx context.Context, req domain.DeleteTaskRelationRequest) error {
	repo, err := s.taskRepository()
	if err != nil {
		return err
	}
	return repo.DeleteTaskRelation(ctx, req)
}

// Metrics returns operational counters from the repository.
func (s *Service) Metrics(ctx context.Context) (domain.Metrics, error) {
	return s.repo.Metrics(ctx)
}

// Close stops workers and closes the repository.
func (s *Service) Close(ctx context.Context) error {
	stopErr := s.Stop(ctx)
	closeErr := s.repo.Close()
	if stopErr != nil {
		return stopErr
	}
	return closeErr
}

// taskRepository returns the optional graph-backed task repository.
func (s *Service) taskRepository() (ports.TaskRepository, error) {
	repo, ok := s.repo.(ports.TaskRepository)
	if !ok {
		return nil, errors.New("task graph repository is not configured")
	}
	return repo, nil
}

// graphQueryRepository returns the optional graph query repository.
func (s *Service) graphQueryRepository() (ports.GraphQueryRepository, error) {
	repo, ok := s.repo.(ports.GraphQueryRepository)
	if !ok {
		return nil, errors.New("graph query repository is not configured")
	}
	return repo, nil
}

// workerLoop continuously leases and handles enrichment jobs.
func (s *Service) workerLoop(ctx context.Context, worker string) {
	timer := time.NewTimer(0)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			if err := s.runOneJob(ctx, worker); err != nil && !errors.Is(err, sql.ErrNoRows) {
				_ = s.repo.AddAudit(context.Background(), domain.AuditEvent{
					Kind:      "worker_error",
					Actor:     worker,
					SubjectID: worker,
					Message:   err.Error(),
					CreatedAt: time.Now().UTC(),
				})
			}
			timer.Reset(s.pollInterval)
		}
	}
}

// runOneJob leases and executes a single available job.
func (s *Service) runOneJob(ctx context.Context, worker string) error {
	job, ok, err := s.repo.LeaseJob(ctx, worker)
	if err != nil || !ok {
		return err
	}
	if err := s.handleJob(ctx, worker, job); err != nil {
		_ = s.repo.FailJob(ctx, job.ID, err)
		return err
	}
	return s.repo.CompleteJob(ctx, job.ID, "completed")
}

// handleJob dispatches deterministic and steward-assisted work by job kind.
func (s *Service) handleJob(ctx context.Context, worker string, job domain.Job) error {
	memoryID := domain.MemoryID(job.TargetID)
	record, err := s.repo.GetMemory(ctx, memoryID)
	if err != nil {
		return err
	}
	content, err := s.repo.GetEvidenceContent(ctx, record.EvidenceID)
	if err != nil {
		return err
	}
	switch job.Kind {
	case domain.JobClassify:
		return s.handleClassify(ctx, worker, record, content)
	case domain.JobResolveEntities:
		return s.auditJob(ctx, worker, job, "entity aliases are already canonicalized during capture")
	case domain.JobLinkRelationships:
		return s.auditJob(ctx, worker, job, "relationship linking completed with deterministic v1 rules")
	case domain.JobSummarize:
		return s.handleSummarize(ctx, worker, record, content)
	case domain.JobDetectDuplicates:
		return s.auditJob(ctx, worker, job, "duplicate detection completed for checksum-indexed evidence")
	case domain.JobReviewContradictions:
		return s.handleContradictions(ctx, worker, record, content)
	case domain.JobReindex:
		if err := s.repo.ReindexMemory(ctx, memoryID); err != nil {
			return err
		}
		return s.auditJob(ctx, worker, job, "lexical index refreshed")
	case domain.JobRefreshCompiledPage:
		return s.auditJob(ctx, worker, job, "compiled page refresh jobs are triggered explicitly in v1")
	default:
		return fmt.Errorf("unsupported job kind %s", job.Kind)
	}
}

// handleClassify lets the steward propose memory repairs when configured.
func (s *Service) handleClassify(ctx context.Context, worker string, record domain.MemoryRecord, content string) error {
	if s.steward == nil {
		return s.auditRecord(ctx, worker, record, "classification skipped because no steward is configured")
	}
	repair, err := s.steward.Classify(ctx, record, content)
	if err != nil {
		return err
	}
	repair.Actor = worker
	repair.MemoryID = record.ID
	_, err = s.repo.RepairMemory(ctx, repair)
	return err
}

// handleSummarize uses steward summaries when available.
func (s *Service) handleSummarize(ctx context.Context, worker string, record domain.MemoryRecord, content string) error {
	if s.steward == nil {
		return s.auditRecord(ctx, worker, record, "summarization skipped because deterministic capture summary already exists")
	}
	summary, err := s.steward.Summarize(ctx, record, content)
	if err != nil {
		return err
	}
	repair := domain.RepairRequest{Actor: worker, MemoryID: record.ID, Summary: &summary}
	_, err = s.repo.RepairMemory(ctx, repair)
	return err
}

// handleContradictions asks the steward to flag contradictions when configured.
func (s *Service) handleContradictions(ctx context.Context, worker string, record domain.MemoryRecord, content string) error {
	if s.steward == nil {
		return s.auditRecord(ctx, worker, record, "contradiction review skipped because no steward is configured")
	}
	relationships, err := s.steward.ReviewContradictions(ctx, record, content)
	if err != nil {
		return err
	}
	if len(relationships) == 0 {
		return s.auditRecord(ctx, worker, record, "steward found no contradictions")
	}
	return s.auditRecord(ctx, worker, record, fmt.Sprintf("steward flagged %d contradiction candidates for review", len(relationships)))
}

// auditJob records successful deterministic worker behavior.
func (s *Service) auditJob(ctx context.Context, worker string, job domain.Job, message string) error {
	auditID, err := id.New("audit")
	if err != nil {
		return err
	}
	return s.repo.AddAudit(ctx, domain.AuditEvent{
		ID:        domain.AuditID(auditID),
		Kind:      string(job.Kind),
		Actor:     worker,
		SubjectID: job.TargetID,
		Message:   message,
		CreatedAt: time.Now().UTC(),
	})
}

// auditRecord records worker behavior for a memory record.
func (s *Service) auditRecord(ctx context.Context, worker string, record domain.MemoryRecord, message string) error {
	auditID, err := id.New("audit")
	if err != nil {
		return err
	}
	return s.repo.AddAudit(ctx, domain.AuditEvent{
		ID:        domain.AuditID(auditID),
		Kind:      "worker_enrichment",
		Actor:     worker,
		SubjectID: string(record.ID),
		SourceID:  record.EvidenceID,
		Message:   message,
		CreatedAt: time.Now().UTC(),
	})
}
