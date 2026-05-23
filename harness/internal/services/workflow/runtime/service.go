// This file implements the workflow orchestration service.
package runtime

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/store"
)

const (
	statusRunning   = store.StatusRunning
	statusWaiting   = store.StatusWaiting
	statusSucceeded = store.StatusSucceeded
	statusFailed    = store.StatusFailed
	statusCanceled  = store.StatusCanceled
	statusPending   = store.StatusPending
	statusSkipped   = store.StatusSkipped
)

const (
	nodeTriggerStart   = "start"
	nodeTriggerSucceed = "succeed"
	nodeTriggerFail    = "fail"
	nodeTriggerSkip    = "skip"
)

// Service owns workflow definitions, persistence, and execution.
type Service struct {
	cfg      Config
	store    *store.Store
	actions  *actions.Registry
	tools    ContextToolClient
	commands CommandClient
	llm      LLMClient
	mcp      *MCPClient
	mu       sync.RWMutex
	defs     map[string]definition.Definition
	defHash  map[string]string
	defWarns []definition.LoadWarning
	runMu    map[string]*sync.Mutex
	rateMu   sync.Mutex
	rateHits map[string][]time.Time
}

// Open creates a workflow service and loads declarative definitions.
func Open(ctx context.Context, cfg Config) (*Service, error) {
	registry := actions.NewRegistry()
	workflowStore, err := store.Open(ctx, cfg.DatabasePath)
	if err != nil {
		return nil, err
	}
	toolClient := cfg.ToolClient
	if toolClient == nil {
		toolClient = NewToolClient(cfg.HarnessContextBaseURL, cfg.RequestTimeout)
	}
	service := &Service{
		cfg:      cfg,
		store:    workflowStore,
		actions:  registry,
		tools:    toolClient,
		commands: cfg.CommandClient,
		llm:      cfg.LLMClient,
		mcp:      NewMCPClient(cfg.RequestTimeout),
		defs:     map[string]definition.Definition{},
		defHash:  map[string]string{},
		defWarns: []definition.LoadWarning{},
		runMu:    map[string]*sync.Mutex{},
		rateHits: map[string][]time.Time{},
	}
	if err := service.ReloadDefinitions(ctx); err != nil {
		_ = workflowStore.Close()
		return nil, err
	}
	if err := service.ResumeActiveRuns(ctx); err != nil {
		_ = workflowStore.Close()
		return nil, err
	}
	return service, nil
}

// Close releases service resources.
func (s *Service) Close() error {
	if s == nil || s.store == nil {
		return nil
	}
	return s.store.Close()
}

// ReloadDefinitions loads definitions from disk and stores snapshots.
func (s *Service) ReloadDefinitions(ctx context.Context) error {
	loaded, warnings, err := s.loadDefinitions()
	if err != nil {
		return err
	}
	for _, warning := range warnings {
		log.Printf("workflow definition skipped: %s: %s", warning.Path, warning.Message)
	}
	nextDefs := map[string]definition.Definition{}
	nextHash := map[string]string{}
	draftSources := make([]loadedDefinitionDraftSource, 0, len(loaded))
	ids := make([]string, 0, len(loaded))
	for _, item := range loaded {
		body := map[string]any{}
		if err := json.Unmarshal(item.Body, &body); err != nil {
			return fmt.Errorf("decode normalized definition %s: %w", item.Definition.ID, err)
		}
		if err := s.store.UpsertDefinition(ctx, store.DefinitionRecord{
			ID:   item.Definition.ID,
			Kind: item.Definition.Kind,
			Name: item.Definition.Name,
			Hash: item.Hash,
			Body: body,
		}); err != nil {
			return err
		}
		ids = append(ids, item.Definition.ID)
		nextDefs[item.Definition.ID] = item.Definition
		nextHash[item.Definition.ID] = item.Hash
		draftSources = append(draftSources, loadedDefinitionDraftSource{
			definition: item.Definition,
			body:       body,
		})
	}
	if err := s.store.DeleteDefinitionsExcept(ctx, ids); err != nil {
		return err
	}
	if err := s.ensureDraftsForDefinitions(ctx, draftSources); err != nil {
		return err
	}
	s.mu.Lock()
	s.defs = nextDefs
	s.defHash = nextHash
	s.defWarns = append([]definition.LoadWarning(nil), warnings...)
	s.mu.Unlock()
	return nil
}

// loadDefinitions loads workflow definition files using configured strictness.
func (s *Service) loadDefinitions() ([]definition.LoadedDefinition, []definition.LoadWarning, error) {
	if s.cfg.SkipInvalidDefinitions {
		return definition.LoadDirectorySkippingInvalid(s.cfg.DefinitionsDir, s.actions)
	}
	loaded, err := definition.LoadDirectory(s.cfg.DefinitionsDir, s.actions)
	return loaded, nil, err
}

