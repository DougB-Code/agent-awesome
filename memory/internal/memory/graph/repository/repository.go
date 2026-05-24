// This file projects memory service operations onto the context graph store.
package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"sort"
	"strings"

	"memory/internal/memory/domain"
	graph "memory/internal/memory/graph/domain"
	graphquery "memory/internal/memory/graph/query"
	graphstore "memory/internal/memory/graph/store"
	"memory/internal/memory/ports"
)

const (
	propertyEventTime      = "event_time"
	propertyIdempotencyKey = "idempotency_key"
	propertyMemoryKind     = "memory_kind"
	propertySourceID       = "source_id"
	propertySourceSystem   = "source_system"
	searchCandidateLimit   = 100
)

// Config contains graph repository storage settings.
type Config struct {
	DBPath   string
	DataRoot string
}

// Repository projects memory service operations onto graph storage.
type Repository struct {
	graph *graphstore.Store
}

var _ ports.Repository = (*Repository)(nil)
var _ ports.GraphQueryRepository = (*Repository)(nil)
var _ ports.CodebaseRepository = (*Repository)(nil)

// Open creates a graph-backed memory repository.
func Open(ctx context.Context, cfg Config) (*Repository, error) {
	store, err := graphstore.Open(ctx, graphstore.Config{DBPath: cfg.DBPath, DataRoot: cfg.DataRoot})
	if err != nil {
		return nil, err
	}
	return &Repository{graph: store}, nil
}

// Close releases graph storage resources.
func (r *Repository) Close() error {
	if r == nil || r.graph == nil {
		return nil
	}
	return r.graph.Close()
}

// QueryContextGraph executes one graph query or audited mutation.
func (r *Repository) QueryContextGraph(ctx context.Context, req domain.GraphQueryRequest) (domain.GraphQueryResult, error) {
	executor := graphquery.NewExecutor(r.graph)
	result, err := executor.Execute(ctx, graphQueryRequest(req))
	if err != nil {
		return domain.GraphQueryResult{}, err
	}
	return graphQueryResult(result), nil
}

// graphQueryRequest converts service-level graph query metadata to graph-native execution input.
func graphQueryRequest(req domain.GraphQueryRequest) graphquery.Request {
	return graphquery.Request{
		Actor:                req.Actor,
		Query:                req.Query,
		SourceNodeID:         req.SourceNodeID,
		Firewall:             req.Firewall,
		IncludeGlobal:        req.IncludeGlobal,
		AllowedSensitivities: req.AllowedSensitivities,
	}
}

// graphQueryResult converts graph-native execution output to service DTOs.
func graphQueryResult(result graphquery.Result) domain.GraphQueryResult {
	rows := make([]domain.GraphQueryRow, 0, len(result.Rows))
	for _, row := range result.Rows {
		converted := domain.GraphQueryRow{}
		for key, value := range row {
			converted[key] = value
		}
		rows = append(rows, converted)
	}
	paths := make([]domain.GraphQueryPath, 0, len(result.Paths))
	for _, path := range result.Paths {
		paths = append(paths, domain.GraphQueryPath{
			RowIndex: path.RowIndex,
			Depth:    path.Depth,
			NodeIDs:  append([]string{}, path.NodeIDs...),
			EdgeIDs:  append([]string{}, path.EdgeIDs...),
		})
	}
	return domain.GraphQueryResult{
		Columns: append([]string{}, result.Columns...),
		Rows:    rows,
		Paths:   paths,
		Limit:   result.Limit,
		Query:   result.Query,
	}
}

// Capture stores memory as graph nodes, edges, properties, aliases, evidence, and audit.
func (r *Repository) Capture(ctx context.Context, req domain.CaptureRequest) (domain.CaptureResult, error) {
	req, err := domain.NormalizeCaptureRequest(req)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	if req.IdempotencyKey != "" {
		result, ok, err := r.captureByIdempotency(ctx, req.IdempotencyKey)
		if err != nil || ok {
			return result, err
		}
	}
	var result domain.CaptureResult
	if err := r.graph.WithUnitOfWork(ctx, func(graphStore *graphstore.Store) error {
		txRepo := *r
		txRepo.graph = graphStore
		if req.IdempotencyKey != "" {
			duplicate, ok, err := txRepo.captureByIdempotency(ctx, req.IdempotencyKey)
			if err != nil {
				return err
			}
			if ok {
				result = duplicate
				return nil
			}
		}
		captured, err := txRepo.captureNormalized(ctx, req)
		if err != nil {
			return err
		}
		result = captured
		return nil
	}); err != nil {
		return domain.CaptureResult{}, err
	}
	return result, nil
}

