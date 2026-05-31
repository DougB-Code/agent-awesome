// This file routes memory operations to one SQLite repository per memory domain.
package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"memory/internal/memory/domain"
	"memory/internal/memory/ports"
)

const domainDatabaseName = "memory.db"

// Pool lazily opens graph repositories keyed by memory domain id.
type Pool struct {
	mu       sync.Mutex
	cfg      Config
	poolRoot string
	repos    map[domain.DomainID]*Repository
}

var _ ports.Repository = (*Pool)(nil)
var _ ports.TaskRepository = (*Pool)(nil)
var _ ports.GraphQueryRepository = (*Pool)(nil)
var _ ports.CodebaseRepository = (*Pool)(nil)
var _ ports.DomainPoolRepository = (*Pool)(nil)

// OpenPool creates a SQLite-backed repository pool rooted under the data directory.
func OpenPool(ctx context.Context, cfg Config) (*Pool, error) {
	pool := &Pool{
		cfg:      cfg,
		poolRoot: normalizedPoolRoot(cfg),
		repos:    map[domain.DomainID]*Repository{},
	}
	if _, err := pool.repoForDomain(ctx, domain.DomainUser); err != nil {
		return nil, err
	}
	return pool, nil
}

// Capture stores memory in the SQLite file selected by request domain metadata.
func (p *Pool) Capture(ctx context.Context, req domain.CaptureRequest) (domain.CaptureResult, error) {
	normalized, err := domain.NormalizeCaptureRequest(req)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	return repo.Capture(ctx, normalized)
}

// Search returns domain-local records, plus global-domain records when requested.
func (p *Pool) Search(ctx context.Context, q domain.RetrievalQuery) ([]domain.MemoryRecord, error) {
	normalized, err := domain.NormalizeRetrievalQuery(q)
	if err != nil {
		return nil, err
	}
	domainIDs := []domain.DomainID{normalized.DomainID}
	if normalized.IncludeGlobal && normalized.DomainID != domain.DomainGlobal {
		domainIDs = append(domainIDs, domain.DomainGlobal)
	}
	records := make([]domain.MemoryRecord, 0, normalized.Limit)
	seen := map[domain.MemoryID]struct{}{}
	for _, domainID := range domainIDs {
		query := normalized
		query.DomainID = domainID
		query.Firewall = domainID
		query.IncludeGlobal = false
		repo, err := p.repoForDomain(ctx, domainID)
		if err != nil {
			return nil, err
		}
		found, err := repo.Search(ctx, query)
		if err != nil {
			return nil, err
		}
		for _, record := range found {
			if _, ok := seen[record.ID]; ok {
				continue
			}
			seen[record.ID] = struct{}{}
			records = append(records, annotateMemoryRecord(record, domainID))
			if len(records) >= normalized.Limit {
				return records, nil
			}
		}
	}
	return records, nil
}

// GetMemory loads one memory record from any known domain database.
func (p *Pool) GetMemory(ctx context.Context, id domain.MemoryID) (domain.MemoryRecord, error) {
	if id == "" {
		return domain.MemoryRecord{}, sql.ErrNoRows
	}
	for _, domainID := range p.knownDomainIDs() {
		repo, err := p.repoForDomain(ctx, domainID)
		if err != nil {
			return domain.MemoryRecord{}, err
		}
		record, err := repo.GetMemory(ctx, id)
		if errors.Is(err, sql.ErrNoRows) {
			continue
		}
		if err != nil {
			return domain.MemoryRecord{}, err
		}
		return annotateMemoryRecord(record, domainID), nil
	}
	return domain.MemoryRecord{}, sql.ErrNoRows
}

// GetEvidenceContent reads source text from any known domain database.
func (p *Pool) GetEvidenceContent(ctx context.Context, id domain.EvidenceID) (string, error) {
	if id == "" {
		return "", sql.ErrNoRows
	}
	for _, domainID := range p.knownDomainIDs() {
		repo, err := p.repoForDomain(ctx, domainID)
		if err != nil {
			return "", err
		}
		content, err := repo.GetEvidenceContent(ctx, id)
		if errors.Is(err, sql.ErrNoRows) {
			continue
		}
		if err != nil {
			return "", err
		}
		return content, nil
	}
	return "", sql.ErrNoRows
}

