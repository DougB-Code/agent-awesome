// This file implements the workflow orchestration service.
package runtime

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
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
	cfg                Config
	store              *store.Store
	actions            *actions.Registry
	tools              ContextToolClient
	commands           CommandClient
	mcpEndpoints       map[string]string
	llm                LLMClient
	mcp                *MCPClient
	mu                 sync.RWMutex
	defs               map[string]definition.Definition
	defHash            map[string]string
	defWarns           []definition.LoadWarning
	defReloadMu        sync.Mutex
	definitionSnapshot string
	runMu              map[string]*sync.Mutex
	rateMu             sync.Mutex
	rateHits           map[string][]time.Time
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
		mcpEndpoints: cloneStringMap(
			cfg.MCPServerEndpoints,
		),
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

// cloneStringMap copies service configuration maps before storing them.
func cloneStringMap(values map[string]string) map[string]string {
	if len(values) == 0 {
		return map[string]string{}
	}
	next := make(map[string]string, len(values))
	for key, value := range values {
		next[key] = value
	}
	return next
}

// ReloadDefinitions loads definitions from disk and stores snapshots.
func (s *Service) ReloadDefinitions(ctx context.Context) error {
	s.defReloadMu.Lock()
	defer s.defReloadMu.Unlock()
	return s.reloadDefinitions(ctx)
}

// reloadDefinitions loads definition files while the definition reload lock is held.
func (s *Service) reloadDefinitions(ctx context.Context) error {
	snapshot, err := s.definitionFileSnapshot()
	if err != nil {
		return err
	}
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
	s.definitionSnapshot = snapshot
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

// syncDefinitionsFromDisk reloads definitions when user-deployable YAML files changed.
func (s *Service) syncDefinitionsFromDisk(ctx context.Context) error {
	s.defReloadMu.Lock()
	defer s.defReloadMu.Unlock()
	snapshot, err := s.definitionFileSnapshot()
	if err != nil {
		return err
	}
	s.mu.RLock()
	unchanged := snapshot == s.definitionSnapshot
	s.mu.RUnlock()
	if unchanged {
		return s.ensureDraftsForStoredDefinitions(ctx)
	}
	return s.reloadDefinitions(ctx)
}

// definitionFileSnapshot hashes deployable workflow definition files in stable order.
func (s *Service) definitionFileSnapshot() (string, error) {
	trimmed := strings.TrimSpace(s.cfg.DefinitionsDir)
	if trimmed == "" {
		return "", fmt.Errorf("definitions directory is required")
	}
	entries, err := os.ReadDir(trimmed)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", fmt.Errorf("read workflow definitions directory %q: %w", trimmed, err)
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, ".yaml") || strings.HasSuffix(name, ".yml") {
			paths = append(paths, filepath.Join(trimmed, name))
		}
	}
	sort.Strings(paths)
	digest := sha256.New()
	for _, path := range paths {
		body, err := os.ReadFile(path)
		if err != nil {
			return "", fmt.Errorf("read workflow definition %q: %w", path, err)
		}
		digest.Write([]byte(filepath.Base(path)))
		digest.Write([]byte{0})
		digest.Write(body)
		digest.Write([]byte{0})
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

// ListDefinitions returns installed definitions from durable storage.
func (s *Service) ListDefinitions(ctx context.Context) ([]store.DefinitionRecord, error) {
	if err := s.syncDefinitionsFromDisk(ctx); err != nil {
		return nil, err
	}
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
	if err := s.syncDefinitionsFromDisk(ctx); err != nil {
		return store.RunRecord{}, err
	}
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
	if !definition.HasPipeGraph(def) && !definition.HasStateMachine(def) {
		return store.RunRecord{}, fmt.Errorf("workflow definition %q is not executable", def.ID)
	}
	if err := s.completePipePendingSignals(ctx, run, openItems, payload); err != nil {
		return store.RunRecord{}, err
	}
	go s.executeRun(context.Background(), run.ID)
	return s.store.GetRun(ctx, run.ID)
}