// captureNormalized writes a normalized capture request into the active graph store.
func (r *Repository) captureNormalized(ctx context.Context, req domain.CaptureRequest) (domain.CaptureResult, error) {
	summary := excerpt(req.Content, 280)
	evidence, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:        graph.KindEvidence,
		StableKey:   evidenceStableKey(req.IdempotencyKey),
		Title:       req.Title,
		Summary:     summary,
		Firewall:    req.Firewall,
		Sensitivity: req.Sensitivity,
		TrustLevel:  graph.TrustSourceOriginal,
		Actor:       req.Actor,
	})
	if err != nil {
		return domain.CaptureResult{}, err
	}
	if _, err := r.graph.WriteEvidenceBlob(ctx, graph.WriteEvidenceBlobRequest{
		NodeID:       evidence.ID,
		Content:      req.Content,
		MediaType:    req.MediaType,
		SourceSystem: req.Source.System,
		SourceID:     req.Source.ID,
		SourceNodeID: evidence.ID,
		Actor:        req.Actor,
	}); err != nil {
		return domain.CaptureResult{}, err
	}
	memory, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:        graph.KindMemory,
		StableKey:   memoryStableKey(req.IdempotencyKey),
		Title:       req.Title,
		Summary:     summary,
		Firewall:    req.Firewall,
		Sensitivity: req.Sensitivity,
		TrustLevel:  req.TrustLevel,
		Actor:       req.Actor,
	})
	if err != nil {
		return domain.CaptureResult{}, err
	}
	if err := r.writeCaptureFacts(ctx, req, memory, evidence); err != nil {
		return domain.CaptureResult{}, err
	}
	if _, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID:   memory.ID,
		Type:         graph.RelationCapturedFrom,
		ToNodeID:     evidence.ID,
		SourceNodeID: evidence.ID,
		TrustLevel:   graph.TrustSourceOriginal,
		Actor:        req.Actor,
	}); err != nil {
		return domain.CaptureResult{}, err
	}
	if err := r.writeFacets(ctx, memory.ID, evidence.ID, req.Actor, req.Subjects, req.Topics, req.EntityNames); err != nil {
		return domain.CaptureResult{}, err
	}
	if _, err := r.graph.UpsertAlias(ctx, graph.UpsertAliasRequest{NodeID: memory.ID, Alias: req.Title, Kind: "title"}); err != nil {
		return domain.CaptureResult{}, err
	}
	if err := r.graph.ReindexNode(ctx, evidence.ID); err != nil {
		return domain.CaptureResult{}, err
	}
	if err := r.graph.ReindexNode(ctx, memory.ID); err != nil {
		return domain.CaptureResult{}, err
	}
	if _, err := r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "capture",
		Actor:         req.Actor,
		SubjectNodeID: memory.ID,
		SourceNodeID:  evidence.ID,
		Message:       "captured source content and projected it into the context graph",
	}); err != nil {
		return domain.CaptureResult{}, err
	}
	return domain.CaptureResult{EvidenceID: domain.EvidenceID(evidence.ID), MemoryID: domain.MemoryID(memory.ID), JobIDs: nil, Duplicate: false}, nil
}

// Search returns graph-backed memory records matching retrieval filters.
func (r *Repository) Search(ctx context.Context, q domain.RetrievalQuery) ([]domain.MemoryRecord, error) {
	q, err := domain.NormalizeRetrievalQuery(q)
	if err != nil {
		return nil, err
	}
	nodes, err := r.graph.SearchNodes(ctx, graph.SearchNodesQuery{
		Text:                 q.Text,
		Kinds:                []graph.NodeKind{graph.KindMemory},
		Firewall:             q.Firewall,
		IncludeGlobal:        q.IncludeGlobal,
		AllowedSensitivities: q.AllowedSensitivities,
		Limit:                searchCandidateLimit,
	})
	if err != nil {
		return nil, err
	}
	records := []domain.MemoryRecord{}
	for _, node := range nodes {
		record, err := r.GetMemory(ctx, domain.MemoryID(node.ID))
		if err != nil {
			return nil, err
		}
		if !recordMatches(record, q) {
			continue
		}
		records = append(records, record)
		if len(records) >= q.Limit {
			break
		}
	}
	return records, nil
}