// RepairMemory updates one record in the selected or discovered domain database.
func (p *Pool) RepairMemory(ctx context.Context, req domain.RepairRequest) (domain.MemoryRecord, error) {
	if explicitDomainID(req.DomainID, req.Firewall) == "" {
		record, err := p.GetMemory(ctx, req.MemoryID)
		if err != nil {
			return domain.MemoryRecord{}, err
		}
		req.DomainID = record.DomainID
		req.Firewall = record.DomainID
	}
	normalized, err := domain.NormalizeRepairRequest(req)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	record, err := repo.RepairMemory(ctx, normalized)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	return annotateMemoryRecord(record, normalized.DomainID), nil
}

// CreateCorrection stores a correction in the selected domain database.
func (p *Pool) CreateCorrection(ctx context.Context, req domain.CorrectionRequest) (domain.CaptureResult, error) {
	normalized, err := domain.NormalizeCorrectionRequest(req)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	return repo.CreateCorrection(ctx, normalized)
}

// RefreshCompiledPage rebuilds a page inside one domain database.
func (p *Pool) RefreshCompiledPage(ctx context.Context, req domain.RefreshPageRequest) (domain.CompiledPage, error) {
	normalized, err := domain.NormalizeRefreshPageRequest(req)
	if err != nil {
		return domain.CompiledPage{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.CompiledPage{}, err
	}
	page, err := repo.RefreshCompiledPage(ctx, normalized)
	if err != nil {
		return domain.CompiledPage{}, err
	}
	return annotateCompiledPage(page, normalized.DomainID), nil
}

// LoadEntityPage loads or builds an entity page in the selected domain.
func (p *Pool) LoadEntityPage(ctx context.Context, domainID domain.DomainID, entityID domain.EntityID, title string) (domain.CompiledPage, error) {
	return p.RefreshCompiledPage(ctx, domain.RefreshPageRequest{Kind: domain.KindEntityPage, DomainID: domainID, EntityID: entityID, Title: title})
}

// LoadTimeline loads or builds a timeline in the selected domain.
func (p *Pool) LoadTimeline(ctx context.Context, domainID domain.DomainID, topic string, entityID domain.EntityID) (domain.CompiledPage, error) {
	return p.RefreshCompiledPage(ctx, domain.RefreshPageRequest{Kind: domain.KindTimeline, DomainID: domainID, Topic: topic, EntityID: entityID})
}

// LeaseJob returns no work because graph-backed capture is synchronous.
func (p *Pool) LeaseJob(context.Context, string) (domain.Job, bool, error) {
	return domain.Job{}, false, nil
}

// CompleteJob is a no-op for graph-backed synchronous capture.
func (p *Pool) CompleteJob(context.Context, domain.JobID, string) error {
	return nil
}

// FailJob is a no-op for graph-backed synchronous capture.
func (p *Pool) FailJob(context.Context, domain.JobID, error) error {
	return nil
}

// ReindexMemory refreshes one memory node in its discovered domain database.
func (p *Pool) ReindexMemory(ctx context.Context, id domain.MemoryID) error {
	record, err := p.GetMemory(ctx, id)
	if err != nil {
		return err
	}
	repo, err := p.repoForDomain(ctx, record.DomainID)
	if err != nil {
		return err
	}
	return repo.ReindexMemory(ctx, id)
}

// AddAudit appends an audit event to the default domain database.
func (p *Pool) AddAudit(ctx context.Context, event domain.AuditEvent) error {
	repo, err := p.repoForDomain(ctx, domain.DomainUser)
	if err != nil {
		return err
	}
	return repo.AddAudit(ctx, event)
}

// Metrics aggregates counters from all known domain databases.
func (p *Pool) Metrics(ctx context.Context) (domain.Metrics, error) {
	total := domain.Metrics{}
	for _, domainID := range p.knownDomainIDs() {
		repo, err := p.repoForDomain(ctx, domainID)
		if err != nil {
			return domain.Metrics{}, err
		}
		metrics, err := repo.Metrics(ctx)
		if err != nil {
			return domain.Metrics{}, err
		}
		total.EvidenceCount += metrics.EvidenceCount
		total.MemoryCount += metrics.MemoryCount
		total.PageCount += metrics.PageCount
		total.PendingJobs += metrics.PendingJobs
		total.FailedJobs += metrics.FailedJobs
		total.RecordsWithSources += metrics.RecordsWithSources
	}
	return total, nil
}

// Close releases every opened domain repository.
func (p *Pool) Close() error {
	p.mu.Lock()
	repos := make([]*Repository, 0, len(p.repos))
	for _, repo := range p.repos {
		repos = append(repos, repo)
	}
	p.repos = map[domain.DomainID]*Repository{}
	p.mu.Unlock()
	var combined error
	for _, repo := range repos {
		combined = errors.Join(combined, repo.Close())
	}
	return combined
}

// ListMemoryDomains returns every open or on-disk domain database in the pool.
func (p *Pool) ListMemoryDomains(context.Context) ([]domain.MemoryDomainInfo, error) {
	ids := p.knownDomainIDs()
	infos := make([]domain.MemoryDomainInfo, 0, len(ids))
	p.mu.Lock()
	open := make(map[domain.DomainID]bool, len(p.repos))
	for domainID := range p.repos {
		open[domainID] = true
	}
	p.mu.Unlock()
	for _, domainID := range ids {
		path := p.domainDBPath(domainID)
		_, statErr := os.Stat(path)
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return nil, fmt.Errorf("stat memory domain %q: %w", domainID, statErr)
		}
		infos = append(infos, domain.MemoryDomainInfo{
			DomainID: domainID,
			Path:     path,
			Open:     open[domainID],
			Exists:   statErr == nil,
		})
	}
	return infos, nil
}