// ListDefinitions returns installed definitions from durable storage.
func (s *Service) ListDefinitions(ctx context.Context) ([]store.DefinitionRecord, error) {
	return s.store.ListDefinitions(ctx)
}

// DefinitionWarnings returns skipped definition diagnostics from the last reload.
func (s *Service) DefinitionWarnings() []definition.LoadWarning {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]definition.LoadWarning(nil), s.defWarns...)
}

// DescribeDefinition returns one loaded definition.
func (s *Service) DescribeDefinition(id string) (definition.Definition, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	def, ok := s.defs[strings.TrimSpace(id)]
	return def, ok
}

// StartWorkflow creates a run and begins execution in the background.
func (s *Service) StartWorkflow(ctx context.Context, definitionID string, input map[string]any) (store.RunRecord, error) {
	def, ok := s.DescribeDefinition(definitionID)
	if !ok {
		return store.RunRecord{}, fmt.Errorf("workflow definition %q not found", definitionID)
	}
	runID, err := newRunID()
	if err != nil {
		return store.RunRecord{}, err
	}
	run := store.RunRecord{
		ID:           runID,
		DefinitionID: def.ID,
		Kind:         def.Kind,
		Status:       statusRunning,
		State:        statusRunning,
		Input:        input,
		Output:       map[string]any{},
	}
	if err := s.store.CreateRun(ctx, run); err != nil {
		return store.RunRecord{}, err
	}
	_ = s.appendEvent(ctx, run.ID, "run_started", "workflow run started", map[string]any{"definition_id": def.ID})
	go s.executeRun(context.Background(), run.ID)
	return s.store.GetRun(ctx, run.ID)
}

// Status returns one workflow run by id.
func (s *Service) Status(ctx context.Context, runID string) (store.RunRecord, error) {
	return s.store.GetRun(ctx, strings.TrimSpace(runID))
}

// History returns durable events for one workflow run.
func (s *Service) History(ctx context.Context, runID string) ([]store.EventRecord, error) {
	return s.store.ListEvents(ctx, strings.TrimSpace(runID))
}

// Inbox returns open user-visible workflow items.
func (s *Service) Inbox(ctx context.Context) ([]store.PendingItem, error) {
	return s.store.ListOpenPendingItems(ctx)
}

// Cancel marks one running workflow as canceled.
func (s *Service) Cancel(ctx context.Context, runID string) (store.RunRecord, error) {
	run, err := s.store.GetRun(ctx, strings.TrimSpace(runID))
	if err != nil {
		return store.RunRecord{}, err
	}
	if err := s.store.UpdateRunState(ctx, run.ID, statusCanceled, run.State, run.Output); err != nil {
		return store.RunRecord{}, err
	}
	_ = s.appendEvent(ctx, run.ID, "run_canceled", "workflow run canceled", nil)
	return s.store.GetRun(ctx, run.ID)
}

// ResumeActiveRuns resumes runs that were interrupted while actively running.
func (s *Service) ResumeActiveRuns(ctx context.Context) error {
	runs, err := s.store.ListRunsByStatus(ctx, statusRunning)
	if err != nil {
		return err
	}
	for _, run := range runs {
		_ = s.appendEvent(ctx, run.ID, "run_resumed", "workflow run resumed after startup", nil)
		go s.executeRun(context.Background(), run.ID)
	}
	return nil
}

// Signal applies a user or system signal to a waiting or running workflow.
func (s *Service) Signal(ctx context.Context, runID string, signal string, payload map[string]any) (store.RunRecord, error) {
	run, err := s.store.GetRun(ctx, strings.TrimSpace(runID))
	if err != nil {
		return store.RunRecord{}, err
	}
	def, ok := s.DescribeDefinition(run.DefinitionID)
	if !ok {
		return store.RunRecord{}, fmt.Errorf("workflow definition %q not loaded", run.DefinitionID)
	}
	openItems, err := s.store.ListOpenPendingItems(ctx)
	if err != nil {
		return store.RunRecord{}, err
	}
	if err := s.store.CompletePendingItems(ctx, run.ID, payload); err != nil {
		return store.RunRecord{}, err
	}
	if err := s.appendEvent(ctx, run.ID, "signal_received", "workflow signal received", map[string]any{"signal": signal, "payload": payload}); err != nil {
		return store.RunRecord{}, err
	}
	if !definition.HasPipeGraph(def) {
		return store.RunRecord{}, fmt.Errorf("workflow definition %q is not an executable graph", def.ID)
	}
	if err := s.completePipePendingSignals(ctx, run, openItems, payload); err != nil {
		return store.RunRecord{}, err
	}
	go s.executeRun(context.Background(), run.ID)
	return s.store.GetRun(ctx, run.ID)
}
