package service

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"memory/internal/memory/domain"
	"memory/internal/memory/id"
	"memory/internal/memory/ports"
)

// Config controls worker behavior for the memory service.
type Config struct {
	WorkerCount        int
	PollInterval       time.Duration
	FirewallPolicy     *FirewallPolicy
	FirewallPolicyPath string
}

// Repositories contains the storage ports required by service features.
type Repositories struct {
	Memory     ports.Repository
	Tasks      ports.TaskRepository
	GraphQuery ports.GraphQueryRepository
	Codebases  ports.CodebaseRepository
	DomainPool ports.DomainPoolRepository
}

// RepositoriesFrom adapts one composite repository at the process wiring edge.
func RepositoriesFrom(repo ports.Repository) Repositories {
	tasks, _ := repo.(ports.TaskRepository)
	graphQuery, _ := repo.(ports.GraphQueryRepository)
	codebases, _ := repo.(ports.CodebaseRepository)
	domainPool, _ := repo.(ports.DomainPoolRepository)
	return Repositories{Memory: repo, Tasks: tasks, GraphQuery: graphQuery, Codebases: codebases, DomainPool: domainPool}
}

// Service provides process-boundary-safe memory operations.
type Service struct {
	repo               ports.Repository
	taskRepo           ports.TaskRepository
	graphQueryRepo     ports.GraphQueryRepository
	codebaseRepo       ports.CodebaseRepository
	domainPoolRepo     ports.DomainPoolRepository
	steward            ports.Steward
	firewallPolicy     *FirewallPolicy
	firewallPolicyPath string
	firewallPolicyMu   sync.Mutex
	workerCount        int
	pollInterval       time.Duration
	cancel             context.CancelFunc
	done               chan struct{}
	startOnce          sync.Once
	stopOnce           sync.Once
}