// GetMemory projects one memory node into a memory record.
func (r *Repository) GetMemory(ctx context.Context, memoryID domain.MemoryID) (domain.MemoryRecord, error) {
	node, err := r.graph.GetNode(ctx, graph.NodeID(memoryID))
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	if node.Kind != graph.KindMemory {
		return domain.MemoryRecord{}, sql.ErrNoRows
	}
	properties, err := r.propertyMap(ctx, node.ID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	evidence, raw, err := r.capturedEvidence(ctx, node.ID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	subjects, err := r.edgeNodeTitles(ctx, node.ID, graph.RelationAbout)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	topics, err := r.edgeNodeTitles(ctx, node.ID, graph.RelationTaggedWith)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	entityIDs, entityNames, err := r.edgeEntityNodes(ctx, node.ID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	relationships, err := r.memoryRelationships(ctx, node.ID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	record := domain.MemoryRecord{
		ID:          domain.MemoryID(node.ID),
		EvidenceID:  domain.EvidenceID(evidence.ID),
		Kind:        domain.Kind(propertyText(properties[propertyMemoryKind], string(domain.KindDocument))),
		Firewall:    node.Firewall,
		TrustLevel:  node.TrustLevel,
		Sensitivity: node.Sensitivity,
		Status:      fromGraphStatus(node.Status),
		Title:       node.Title,
		Summary:     node.Summary,
		Subjects:    subjects,
		Topics:      topics,
		EntityIDs:   entityIDs,
		EntityNames: entityNames,
		CreatedAt:   node.CreatedAt,
		UpdatedAt:   node.UpdatedAt,
		Idempotency: propertyText(properties[propertyIdempotencyKey], ""),
		Source: domain.SourceRef{
			System: propertyText(properties[propertySourceSystem], ""),
			ID:     propertyText(properties[propertySourceID], ""),
		},
		Raw:           raw,
		Relationships: relationships,
	}
	if eventTime := properties[propertyEventTime].Value.Time; eventTime != nil {
		record.EventTime = eventTime
	}
	record.Raw.Source = record.Source
	record.Raw.Idempotency = record.Idempotency
	return record, nil
}

// GetEvidenceContent reads source text for an evidence node.
func (r *Repository) GetEvidenceContent(ctx context.Context, evidenceID domain.EvidenceID) (string, error) {
	return r.graph.ReadEvidenceBlobContent(ctx, graph.NodeID(evidenceID))
}

// RepairMemory applies metadata corrections to graph-backed memory.
func (r *Repository) RepairMemory(ctx context.Context, req domain.RepairRequest) (domain.MemoryRecord, error) {
	replaceSubjects := req.Subjects != nil
	replaceTopics := req.Topics != nil
	replaceEntities := req.EntityNames != nil
	req, err := domain.NormalizeRepairRequest(req)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	record, err := r.GetMemory(ctx, req.MemoryID)
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	title := record.Title
	if req.Title != nil {
		title = strings.TrimSpace(*req.Title)
	}
	summary := record.Summary
	if req.Summary != nil {
		summary = strings.TrimSpace(*req.Summary)
	}
	sensitivity := record.Sensitivity
	if req.Sensitivity != nil {
		sensitivity = *req.Sensitivity
	}
	status := record.Status
	if req.Status != nil {
		status = *req.Status
	}
	existingNode, err := r.graph.GetNode(ctx, graph.NodeID(req.MemoryID))
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	node, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		NodeID:      graph.NodeID(req.MemoryID),
		Kind:        graph.KindMemory,
		StableKey:   existingNode.StableKey,
		Title:       title,
		Summary:     summary,
		Status:      status,
		Firewall:    record.Firewall,
		Sensitivity: sensitivity,
		TrustLevel:  record.TrustLevel,
		Actor:       req.Actor,
	})
	if err != nil {
		return domain.MemoryRecord{}, err
	}
	if req.Kind != nil {
		if _, err := r.graph.UpsertNodeProperty(ctx, graph.UpsertNodePropertyRequest{
			NodeID: node.ID,
			Key:    propertyMemoryKind,
			Value:  graph.Value{Type: graph.ValueText, Text: string(*req.Kind)},
			Actor:  req.Actor,
		}); err != nil {
			return domain.MemoryRecord{}, err
		}
	}
	evidenceID := graph.NodeID(record.EvidenceID)
	if replaceSubjects {
		if err := r.replaceFacetEdges(ctx, node.ID, evidenceID, req.Actor, graph.RelationAbout, req.Subjects, "subject"); err != nil {
			return domain.MemoryRecord{}, err
		}
	}
	if replaceTopics {
		if err := r.replaceFacetEdges(ctx, node.ID, evidenceID, req.Actor, graph.RelationTaggedWith, req.Topics, "topic"); err != nil {
			return domain.MemoryRecord{}, err
		}
	}
	if replaceEntities {
		if err := r.replaceEntityEdges(ctx, node.ID, evidenceID, req.Actor, req.EntityNames); err != nil {
			return domain.MemoryRecord{}, err
		}
	}
	if err := r.graph.ReindexNode(ctx, node.ID); err != nil {
		return domain.MemoryRecord{}, err
	}
	if _, err := r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		Kind:          "memory_repair",
		Actor:         req.Actor,
		SubjectNodeID: node.ID,
		SourceNodeID:  evidenceID,
		Message:       "repaired graph-backed memory metadata",
	}); err != nil {
		return domain.MemoryRecord{}, err
	}
	return r.GetMemory(ctx, req.MemoryID)
}