// CreateMemoryDomain creates or opens one domain database without restarting memoryd.
func (p *Pool) CreateMemoryDomain(ctx context.Context, domainID domain.DomainID) (domain.MemoryDomainInfo, error) {
	normalized, err := domain.NormalizeDomainID(domainID, "")
	if err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	if _, err := p.repoForDomain(ctx, normalized); err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	return p.memoryDomainInfo(normalized), nil
}

// RemoveMemoryDomain closes one live pool member and optionally deletes its files.
func (p *Pool) RemoveMemoryDomain(ctx context.Context, domainID domain.DomainID, deleteFiles bool) (domain.MemoryDomainInfo, error) {
	normalized, err := domain.NormalizeDomainID(domainID, "")
	if err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	if normalized == domain.DomainUser {
		return domain.MemoryDomainInfo{}, fmt.Errorf("memory domain %q cannot be removed", normalized)
	}
	p.mu.Lock()
	repo := p.repos[normalized]
	delete(p.repos, normalized)
	p.mu.Unlock()
	if repo != nil {
		if err := repo.Close(); err != nil {
			return domain.MemoryDomainInfo{}, fmt.Errorf("close memory domain %q: %w", normalized, err)
		}
	}
	if deleteFiles {
		root := p.domainRoot(normalized)
		if err := os.RemoveAll(root); err != nil {
			return domain.MemoryDomainInfo{}, fmt.Errorf("delete memory domain %q: %w", normalized, err)
		}
	}
	return p.memoryDomainInfo(normalized), nil
}

// CreateTask stores a task in the selected domain database.
func (p *Pool) CreateTask(ctx context.Context, req domain.CreateTaskRequest) (domain.Task, error) {
	normalized, err := domain.NormalizeCreateTaskRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.Task{}, err
	}
	task, err := repo.CreateTask(ctx, normalized)
	if err != nil {
		return domain.Task{}, err
	}
	return annotateTask(task, normalized.DomainID), nil
}

// GetTask loads one task from the selected domain database.
func (p *Pool) GetTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	normalized, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.Task{}, err
	}
	task, err := repo.GetTask(ctx, normalized)
	if err != nil {
		return domain.Task{}, err
	}
	return annotateTask(task, normalized.DomainID), nil
}

// ListTasks lists tasks from the selected domain database.
func (p *Pool) ListTasks(ctx context.Context, q domain.TaskQuery) ([]domain.Task, error) {
	normalized, err := domain.NormalizeTaskQuery(q)
	if err != nil {
		return nil, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return nil, err
	}
	tasks, err := repo.ListTasks(ctx, normalized)
	if err != nil {
		return nil, err
	}
	for index := range tasks {
		tasks[index] = annotateTask(tasks[index], normalized.DomainID)
	}
	return tasks, nil
}