// New creates a memory service backed by the given repository.
func New(repos Repositories, steward ports.Steward, cfg Config) *Service {
	if cfg.WorkerCount <= 0 {
		cfg.WorkerCount = 2
	}
	if cfg.PollInterval <= 0 {
		cfg.PollInterval = 250 * time.Millisecond
	}
	return &Service{
		repo:               repos.Memory,
		taskRepo:           repos.Tasks,
		graphQueryRepo:     repos.GraphQuery,
		codebaseRepo:       repos.Codebases,
		domainPoolRepo:     repos.DomainPool,
		steward:            steward,
		firewallPolicy:     cfg.FirewallPolicy,
		firewallPolicyPath: strings.TrimSpace(cfg.FirewallPolicyPath),
		workerCount:        cfg.WorkerCount,
		pollInterval:       cfg.PollInterval,
		done:               make(chan struct{}),
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

// Capture synchronously stores raw source content and schedules enrichment.
func (s *Service) Capture(ctx context.Context, req domain.CaptureRequest) (domain.CaptureResult, error) {
	normalized, err := domain.NormalizeCaptureRequest(req)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	if err := s.authorizeWrite(normalized.Actor, normalized.DomainID); err != nil {
		return domain.CaptureResult{}, err
	}
	req = normalized
	return s.repo.Capture(ctx, req)
}

// SearchMemory returns ordered memory search results.
func (s *Service) SearchMemory(ctx context.Context, q domain.RetrievalQuery) (domain.RetrievalBundle, error) {
	normalized, err := domain.NormalizeRetrievalQuery(q)
	if err != nil {
		return domain.RetrievalBundle{}, err
	}
	if err := s.authorizeRetrieval(normalized); err != nil {
		return domain.RetrievalBundle{}, err
	}
	q = normalized
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
func (s *Service) LoadEntityPage(ctx context.Context, domainID domain.DomainID, entityID domain.EntityID, title string) (domain.CompiledPage, error) {
	return s.LoadEntityPageForActor(ctx, "agent", domainID, entityID, title)
}

// LoadEntityPageForActor returns a compiled entity page after domain authorization.
func (s *Service) LoadEntityPageForActor(ctx context.Context, actor string, domainID domain.DomainID, entityID domain.EntityID, title string) (domain.CompiledPage, error) {
	req, err := domain.NormalizeRefreshPageRequest(domain.RefreshPageRequest{Actor: actor, Kind: domain.KindEntityPage, DomainID: domainID, EntityID: entityID, Title: title})
	if err != nil {
		return domain.CompiledPage{}, err
	}
	if err := s.authorizeWrite(req.Actor, req.DomainID); err != nil {
		return domain.CompiledPage{}, err
	}
	return s.repo.LoadEntityPage(ctx, req.DomainID, req.EntityID, req.Title)
}

// LoadTimeline returns a compiled timeline, creating it if necessary.
func (s *Service) LoadTimeline(ctx context.Context, domainID domain.DomainID, topic string, entityID domain.EntityID) (domain.CompiledPage, error) {
	return s.LoadTimelineForActor(ctx, "agent", domainID, topic, entityID)
}

// LoadTimelineForActor returns a compiled timeline after domain authorization.
func (s *Service) LoadTimelineForActor(ctx context.Context, actor string, domainID domain.DomainID, topic string, entityID domain.EntityID) (domain.CompiledPage, error) {
	req, err := domain.NormalizeRefreshPageRequest(domain.RefreshPageRequest{Actor: actor, Kind: domain.KindTimeline, DomainID: domainID, Topic: topic, EntityID: entityID})
	if err != nil {
		return domain.CompiledPage{}, err
	}
	if err := s.authorizeWrite(req.Actor, req.DomainID); err != nil {
		return domain.CompiledPage{}, err
	}
	return s.repo.LoadTimeline(ctx, req.DomainID, req.Topic, req.EntityID)
}

// RefreshCompiledPage rebuilds a compiled knowledge page.
func (s *Service) RefreshCompiledPage(ctx context.Context, req domain.RefreshPageRequest) (domain.CompiledPage, error) {
	normalized, err := domain.NormalizeRefreshPageRequest(req)
	if err != nil {
		return domain.CompiledPage{}, err
	}
	if err := s.authorizeWrite(normalized.Actor, normalized.DomainID); err != nil {
		return domain.CompiledPage{}, err
	}
	req = normalized
	return s.repo.RefreshCompiledPage(ctx, req)
}

// RepairMemoryRecord applies explicit metadata corrections.
func (s *Service) RepairMemoryRecord(ctx context.Context, req domain.RepairRequest) (domain.MemoryRecord, error) {
	normalized, err := domain.NormalizeRepairRequest(req)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	record, err := s.repo.GetMemory(ctx, normalized.MemoryID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	if err := s.authorizeWrite(normalized.Actor, record.DomainID); err != nil {
		return domain.MemoryRecord{}, err
	}
	normalized.DomainID = record.DomainID
	normalized.Firewall = record.DomainID
	req = normalized
	return s.repo.RepairMemory(ctx, req)
}

// SubmitMemoryCorrection stores a correction as source content.
func (s *Service) SubmitMemoryCorrection(ctx context.Context, req domain.CorrectionRequest) (domain.CaptureResult, error) {
	normalized, err := domain.NormalizeCorrectionRequest(req)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	if err := s.authorizeWrite(normalized.Actor, normalized.DomainID); err != nil {
		return domain.CaptureResult{}, err
	}
	req = normalized
	return s.repo.CreateCorrection(ctx, req)
}

// OrganizeMemory runs deterministic memory maintenance and creates follow-up tasks.
func (s *Service) OrganizeMemory(ctx context.Context, req domain.OrganizeMemoryRequest) (domain.OrganizeMemoryResult, error) {
	normalized, err := domain.NormalizeOrganizeMemoryRequest(req)
	if err != nil {
		return domain.OrganizeMemoryResult{}, err
	}
	bundle, err := s.SearchMemory(ctx, domain.RetrievalQuery{
		Actor:                normalized.Actor,
		DomainID:             normalized.DomainID,
		IncludeGlobal:        normalized.IncludeGlobal,
		AllowedSensitivities: normalized.AllowedSensitivities,
		Limit:                normalized.Limit,
	})
	if err != nil {
		return domain.OrganizeMemoryResult{}, err
	}
	result := domain.OrganizeMemoryResult{Reviewed: len(bundle.Primary)}
	for _, record := range bundle.Primary {
		item, task, repaired, err := s.organizeMemoryRecord(ctx, normalized, record)
		if err != nil {
			return domain.OrganizeMemoryResult{}, err
		}
		if len(item.Questions) == 0 && !item.SummaryUpdated {
			continue
		}
		if repaired {
			result.Repaired++
		}
		if task.ID != "" {
			result.FollowUpTasks = append(result.FollowUpTasks, task)
		}
		result.Items = append(result.Items, item)
	}
	return result, nil
}

// QueryContextGraph executes one graph query or audited mutation.
func (s *Service) QueryContextGraph(ctx context.Context, req domain.GraphQueryRequest) (domain.GraphQueryResult, error) {
	repo, err := s.graphQueryRepository()
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	if graphQueryMutates(req.Query) && strings.TrimSpace(req.Actor) == "" {
		return domain.GraphQueryResult{}, errors.New("actor is required for graph mutations")
	}
	normalized, err := domain.NormalizeGraphQueryRequest(req)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	if err := s.authorizeGraphQuery(normalized); err != nil {
		return domain.GraphQueryResult{}, err
	}
	req = normalized
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
	if s.taskRepo == nil {
		return nil, errors.New("task graph repository is not configured")
	}
	return s.taskRepo, nil
}

// graphQueryRepository returns the optional graph query repository.
func (s *Service) graphQueryRepository() (ports.GraphQueryRepository, error) {
	if s.graphQueryRepo == nil {
		return nil, errors.New("graph query repository is not configured")
	}
	return s.graphQueryRepo, nil
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
		return s.auditJob(ctx, worker, job, "duplicate detection completed for checksum-indexed source content")
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
	repair.DomainID = record.DomainID
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
	repair := domain.RepairRequest{Actor: worker, MemoryID: record.ID, DomainID: record.DomainID, Summary: &summary}
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

// organizeMemoryRecord repairs safe metadata and opens human follow-up tasks.
func (s *Service) organizeMemoryRecord(ctx context.Context, req domain.OrganizeMemoryRequest, record domain.MemoryRecord) (domain.MemoryOrganizationItem, domain.Task, bool, error) {
	content, err := s.repo.GetEvidenceContent(ctx, record.EvidenceID)
	if err != nil {
		return domain.MemoryOrganizationItem{}, domain.Task{}, false, err
	}
	item := domain.MemoryOrganizationItem{
		MemoryID:  record.ID,
		Title:     record.Title,
		Questions: memoryFollowUpQuestions(record, content),
	}
	repaired := false
	if strings.TrimSpace(record.Summary) == "" {
		summary := memorySummaryFromContent(content)
		if summary != "" && !req.DryRun {
			_, err := s.RepairMemoryRecord(ctx, domain.RepairRequest{
				Actor:    req.Actor,
				MemoryID: record.ID,
				DomainID: record.DomainID,
				Summary:  &summary,
			})
			if err != nil {
				return domain.MemoryOrganizationItem{}, domain.Task{}, false, err
			}
			item.SummaryUpdated = true
			repaired = true
		} else if summary != "" {
			item.SummaryUpdated = true
		}
	}
	if len(item.Questions) == 0 || req.DryRun {
		return item, domain.Task{}, repaired, nil
	}
	task, err := s.createMemoryFollowUpTask(ctx, req.Actor, record, item.Questions)
	if err != nil {
		return domain.MemoryOrganizationItem{}, domain.Task{}, false, err
	}
	item.FollowUpTaskID = task.ID
	return item, task, repaired, nil
}

// createMemoryFollowUpTask creates an idempotent clarification task.
func (s *Service) createMemoryFollowUpTask(ctx context.Context, actor string, record domain.MemoryRecord, questions []string) (domain.Task, error) {
	repo, err := s.taskRepository()
	if err != nil {
		return domain.Task{}, err
	}
	description := "Answer these questions so Agent Awesome can file this memory correctly:\n- " + strings.Join(questions, "\n- ")
	return repo.CreateTask(ctx, domain.CreateTaskRequest{
		Actor:       actor,
		DomainID:    record.DomainID,
		Title:       "Clarify memory: " + memoryRecordLabel(record),
		Description: description,
		Priority:    domain.TaskPriorityNormal,
		Topics:      []string{"memory", "follow-up"},
		MemoryLinks: []domain.MemoryLinkRequest{
			{
				MemoryID:     string(record.ID),
				Relationship: domain.TaskMemoryOriginatedFrom,
				Note:         "Created by memory organization batch maintenance.",
			},
		},
		IdempotencyKey: "memory-organize-follow-up:" + string(record.ID),
	})
}

// memoryFollowUpQuestions returns user-answerable gaps for one memory record.
func memoryFollowUpQuestions(record domain.MemoryRecord, content string) []string {
	label := memoryRecordLabel(record)
	questions := []string{}
	if strings.EqualFold(strings.TrimSpace(record.Title), "Untitled memory") || strings.TrimSpace(record.Title) == "" {
		questions = append(questions, "What short title should identify this memory?")
	}
	if len(record.Topics) == 0 {
		questions = append(questions, fmt.Sprintf("Which topic should %q belong to?", label))
	}
	if len(record.Subjects) == 0 && len(record.EntityNames) == 0 && len(record.EntityIDs) == 0 {
		questions = append(questions, fmt.Sprintf("Who or what is %q about?", label))
	}
	if len(strings.Fields(content)) < 8 {
		questions = append(questions, fmt.Sprintf("What additional detail should be preserved for %q?", label))
	}
	return questions
}

// memorySummaryFromContent returns a deterministic source-backed summary.
func memorySummaryFromContent(content string) string {
	content = strings.Join(strings.Fields(content), " ")
	if content == "" {
		return ""
	}
	for _, marker := range []string{". ", "! ", "? "} {
		if index := strings.Index(content, marker); index >= 0 {
			return content[:index+1]
		}
	}
	if len(content) <= 180 {
		return content
	}
	runes := []rune(content)
	if len(runes) <= 180 {
		return content
	}
	return strings.TrimSpace(string(runes[:177])) + "..."
}

// memoryRecordLabel returns a compact human label for a memory record.
func memoryRecordLabel(record domain.MemoryRecord) string {
	title := strings.TrimSpace(record.Title)
	if title != "" && !strings.EqualFold(title, "Untitled memory") {
		return title
	}
	if record.Source.System != "" && record.Source.ID != "" {
		return record.Source.System + ":" + record.Source.ID
	}
	return string(record.ID)
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