// CreateCorrection stores a correction and links it to the corrected memory.
func (r *Repository) CreateCorrection(ctx context.Context, req domain.CorrectionRequest) (domain.CaptureResult, error) {
	req, err := domain.NormalizeCorrectionRequest(req)
	if err != nil {
		return domain.CaptureResult{}, err
	}
	result, err := r.Capture(ctx, domain.CaptureRequest{
		Actor:          req.Actor,
		Content:        req.Text,
		Title:          "Memory correction",
		Source:         domain.SourceRef{System: "memory_correction", ID: string(req.MemoryID)},
		Kind:           domain.KindDocument,
		Firewall:       req.Firewall,
		TrustLevel:     domain.TrustUserAsserted,
		Sensitivity:    domain.SensitivityPrivate,
		Topics:         []string{"correction"},
		IdempotencyKey: fmt.Sprintf("correction:%s:%x", req.MemoryID, req.Text),
	})
	if err != nil {
		return domain.CaptureResult{}, err
	}
	if _, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{
		FromNodeID:   graph.NodeID(result.MemoryID),
		Type:         graph.RelationRefersTo,
		ToNodeID:     graph.NodeID(req.MemoryID),
		SourceNodeID: graph.NodeID(result.EvidenceID),
		TrustLevel:   graph.TrustUserAsserted,
		Actor:        req.Actor,
	}); err != nil {
		return domain.CaptureResult{}, err
	}
	return result, nil
}

// RefreshCompiledPage returns a source-backed page projection over graph memories.
func (r *Repository) RefreshCompiledPage(ctx context.Context, req domain.RefreshPageRequest) (domain.CompiledPage, error) {
	req, err := domain.NormalizeRefreshPageRequest(req)
	if err != nil {
		return domain.CompiledPage{}, err
	}
	title := req.Title
	query := domain.RetrievalQuery{Actor: req.Actor, Firewall: req.Firewall, Limit: searchCandidateLimit}
	if req.Topic != "" {
		query.Topics = []string{req.Topic}
		if title == "" {
			title = req.Topic
		}
	}
	if req.EntityID != "" {
		query.EntityIDs = []domain.EntityID{req.EntityID}
		if title == "" {
			if node, err := r.graph.GetNode(ctx, graph.NodeID(req.EntityID)); err == nil {
				title = node.Title
			}
		}
	}
	if title == "" {
		title = string(req.Kind)
	}
	records, err := r.Search(ctx, query)
	if err != nil {
		return domain.CompiledPage{}, err
	}
	content, sourceIDs := buildCompiledPageContent(req.Kind, title, records)
	pageNode, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
		Kind:      graph.KindArtifact,
		StableKey: pageStableKey(req.Kind, req.Firewall, title),
		Title:     title,
		Summary:   excerpt(content, 280),
		Firewall:  req.Firewall,
		Actor:     req.Actor,
	})
	if err != nil {
		return domain.CompiledPage{}, err
	}
	return domain.CompiledPage{
		ID:        domain.PageID(pageNode.ID),
		Kind:      req.Kind,
		Firewall:  req.Firewall,
		Title:     title,
		Status:    domain.StatusActive,
		SourceIDs: sourceIDs,
		Content:   content,
		CreatedAt: pageNode.CreatedAt,
		UpdatedAt: pageNode.UpdatedAt,
	}, nil
}