// TaskGraphProjection returns a task graph from the selected domain database.
func (p *Pool) TaskGraphProjection(ctx context.Context, q domain.TaskGraphProjectionQuery) (domain.TaskGraphProjection, error) {
	normalized, err := domain.NormalizeTaskGraphProjectionQuery(q)
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.Tasks.DomainID)
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	projection, err := repo.TaskGraphProjection(ctx, normalized)
	if err != nil {
		return domain.TaskGraphProjection{}, err
	}
	return annotateTaskProjection(projection, normalized.Tasks.DomainID), nil
}

// UpdateTask patches a task in the selected domain database.
func (p *Pool) UpdateTask(ctx context.Context, req domain.UpdateTaskRequest) (domain.Task, error) {
	normalized, err := domain.NormalizeUpdateTaskRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.Task{}, err
	}
	task, err := repo.UpdateTask(ctx, normalized)
	if err != nil {
		return domain.Task{}, err
	}
	return annotateTask(task, normalized.DomainID), nil
}

// CompleteTask marks one task done in the selected domain database.
func (p *Pool) CompleteTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	normalized, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.Task{}, err
	}
	task, err := repo.CompleteTask(ctx, normalized)
	if err != nil {
		return domain.Task{}, err
	}
	return annotateTask(task, normalized.DomainID), nil
}

// CancelTask marks one task canceled in the selected domain database.
func (p *Pool) CancelTask(ctx context.Context, req domain.TaskIDRequest) (domain.Task, error) {
	normalized, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return domain.Task{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.Task{}, err
	}
	task, err := repo.CancelTask(ctx, normalized)
	if err != nil {
		return domain.Task{}, err
	}
	return annotateTask(task, normalized.DomainID), nil
}

// DeleteTask lifecycle-deletes one task in the selected domain database.
func (p *Pool) DeleteTask(ctx context.Context, req domain.TaskIDRequest) error {
	normalized, err := domain.NormalizeTaskIDRequest(req)
	if err != nil {
		return err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return err
	}
	return repo.DeleteTask(ctx, normalized)
}