// LoadEntityPage returns a compiled entity page projection.
func (r *Repository) LoadEntityPage(ctx context.Context, firewall domain.Firewall, entityID domain.EntityID, title string) (domain.CompiledPage, error) {
	if title == "" {
		if node, err := r.graph.GetNode(ctx, graph.NodeID(entityID)); err == nil {
			title = node.Title
		}
	}
	return r.RefreshCompiledPage(ctx, domain.RefreshPageRequest{Kind: domain.KindEntityPage, Firewall: firewall, EntityID: entityID, Title: title})
}

// LoadTimeline returns a compiled timeline projection.
func (r *Repository) LoadTimeline(ctx context.Context, firewall domain.Firewall, topic string, entityID domain.EntityID) (domain.CompiledPage, error) {
	return r.RefreshCompiledPage(ctx, domain.RefreshPageRequest{Kind: domain.KindTimeline, Firewall: firewall, Topic: topic, EntityID: entityID})
}

// LeaseJob returns no work because graph-backed Phase 2 capture is synchronous.
func (r *Repository) LeaseJob(context.Context, string) (domain.Job, bool, error) {
	return domain.Job{}, false, nil
}

// CompleteJob is a no-op for graph-backed synchronous capture.
func (r *Repository) CompleteJob(context.Context, domain.JobID, string) error {
	return nil
}

// FailJob is a no-op for graph-backed synchronous capture.
func (r *Repository) FailJob(context.Context, domain.JobID, error) error {
	return nil
}

// ReindexMemory refreshes lexical search for a graph-backed memory node.
func (r *Repository) ReindexMemory(ctx context.Context, memoryID domain.MemoryID) error {
	return r.graph.ReindexNode(ctx, graph.NodeID(memoryID))
}

// AddAudit appends a graph audit event.
func (r *Repository) AddAudit(ctx context.Context, event domain.AuditEvent) error {
	_, err := r.graph.AppendAudit(ctx, graph.AppendAuditRequest{
		AuditID:       graph.AuditID(event.ID),
		Kind:          event.Kind,
		Actor:         event.Actor,
		SubjectNodeID: graph.NodeID(event.SubjectID),
		SourceNodeID:  graph.NodeID(event.SourceID),
		Message:       event.Message,
		DetailsJSON:   event.Details,
	})
	return err
}

// Metrics returns graph-backed memory counters.
func (r *Repository) Metrics(ctx context.Context) (domain.Metrics, error) {
	evidenceCount, err := r.graph.CountNodes(ctx, graph.KindEvidence, graph.StatusActive)
	if err != nil {
		return domain.Metrics{}, err
	}
	memoryCount, err := r.graph.CountNodes(ctx, graph.KindMemory, graph.StatusActive)
	if err != nil {
		return domain.Metrics{}, err
	}
	pageCount, err := r.graph.CountNodes(ctx, graph.KindArtifact, graph.StatusActive)
	if err != nil {
		return domain.Metrics{}, err
	}
	return domain.Metrics{
		EvidenceCount:      evidenceCount,
		MemoryCount:        memoryCount,
		PageCount:          pageCount,
		PendingJobs:        0,
		FailedJobs:         0,
		RecordsWithSources: memoryCount,
	}, nil
}

// captureByIdempotency returns an existing capture when the stable key exists.
func (r *Repository) captureByIdempotency(ctx context.Context, key string) (domain.CaptureResult, bool, error) {
	memory, err := r.graph.GetNodeByStableKey(ctx, graph.KindMemory, memoryStableKey(key))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.CaptureResult{}, false, nil
	}
	if err != nil {
		return domain.CaptureResult{}, false, err
	}
	record, err := r.GetMemory(ctx, domain.MemoryID(memory.ID))
	if err != nil {
		return domain.CaptureResult{}, false, err
	}
	return domain.CaptureResult{EvidenceID: record.EvidenceID, MemoryID: record.ID, Duplicate: true}, true, nil
}