// LinkTaskMemory attaches memory context inside the selected domain database.
func (p *Pool) LinkTaskMemory(ctx context.Context, req domain.LinkTaskMemoryRequest) (domain.MemoryLink, error) {
	normalized, err := domain.NormalizeLinkTaskMemoryRequest(req)
	if err != nil {
		return domain.MemoryLink{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.MemoryLink{}, err
	}
	return repo.LinkTaskMemory(ctx, normalized)
}

// ListTaskRelations lists task edges in the selected domain database.
func (p *Pool) ListTaskRelations(ctx context.Context, q domain.TaskRelationQuery) ([]domain.TaskRelation, error) {
	normalized, err := domain.NormalizeTaskRelationQuery(q)
	if err != nil {
		return nil, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return nil, err
	}
	relations, err := repo.ListTaskRelations(ctx, normalized)
	if err != nil {
		return nil, err
	}
	for index := range relations {
		relations[index] = annotateTaskRelation(relations[index], normalized.DomainID)
	}
	return relations, nil
}

// TraverseTaskRelations traverses task edges in the selected domain database.
func (p *Pool) TraverseTaskRelations(ctx context.Context, q domain.TaskRelationTraversalQuery) (domain.TaskRelationTraversal, error) {
	normalized, err := domain.NormalizeTaskRelationTraversalQuery(q)
	if err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	traversal, err := repo.TraverseTaskRelations(ctx, normalized)
	if err != nil {
		return domain.TaskRelationTraversal{}, err
	}
	for pathIndex := range traversal.Paths {
		for taskIndex := range traversal.Paths[pathIndex].Tasks {
			traversal.Paths[pathIndex].Tasks[taskIndex] = annotateTask(traversal.Paths[pathIndex].Tasks[taskIndex], normalized.DomainID)
		}
		for relationIndex := range traversal.Paths[pathIndex].Relations {
			traversal.Paths[pathIndex].Relations[relationIndex] = annotateTaskRelation(traversal.Paths[pathIndex].Relations[relationIndex], normalized.DomainID)
		}
	}
	return traversal, nil
}

// UpsertTaskRelation writes one task edge in the selected domain database.
func (p *Pool) UpsertTaskRelation(ctx context.Context, req domain.UpsertTaskRelationRequest) (domain.TaskRelation, error) {
	normalized, err := domain.NormalizeUpsertTaskRelationRequest(req)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	relation, err := repo.UpsertTaskRelation(ctx, normalized)
	if err != nil {
		return domain.TaskRelation{}, err
	}
	return annotateTaskRelation(relation, normalized.DomainID), nil
}

// DeleteTaskRelation deletes one task edge in the selected domain database.
func (p *Pool) DeleteTaskRelation(ctx context.Context, req domain.DeleteTaskRelationRequest) error {
	normalized, err := domain.NormalizeDeleteTaskRelationRequest(req)
	if err != nil {
		return err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return err
	}
	return repo.DeleteTaskRelation(ctx, normalized)
}

// QueryContextGraph executes a graph query inside the selected domain database.
func (p *Pool) QueryContextGraph(ctx context.Context, req domain.GraphQueryRequest) (domain.GraphQueryResult, error) {
	normalized, err := domain.NormalizeGraphQueryRequest(req)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	repo, err := p.repoForDomain(ctx, normalized.DomainID)
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	return repo.QueryContextGraph(ctx, normalized)
}

// UpsertCodebase stores one codebase in the default domain database.
func (p *Pool) UpsertCodebase(ctx context.Context, req domain.UpsertCodebaseRequest) (domain.Codebase, error) {
	repo, err := p.repoForDomain(ctx, domain.DomainUser)
	if err != nil {
		return domain.Codebase{}, err
	}
	return repo.UpsertCodebase(ctx, req)
}

// GetCodebase loads one codebase from the default domain database.
func (p *Pool) GetCodebase(ctx context.Context, req domain.CodebaseIDRequest) (domain.Codebase, error) {
	repo, err := p.repoForDomain(ctx, domain.DomainUser)
	if err != nil {
		return domain.Codebase{}, err
	}
	return repo.GetCodebase(ctx, req)
}

// ListCodebases lists codebases from the default domain database.
func (p *Pool) ListCodebases(ctx context.Context, req domain.CodebaseQuery) ([]domain.Codebase, error) {
	repo, err := p.repoForDomain(ctx, domain.DomainUser)
	if err != nil {
		return nil, err
	}
	return repo.ListCodebases(ctx, req)
}

// ResolveCodebase resolves a codebase from the default domain database.
func (p *Pool) ResolveCodebase(ctx context.Context, req domain.ResolveCodebaseRequest) (domain.CodebaseResolution, error) {
	repo, err := p.repoForDomain(ctx, domain.DomainUser)
	if err != nil {
		return domain.CodebaseResolution{}, err
	}
	return repo.ResolveCodebase(ctx, req)
}

// DeleteCodebase removes a codebase from the default domain database.
func (p *Pool) DeleteCodebase(ctx context.Context, req domain.CodebaseIDRequest) error {
	repo, err := p.repoForDomain(ctx, domain.DomainUser)
	if err != nil {
		return err
	}
	return repo.DeleteCodebase(ctx, req)
}

// repoForDomain returns an opened repository for a safe memory domain id.
func (p *Pool) repoForDomain(ctx context.Context, domainID domain.DomainID) (*Repository, error) {
	normalized, err := domain.NormalizeDomainID(domainID, "")
	if err != nil {
		return nil, err
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if repo, ok := p.repos[normalized]; ok {
		return repo, nil
	}
	root := p.domainRoot(normalized)
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, fmt.Errorf("create memory domain root %q: %w", root, err)
	}
	repo, err := Open(ctx, Config{
		DBPath:   filepath.Join(root, domainDatabaseName),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		return nil, err
	}
	p.repos[normalized] = repo
	return repo, nil
}

// domainRoot returns the filesystem root for one domain database.
func (p *Pool) domainRoot(domainID domain.DomainID) string {
	return filepath.Join(p.poolRoot, string(domainID))
}

// domainDBPath returns the SQLite path for one domain database.
func (p *Pool) domainDBPath(domainID domain.DomainID) string {
	return filepath.Join(p.domainRoot(domainID), domainDatabaseName)
}

// memoryDomainInfo returns current pool state for one normalized domain.
func (p *Pool) memoryDomainInfo(domainID domain.DomainID) domain.MemoryDomainInfo {
	p.mu.Lock()
	_, open := p.repos[domainID]
	p.mu.Unlock()
	path := p.domainDBPath(domainID)
	_, statErr := os.Stat(path)
	return domain.MemoryDomainInfo{
		DomainID: domainID,
		Path:     path,
		Open:     open,
		Exists:   statErr == nil,
	}
}

// knownDomainIDs returns every currently opened or on-disk memory domain id.
func (p *Pool) knownDomainIDs() []domain.DomainID {
	seen := map[domain.DomainID]struct{}{domain.DomainUser: {}}
	p.mu.Lock()
	for domainID := range p.repos {
		seen[domainID] = struct{}{}
	}
	p.mu.Unlock()
	entries, err := os.ReadDir(p.poolRoot)
	if err == nil {
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			domainID := domain.DomainID(entry.Name())
			if !domain.ValidDomainID(domainID) {
				continue
			}
			seen[domainID] = struct{}{}
		}
	}
	ids := make([]domain.DomainID, 0, len(seen))
	for domainID := range seen {
		ids = append(ids, domainID)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
}

// normalizedPoolRoot derives a private domain database root from repository config.
func normalizedPoolRoot(cfg Config) string {
	if strings.TrimSpace(cfg.PoolRoot) != "" {
		return cfg.PoolRoot
	}
	dataRoot := strings.TrimSpace(cfg.DataRoot)
	if dataRoot == "" {
		dataRoot = "data"
	}
	return filepath.Join(dataRoot, "domains")
}

// explicitDomainID returns the caller-provided domain id before defaulting.
func explicitDomainID(domainID domain.DomainID, legacy domain.Firewall) domain.DomainID {
	if strings.TrimSpace(string(domainID)) != "" {
		return domain.DomainID(strings.TrimSpace(string(domainID)))
	}
	return domain.DomainID(strings.TrimSpace(string(legacy)))
}

// annotateMemoryRecord attaches service routing metadata to a boundary-local record.
func annotateMemoryRecord(record domain.MemoryRecord, domainID domain.DomainID) domain.MemoryRecord {
	record.DomainID = domainID
	record.Firewall = domainID
	return record
}

// annotateCompiledPage attaches service routing metadata to a boundary-local page.
func annotateCompiledPage(page domain.CompiledPage, domainID domain.DomainID) domain.CompiledPage {
	page.DomainID = domainID
	page.Firewall = domainID
	return page
}

// annotateTask attaches service routing metadata to a boundary-local task.
func annotateTask(task domain.Task, domainID domain.DomainID) domain.Task {
	task.DomainID = domainID
	task.Firewall = domainID
	return task
}

// annotateTaskRelation attaches service routing metadata to a boundary-local task edge.
func annotateTaskRelation(relation domain.TaskRelation, domainID domain.DomainID) domain.TaskRelation {
	relation.DomainID = domainID
	relation.Firewall = domainID
	return relation
}

// annotateTaskProjection attaches service routing metadata across task graph projections.
func annotateTaskProjection(projection domain.TaskGraphProjection, domainID domain.DomainID) domain.TaskGraphProjection {
	for index := range projection.Tasks {
		projection.Tasks[index] = annotateTask(projection.Tasks[index], domainID)
	}
	for index := range projection.Relations {
		projection.Relations[index] = annotateTaskRelation(projection.Relations[index], domainID)
	}
	for index := range projection.Nodes {
		if projection.Nodes[index].Task != nil {
			task := annotateTask(*projection.Nodes[index].Task, domainID)
			projection.Nodes[index].Task = &task
		}
	}
	for index := range projection.Edges {
		if projection.Edges[index].Relation != nil {
			relation := annotateTaskRelation(*projection.Edges[index].Relation, domainID)
			projection.Edges[index].Relation = &relation
		}
	}
	return projection
}