// writeCaptureFacts stores scalar memory properties.
func (r *Repository) writeCaptureFacts(ctx context.Context, req domain.CaptureRequest, memory graph.Node, evidence graph.Node) error {
	facts := []graph.UpsertNodePropertyRequest{
		textProperty(memory.ID, propertyMemoryKind, string(req.Kind), evidence.ID, req.Actor),
		textProperty(memory.ID, propertySourceSystem, req.Source.System, evidence.ID, req.Actor),
		textProperty(memory.ID, propertySourceID, req.Source.ID, evidence.ID, req.Actor),
	}
	if req.IdempotencyKey != "" {
		facts = append(facts, textProperty(memory.ID, propertyIdempotencyKey, req.IdempotencyKey, evidence.ID, req.Actor))
	}
	if req.EventTime != nil {
		facts = append(facts, graph.UpsertNodePropertyRequest{
			NodeID:       memory.ID,
			Key:          propertyEventTime,
			Value:        graph.Value{Type: graph.ValueTime, Time: req.EventTime},
			SourceNodeID: evidence.ID,
			Actor:        req.Actor,
		})
	}
	for _, fact := range facts {
		if strings.TrimSpace(fact.Value.Text) == "" && fact.Value.Time == nil {
			continue
		}
		if _, err := r.graph.UpsertNodeProperty(ctx, fact); err != nil {
			return err
		}
	}
	return nil
}

// writeFacets stores subjects, topics, and named entities as graph edges.
func (r *Repository) writeFacets(ctx context.Context, memoryID graph.NodeID, evidenceID graph.NodeID, actor string, subjects []string, topics []string, entities []string) error {
	if err := r.replaceFacetEdges(ctx, memoryID, evidenceID, actor, graph.RelationAbout, domain.NormalizeStrings(subjects), "subject"); err != nil {
		return err
	}
	if err := r.replaceFacetEdges(ctx, memoryID, evidenceID, actor, graph.RelationTaggedWith, domain.NormalizeStrings(topics), "topic"); err != nil {
		return err
	}
	return r.replaceEntityEdges(ctx, memoryID, evidenceID, actor, domain.NormalizeStrings(entities))
}

// replaceFacetEdges replaces topic-like edges for one memory node.
func (r *Repository) replaceFacetEdges(ctx context.Context, memoryID graph.NodeID, evidenceID graph.NodeID, actor string, relation graph.RelationType, values []string, stablePrefix string) error {
	if err := r.archiveEdges(ctx, memoryID, relation, actor); err != nil {
		return err
	}
	values = domain.NormalizeStrings(values)
	for _, value := range values {
		node, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
			Kind:      graph.KindTopic,
			StableKey: stablePrefix + ":" + value,
			Title:     value,
			Firewall:  graph.FirewallUser,
			Actor:     actor,
		})
		if err != nil {
			return err
		}
		if _, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{
			FromNodeID:   memoryID,
			Type:         relation,
			ToNodeID:     node.ID,
			SourceNodeID: evidenceID,
			Actor:        actor,
		}); err != nil {
			return err
		}
	}
	return nil
}

// replaceEntityEdges replaces entity mention edges for one memory node.
func (r *Repository) replaceEntityEdges(ctx context.Context, memoryID graph.NodeID, evidenceID graph.NodeID, actor string, names []string) error {
	if err := r.archiveEdges(ctx, memoryID, graph.RelationMentions, actor); err != nil {
		return err
	}
	names = domain.NormalizeStrings(names)
	for _, name := range names {
		node, err := r.graph.UpsertNode(ctx, graph.UpsertNodeRequest{
			Kind:      graph.KindEntity,
			StableKey: "entity:" + name,
			Title:     name,
			Firewall:  graph.FirewallUser,
			Actor:     actor,
		})
		if err != nil {
			return err
		}
		if _, err := r.graph.UpsertAlias(ctx, graph.UpsertAliasRequest{NodeID: node.ID, Alias: name, Kind: "name"}); err != nil {
			return err
		}
		if _, err := r.graph.UpsertEdge(ctx, graph.UpsertEdgeRequest{
			FromNodeID:   memoryID,
			Type:         graph.RelationMentions,
			ToNodeID:     node.ID,
			SourceNodeID: evidenceID,
			Actor:        actor,
		}); err != nil {
			return err
		}
	}
	return nil
}

// archiveEdges lifecycle-archives outgoing edges of one relation type.
func (r *Repository) archiveEdges(ctx context.Context, nodeID graph.NodeID, relation graph.RelationType, actor string) error {
	edges, err := r.graph.ListOutgoingEdges(ctx, nodeID, []graph.RelationType{relation})
	if err != nil {
		return err
	}
	for _, edge := range edges {
		if _, err := r.graph.SetEdgeStatus(ctx, edge.ID, graph.StatusArchived, actor); err != nil {
			return err
		}
	}
	return nil
}

// propertyMap returns active node properties keyed by property name.
func (r *Repository) propertyMap(ctx context.Context, nodeID graph.NodeID) (map[string]graph.NodeProperty, error) {
	properties, err := r.graph.ListNodeProperties(ctx, nodeID)
	if err != nil {
		return nil, err
	}
	byKey := map[string]graph.NodeProperty{}
	for _, property := range properties {
		byKey[property.Key] = property
	}
	return byKey, nil
}

// capturedEvidence returns the source node and raw source content for a memory node.
func (r *Repository) capturedEvidence(ctx context.Context, memoryID graph.NodeID) (graph.Node, *domain.RawEvidence, error) {
	edges, err := r.graph.ListOutgoingEdges(ctx, memoryID, []graph.RelationType{graph.RelationCapturedFrom})
	if err != nil {
		return graph.Node{}, nil, err
	}
	if len(edges) == 0 {
		return graph.Node{}, nil, sql.ErrNoRows
	}
	evidence, err := r.graph.GetNode(ctx, edges[0].ToNodeID)
	if err != nil {
		return graph.Node{}, nil, err
	}
	blob, err := r.graph.GetEvidenceBlob(ctx, evidence.ID)
	if err != nil {
		return graph.Node{}, nil, err
	}
	raw := &domain.RawEvidence{
		ID:        domain.EvidenceID(evidence.ID),
		Checksum:  blob.Checksum,
		Path:      blob.Path,
		MediaType: blob.MediaType,
		Title:     evidence.Title,
		CreatedAt: blob.CreatedAt,
		SizeBytes: blob.SizeBytes,
		Source:    domain.SourceRef{System: blob.SourceSystem, ID: blob.SourceID},
	}
	return evidence, raw, nil
}

// edgeNodeTitles returns sorted target node titles for an outgoing relation.
func (r *Repository) edgeNodeTitles(ctx context.Context, nodeID graph.NodeID, relation graph.RelationType) ([]string, error) {
	edges, err := r.graph.ListOutgoingEdges(ctx, nodeID, []graph.RelationType{relation})
	if err != nil {
		return nil, err
	}
	values := []string{}
	for _, edge := range edges {
		node, err := r.graph.GetNode(ctx, edge.ToNodeID)
		if err != nil {
			return nil, err
		}
		values = append(values, node.Title)
	}
	sort.Strings(values)
	return values, nil
}

// edgeEntityNodes returns sorted entity IDs and titles for memory mentions.
func (r *Repository) edgeEntityNodes(ctx context.Context, nodeID graph.NodeID) ([]domain.EntityID, []string, error) {
	edges, err := r.graph.ListOutgoingEdges(ctx, nodeID, []graph.RelationType{graph.RelationMentions})
	if err != nil {
		return nil, nil, err
	}
	pairs := []struct {
		id   domain.EntityID
		name string
	}{}
	for _, edge := range edges {
		node, err := r.graph.GetNode(ctx, edge.ToNodeID)
		if err != nil {
			return nil, nil, err
		}
		pairs = append(pairs, struct {
			id   domain.EntityID
			name string
		}{id: domain.EntityID(node.ID), name: node.Title})
	}
	sort.Slice(pairs, func(i, j int) bool { return pairs[i].name < pairs[j].name })
	ids := make([]domain.EntityID, 0, len(pairs))
	names := make([]string, 0, len(pairs))
	for _, pair := range pairs {
		ids = append(ids, pair.id)
		names = append(names, pair.name)
	}
	return ids, names, nil
}

// memoryRelationships returns memory relationships from graph edges.
func (r *Repository) memoryRelationships(ctx context.Context, nodeID graph.NodeID) ([]domain.Relationship, error) {
	edges, err := r.graph.ListOutgoingEdges(ctx, nodeID, []graph.RelationType{graph.RelationContradicts, graph.RelationRefersTo, graph.RelationSupersedes})
	if err != nil {
		return nil, err
	}
	relationships := []domain.Relationship{}
	for _, edge := range edges {
		relationships = append(relationships, domain.Relationship{
			ID:         string(edge.ID),
			FromID:     string(edge.FromNodeID),
			Type:       fromGraphRelationship(edge.Type),
			ToID:       string(edge.ToNodeID),
			SourceID:   domain.EvidenceID(edge.SourceNodeID),
			TrustLevel: edge.TrustLevel,
			CreatedAt:  edge.CreatedAt,
		})
	}
	return relationships, nil
}

// recordMatches applies filters not handled by graph FTS.
func recordMatches(record domain.MemoryRecord, q domain.RetrievalQuery) bool {
	if record.Firewall != q.Firewall && !(q.IncludeGlobal && record.Firewall == domain.FirewallGlobal) {
		return false
	}
	if len(q.Kinds) > 0 && !slices.Contains(q.Kinds, record.Kind) {
		return false
	}
	for _, topic := range q.Topics {
		if !slices.Contains(record.Topics, topic) {
			return false
		}
	}
	for _, entityID := range q.EntityIDs {
		if !slices.Contains(record.EntityIDs, entityID) {
			return false
		}
	}
	eventTime := record.CreatedAt
	if record.EventTime != nil {
		eventTime = *record.EventTime
	}
	if q.TimeFrom != nil && eventTime.Before(*q.TimeFrom) {
		return false
	}
	if q.TimeTo != nil && eventTime.After(*q.TimeTo) {
		return false
	}
	return true
}

// buildCompiledPageContent renders a deterministic source-backed page.
func buildCompiledPageContent(kind domain.Kind, title string, records []domain.MemoryRecord) (string, []domain.EvidenceID) {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", title)
	fmt.Fprintf(&b, "Kind: `%s`\n\n", kind)
	if len(records) == 0 {
		b.WriteString("No source content matched this page yet.\n")
		return b.String(), nil
	}
	sourceSet := map[domain.EvidenceID]struct{}{}
	sort.Slice(records, func(i, j int) bool { return records[i].CreatedAt.After(records[j].CreatedAt) })
	for _, record := range records {
		sourceSet[record.EvidenceID] = struct{}{}
		fmt.Fprintf(&b, "## %s\n\n", record.Title)
		if record.Summary != "" {
			fmt.Fprintf(&b, "%s\n\n", record.Summary)
		}
		fmt.Fprintf(&b, "- Memory: `%s`\n", record.ID)
		fmt.Fprintf(&b, "- Source: `%s`\n", record.EvidenceID)
		if len(record.Topics) > 0 {
			fmt.Fprintf(&b, "- Topics: %s\n", strings.Join(record.Topics, ", "))
		}
		b.WriteString("\n")
	}
	sourceIDs := make([]domain.EvidenceID, 0, len(sourceSet))
	for sourceID := range sourceSet {
		sourceIDs = append(sourceIDs, sourceID)
	}
	sort.Slice(sourceIDs, func(i, j int) bool { return sourceIDs[i] < sourceIDs[j] })
	return b.String(), sourceIDs
}

// textProperty creates a source-backed text property request.
func textProperty(nodeID graph.NodeID, key string, value string, source graph.NodeID, actor string) graph.UpsertNodePropertyRequest {
	return graph.UpsertNodePropertyRequest{
		NodeID:       nodeID,
		Key:          key,
		Value:        graph.Value{Type: graph.ValueText, Text: strings.TrimSpace(value)},
		SourceNodeID: source,
		Actor:        actor,
	}
}

// propertyText returns a property text value or fallback.
func propertyText(property graph.NodeProperty, fallback string) string {
	if property.Value.Type == "" {
		return fallback
	}
	if property.Value.Type == graph.ValueText || property.Value.Type == graph.ValueBool {
		if property.Value.Text == "" {
			return fallback
		}
		return property.Value.Text
	}
	return fallback
}

// evidenceStableKey returns an idempotent evidence stable key when available.
func evidenceStableKey(key string) string {
	return idempotencyStableKey("evidence", key)
}

// memoryStableKey returns an idempotent memory stable key when available.
func memoryStableKey(key string) string {
	return idempotencyStableKey("memory", key)
}

// idempotencyStableKey returns a namespaced stable key when idempotency is present.
func idempotencyStableKey(prefix string, key string) string {
	key = strings.TrimSpace(key)
	if key == "" {
		return ""
	}
	return prefix + ":idempotency:" + key
}

// pageStableKey returns a deterministic compiled page stable key.
func pageStableKey(kind domain.Kind, firewall domain.Firewall, title string) string {
	return fmt.Sprintf("page:%s:%s:%s", kind, firewall, strings.ToLower(strings.TrimSpace(title)))
}

// excerpt returns a compact deterministic summary.
func excerpt(content string, limit int) string {
	content = strings.Join(strings.Fields(content), " ")
	runes := []rune(content)
	if len(runes) <= limit {
		return content
	}
	return strings.TrimSpace(string(runes[:limit])) + "..."
}
