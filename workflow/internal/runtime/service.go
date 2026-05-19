// This file implements the workflow orchestration service.
package runtime

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/qmuntal/stateless"

	"workflow/internal/actions"
	"workflow/internal/definition"
	"workflow/internal/store"
)

const (
	statusRunning   = "running"
	statusWaiting   = "waiting"
	statusSucceeded = "succeeded"
	statusFailed    = "failed"
	statusCanceled  = "canceled"
	statusPending   = "pending"
)

const (
	taskTriggerStart   = "start"
	taskTriggerSucceed = "succeed"
	taskTriggerFail    = "fail"
)

// Service owns workflow definitions, persistence, and execution.
type Service struct {
	cfg     Config
	store   *store.Store
	actions *actions.Registry
	tools   *ToolClient
	mcp     *MCPClient
	mu      sync.RWMutex
	defs    map[string]definition.Definition
	defHash map[string]string
	runMu   map[string]*sync.Mutex
}

// Open creates a workflow service and loads declarative definitions.
func Open(ctx context.Context, cfg Config) (*Service, error) {
	registry := actions.NewRegistry()
	workflowStore, err := store.Open(ctx, cfg.DatabasePath)
	if err != nil {
		return nil, err
	}
	service := &Service{
		cfg:     cfg,
		store:   workflowStore,
		actions: registry,
		tools:   NewToolClient(cfg.HarnessContextBaseURL, cfg.RequestTimeout),
		mcp:     NewMCPClient(cfg.RequestTimeout),
		defs:    map[string]definition.Definition{},
		defHash: map[string]string{},
		runMu:   map[string]*sync.Mutex{},
	}
	if err := service.ReloadDefinitions(ctx); err != nil {
		_ = workflowStore.Close()
		return nil, err
	}
	if err := service.SeedAuthoringCatalog(ctx); err != nil {
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
	loaded, err := definition.LoadDirectory(s.cfg.DefinitionsDir, s.actions)
	if err != nil {
		return err
	}
	nextDefs := map[string]definition.Definition{}
	nextHash := map[string]string{}
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
	}
	if err := s.store.DeleteDefinitionsExcept(ctx, ids); err != nil {
		return err
	}
	s.mu.Lock()
	s.defs = nextDefs
	s.defHash = nextHash
	s.mu.Unlock()
	return nil
}

// ListDefinitions returns installed definitions from durable storage.
func (s *Service) ListDefinitions(ctx context.Context) ([]store.DefinitionRecord, error) {
	return s.store.ListDefinitions(ctx)
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
	state := "running"
	if !definition.HasTaskStates(def) {
		state = def.Initial
	}
	run := store.RunRecord{
		ID:           runID,
		DefinitionID: def.ID,
		Kind:         def.Kind,
		Status:       statusRunning,
		State:        state,
		Input:        input,
		Output:       map[string]any{},
	}
	if err := s.store.CreateRun(ctx, run); err != nil {
		return store.RunRecord{}, err
	}
	_ = s.store.AppendEvent(ctx, run.ID, "run_started", "workflow run started", map[string]any{"definition_id": def.ID})
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
	_ = s.store.AppendEvent(ctx, run.ID, "run_canceled", "workflow run canceled", nil)
	return s.store.GetRun(ctx, run.ID)
}

// ResumeActiveRuns resumes runs that were interrupted while actively running.
func (s *Service) ResumeActiveRuns(ctx context.Context) error {
	runs, err := s.store.ListRunsByStatus(ctx, statusRunning)
	if err != nil {
		return err
	}
	for _, run := range runs {
		_ = s.store.AppendEvent(ctx, run.ID, "run_resumed", "workflow run resumed after startup", nil)
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
	if err := s.store.CompletePendingItems(ctx, run.ID, payload); err != nil {
		return store.RunRecord{}, err
	}
	if err := s.store.AppendEvent(ctx, run.ID, "signal_received", "workflow signal received", map[string]any{"signal": signal, "payload": payload}); err != nil {
		return store.RunRecord{}, err
	}
	if def.Kind != definition.KindStateMachine || definition.HasTaskStates(def) {
		return run, nil
	}
	if err := s.fireStateTrigger(ctx, def, run, signal); err != nil {
		_ = s.store.AppendEvent(ctx, run.ID, "signal_failed", err.Error(), map[string]any{"signal": signal})
		return store.RunRecord{}, err
	}
	go s.executeRun(context.Background(), run.ID)
	return s.store.GetRun(ctx, run.ID)
}

// RequestHuman records a pending user-visible item without contacting channels.
func (s *Service) RequestHuman(ctx context.Context, req actions.HumanRequest) (string, error) {
	if containsSensitiveKey(req.Payload) {
		return "", fmt.Errorf("human.request payload must not contain credential-like keys")
	}
	id, err := newPendingID()
	if err != nil {
		return "", err
	}
	if err := s.store.CreatePendingItem(ctx, store.PendingItem{
		ID:      id,
		RunID:   req.RunID,
		StepID:  req.StepID,
		Status:  "open",
		Prompt:  req.Prompt,
		Payload: req.Payload,
	}); err != nil {
		return "", err
	}
	_ = s.store.AppendEvent(ctx, req.RunID, "human_requested", "workflow is waiting for user input", map[string]any{"pending_id": id, "step_id": req.StepID})
	return id, nil
}

// CallTool invokes one harness context tool.
func (s *Service) CallTool(ctx context.Context, req actions.ToolRequest) (map[string]any, error) {
	return s.tools.Call(ctx, req)
}

// CallMCP invokes one MCP tool endpoint.
func (s *Service) CallMCP(ctx context.Context, req actions.MCPRequest) (map[string]any, error) {
	return s.mcp.Call(ctx, req)
}

// SignalWorkflow applies an internal signal from an action.
func (s *Service) SignalWorkflow(ctx context.Context, signal actions.WorkflowSignal) error {
	_, err := s.Signal(ctx, signal.RunID, signal.Signal, signal.Payload)
	return err
}

// StartNestedWorkflow starts a child workflow from a workflow action.
func (s *Service) StartNestedWorkflow(ctx context.Context, req actions.NestedWorkflowRequest) (map[string]any, error) {
	run, err := s.StartWorkflow(ctx, req.DefinitionID, req.Input)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"run_id":        run.ID,
		"definition_id": run.DefinitionID,
		"status":        run.Status,
	}, nil
}

// executeRun resumes a run according to its definition kind.
func (s *Service) executeRun(ctx context.Context, runID string) {
	unlock := s.lockRun(runID)
	defer unlock()
	run, err := s.store.GetRun(ctx, runID)
	if err != nil || run.Status == statusCanceled || run.Status == statusSucceeded {
		return
	}
	def, ok := s.DescribeDefinition(run.DefinitionID)
	if !ok {
		s.failRun(ctx, run, fmt.Errorf("workflow definition %q not loaded", run.DefinitionID))
		return
	}
	if def.Kind != definition.KindStateMachine {
		err = fmt.Errorf("unsupported workflow kind %q", def.Kind)
	} else if definition.HasTaskStates(def) {
		err = s.executeTaskStates(ctx, def, run)
	} else {
		err = s.executeStateEntry(ctx, def, run)
	}
	if err == nil {
		run, _ = s.store.GetRun(ctx, run.ID)
		if definition.HasTaskStates(def) {
			if run.Status == statusRunning {
				_ = s.store.UpdateRunState(ctx, run.ID, statusSucceeded, run.State, map[string]any{"status": statusSucceeded})
				_ = s.store.AppendEvent(ctx, run.ID, "run_succeeded", "workflow run succeeded", nil)
			}
			return
		}
		if def.Kind == definition.KindStateMachine {
			s.completeStateMachineRun(ctx, def, run)
			return
		}
		return
	}
	if errors.Is(err, actions.ErrPending) {
		run, _ = s.store.GetRun(ctx, run.ID)
		_ = s.store.UpdateRunState(ctx, run.ID, statusWaiting, run.State, run.Output)
		return
	}
	s.failRun(ctx, run, err)
}

// completeStateMachineRun waits in non-terminal states and succeeds terminal states.
func (s *Service) completeStateMachineRun(ctx context.Context, def definition.Definition, run store.RunRecord) {
	if run.Status != statusRunning {
		return
	}
	state, ok := stateByID(def, run.State)
	if !ok {
		s.failRun(ctx, run, fmt.Errorf("state %q is not defined", run.State))
		return
	}
	if len(state.Transitions) > 0 {
		_ = s.store.UpdateRunState(ctx, run.ID, statusWaiting, run.State, run.Output)
		return
	}
	_ = s.store.UpdateRunState(ctx, run.ID, statusSucceeded, run.State, map[string]any{"status": statusSucceeded})
	_ = s.store.AppendEvent(ctx, run.ID, "run_succeeded", "workflow run succeeded", nil)
}

// executeStateEntry executes the entry actions for the current state.
func (s *Service) executeStateEntry(ctx context.Context, def definition.Definition, run store.RunRecord) error {
	state, ok := stateByID(def, run.State)
	if !ok {
		return fmt.Errorf("state %q is not defined", run.State)
	}
	for index, action := range state.OnEntry {
		stepID := action.ID
		if stepID == "" {
			stepID = fmt.Sprintf("%s_entry_%d", state.ID, index+1)
		}
		if _, err := s.executeAction(ctx, run, stepID, action.Uses, action.With); err != nil {
			return err
		}
	}
	return nil
}

// executeTaskStates schedules ready task states until the graph completes.
func (s *Service) executeTaskStates(ctx context.Context, def definition.Definition, run store.RunRecord) error {
	taskStates := taskStatesByID(def)
	execCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	inFlight := map[string]struct{}{}
	results := make(chan taskStateResult, len(taskStates))
	for {
		records, err := s.store.ListTaskStates(ctx, run.ID)
		if err != nil {
			return err
		}
		statuses := taskStatusByID(records)
		if taskStatesSucceeded(taskStates, statuses) {
			return nil
		}
		if failedID, failed := firstFailedTaskState(taskStates, statuses); failed {
			return fmt.Errorf("task state %q failed: %s", failedID, statuses[failedID].Error)
		}
		for _, state := range def.States {
			if _, ok := taskStates[state.ID]; !ok {
				continue
			}
			if _, ok := inFlight[state.ID]; ok {
				continue
			}
			if record, ok := statuses[state.ID]; ok && record.Status == statusSucceeded {
				continue
			}
			if !taskDependenciesSucceeded(state, statuses) {
				continue
			}
			inFlight[state.ID] = struct{}{}
			go func(task definition.StateDefinition) {
				results <- taskStateResult{stateID: task.ID, err: s.executeTaskState(execCtx, run, task)}
			}(state)
		}
		if len(inFlight) == 0 {
			return fmt.Errorf("task states are blocked by incomplete dependencies")
		}
		result := <-results
		delete(inFlight, result.stateID)
		if result.err != nil {
			cancel()
			for len(inFlight) > 0 {
				next := <-results
				delete(inFlight, next.stateID)
			}
			if errors.Is(result.err, actions.ErrPending) || containsPending(result.err) {
				return actions.ErrPending
			}
			return result.err
		}
	}
}

// executeTaskState runs one durable task state with retry and timeout policy.
func (s *Service) executeTaskState(ctx context.Context, run store.RunRecord, state definition.StateDefinition) error {
	if record, ok, err := s.store.GetTaskState(ctx, run.ID, state.ID); err != nil {
		return err
	} else if ok && record.Status == statusSucceeded {
		return nil
	}
	attempts := taskStateAttempts(ctx, s.store, run.ID, state.ID)
	maxAttempts := state.Retry + 1
	retryDelay, err := stateRetryDelay(state)
	if err != nil {
		return err
	}
	var lastErr error
	for attempts < maxAttempts {
		attempts++
		if err := s.fireTaskStateTrigger(ctx, run.ID, state.ID, taskTriggerStart, attempts, nil, ""); err != nil {
			return err
		}
		input, err := s.taskStateInput(ctx, run, state)
		if err != nil {
			lastErr = err
		} else {
			actionCtx := ctx
			var cancel context.CancelFunc
			if strings.TrimSpace(state.Timeout) != "" {
				timeout, err := time.ParseDuration(state.Timeout)
				if err != nil {
					return fmt.Errorf("task state %q timeout: %w", state.ID, err)
				}
				actionCtx, cancel = context.WithTimeout(ctx, timeout)
			}
			output, err := s.executeActionWithInput(actionCtx, run, state.ID, state.Uses, state.With, input)
			if cancel != nil {
				cancel()
			}
			if err == nil {
				if output == nil {
					output = map[string]any{}
					if err := s.store.SaveStepOutput(ctx, run.ID, state.ID, output); err != nil {
						return err
					}
				}
				return s.fireTaskStateTrigger(ctx, run.ID, state.ID, taskTriggerSucceed, attempts, output, "")
			}
			lastErr = err
		}
		if attempts < maxAttempts && retryDelay > 0 {
			if err := sleepContext(ctx, retryDelay); err != nil {
				return err
			}
		}
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("task state %q failed", state.ID)
	}
	if err := s.fireTaskStateTrigger(ctx, run.ID, state.ID, taskTriggerFail, attempts, nil, lastErr.Error()); err != nil {
		return err
	}
	return lastErr
}

// stateRetryDelay parses fixed retry delay settings for one task state.
func stateRetryDelay(state definition.StateDefinition) (time.Duration, error) {
	if strings.TrimSpace(state.RetryDelay) == "" {
		return 0, nil
	}
	delay, err := time.ParseDuration(state.RetryDelay)
	if err != nil {
		return 0, fmt.Errorf("task state %q retry_delay: %w", state.ID, err)
	}
	return delay, nil
}

// executeAction runs one registered action and persists its output.
func (s *Service) executeAction(ctx context.Context, run store.RunRecord, stepID string, action string, args map[string]any) (map[string]any, error) {
	return s.executeActionWithInput(ctx, run, stepID, action, args, run.Input)
}

// executeActionWithInput runs one action with explicit step input and stores its output.
func (s *Service) executeActionWithInput(ctx context.Context, run store.RunRecord, stepID string, action string, args map[string]any, input map[string]any) (map[string]any, error) {
	_ = s.store.AppendEvent(ctx, run.ID, "step_started", "workflow step started", map[string]any{"step_id": stepID, "action": action})
	output, err := s.actions.Execute(ctx, action, actions.Context{
		RunID:  run.ID,
		StepID: stepID,
		Input:  input,
		Host:   s,
	}, args)
	if output != nil {
		_ = s.store.SaveStepOutput(ctx, run.ID, stepID, output)
	}
	if err != nil {
		if errors.Is(err, actions.ErrPending) {
			_ = s.store.AppendEvent(ctx, run.ID, "step_pending", "workflow step is pending", map[string]any{"step_id": stepID})
			return output, err
		}
		_ = s.store.AppendEvent(ctx, run.ID, "step_failed", err.Error(), map[string]any{"step_id": stepID})
		return output, err
	}
	_ = s.store.AppendEvent(ctx, run.ID, "step_succeeded", "workflow step succeeded", map[string]any{"step_id": stepID})
	return output, nil
}

// taskStateInput builds the JSON input visible to a task state from parent outputs.
func (s *Service) taskStateInput(ctx context.Context, run store.RunRecord, state definition.StateDefinition) (map[string]any, error) {
	if len(state.DependsOn) == 0 {
		return run.Input, nil
	}
	input := map[string]any{"workflow_input": run.Input}
	for _, dependencyID := range state.DependsOn {
		output, ok, err := s.store.StepOutput(ctx, run.ID, dependencyID)
		if err != nil {
			return nil, err
		}
		if !ok {
			output = map[string]any{}
		}
		input[dependencyID] = output
	}
	return input, nil
}

// fireStateTrigger uses stateless to persist a state transition.
func (s *Service) fireStateTrigger(ctx context.Context, def definition.Definition, run store.RunRecord, trigger string) error {
	current := run.State
	machine := stateless.NewStateMachineWithExternalStorage(
		func(context.Context) (stateless.State, error) {
			return current, nil
		},
		func(ctx context.Context, state stateless.State) error {
			next, _ := state.(string)
			current = next
			return s.store.UpdateRunState(ctx, run.ID, statusRunning, next, run.Output)
		},
		stateless.FiringQueued,
	)
	for _, state := range def.States {
		cfg := machine.Configure(state.ID)
		for _, transition := range state.Transitions {
			cfg.Permit(transition.Trigger, transition.To)
		}
	}
	if err := machine.FireCtx(ctx, strings.TrimSpace(trigger)); err != nil {
		return err
	}
	return s.store.AppendEvent(ctx, run.ID, "state_transitioned", "workflow state transitioned", map[string]any{"from": run.State, "to": current, "trigger": trigger})
}

// fireTaskStateTrigger uses stateless to persist one task-state lifecycle transition.
func (s *Service) fireTaskStateTrigger(ctx context.Context, runID string, stateID string, trigger string, attempts int, output map[string]any, message string) error {
	current := statusPending
	if record, ok, err := s.store.GetTaskState(ctx, runID, stateID); err != nil {
		return err
	} else if ok {
		current = record.Status
	}
	machine := stateless.NewStateMachineWithExternalStorage(
		func(context.Context) (stateless.State, error) {
			return current, nil
		},
		func(ctx context.Context, state stateless.State) error {
			next, _ := state.(string)
			current = next
			switch next {
			case statusRunning:
				return s.store.MarkTaskStateRunning(ctx, runID, stateID, attempts)
			case statusSucceeded:
				return s.store.MarkTaskStateSucceeded(ctx, runID, stateID, attempts, output)
			case statusFailed:
				return s.store.MarkTaskStateFailed(ctx, runID, stateID, attempts, message)
			default:
				return fmt.Errorf("unsupported task state status %q", next)
			}
		},
		stateless.FiringQueued,
	)
	machine.Configure(statusPending).Permit(taskTriggerStart, statusRunning)
	machine.Configure(statusRunning).
		PermitReentry(taskTriggerStart).
		Permit(taskTriggerSucceed, statusSucceeded).
		Permit(taskTriggerFail, statusFailed)
	if err := machine.FireCtx(ctx, trigger); err != nil {
		return fmt.Errorf("task state %q transition %q from %q: %w", stateID, trigger, current, err)
	}
	return nil
}

// failRun marks a run failed and records the error.
func (s *Service) failRun(ctx context.Context, run store.RunRecord, err error) {
	_ = s.store.UpdateRunState(ctx, run.ID, statusFailed, run.State, map[string]any{"error": err.Error()})
	_ = s.store.AppendEvent(ctx, run.ID, "run_failed", err.Error(), nil)
}

// stateByID returns one state definition by id.
func stateByID(def definition.Definition, id string) (definition.StateDefinition, bool) {
	for _, state := range def.States {
		if state.ID == id {
			return state, true
		}
	}
	return definition.StateDefinition{}, false
}

// lockRun serializes in-process execution for one run id.
func (s *Service) lockRun(runID string) func() {
	s.mu.Lock()
	mutex := s.runMu[runID]
	if mutex == nil {
		mutex = &sync.Mutex{}
		s.runMu[runID] = mutex
	}
	s.mu.Unlock()
	mutex.Lock()
	return mutex.Unlock
}

// taskStateResult reports one concurrent task-state completion.
type taskStateResult struct {
	stateID string
	err     error
}

// taskStatesByID returns every executable task state by id.
func taskStatesByID(def definition.Definition) map[string]definition.StateDefinition {
	states := map[string]definition.StateDefinition{}
	for _, state := range def.States {
		if definition.IsTaskState(state) {
			states[state.ID] = state
		}
	}
	return states
}

// taskStatusByID indexes durable task-state records by state id.
func taskStatusByID(records []store.TaskStateRecord) map[string]store.TaskStateRecord {
	statuses := map[string]store.TaskStateRecord{}
	for _, record := range records {
		statuses[record.StateID] = record
	}
	return statuses
}

// taskStatesSucceeded reports whether every task state has durable success.
func taskStatesSucceeded(states map[string]definition.StateDefinition, statuses map[string]store.TaskStateRecord) bool {
	for id := range states {
		if statuses[id].Status != statusSucceeded {
			return false
		}
	}
	return true
}

// firstFailedTaskState returns the first durable failed task state.
func firstFailedTaskState(states map[string]definition.StateDefinition, statuses map[string]store.TaskStateRecord) (string, bool) {
	for id := range states {
		if statuses[id].Status == statusFailed {
			return id, true
		}
	}
	return "", false
}

// taskDependenciesSucceeded reports whether all parent task states completed.
func taskDependenciesSucceeded(state definition.StateDefinition, statuses map[string]store.TaskStateRecord) bool {
	for _, dependencyID := range state.DependsOn {
		if statuses[dependencyID].Status != statusSucceeded {
			return false
		}
	}
	return true
}

// taskStateAttempts returns persisted attempts for one task state.
func taskStateAttempts(ctx context.Context, workflowStore *store.Store, runID string, stateID string) int {
	record, ok, err := workflowStore.GetTaskState(ctx, runID, stateID)
	if err != nil || !ok {
		return 0
	}
	if record.Status == statusRunning && record.Attempts > 0 {
		return record.Attempts - 1
	}
	return record.Attempts
}

// sleepContext waits for retry delay or context cancellation.
func sleepContext(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// containsPending reports whether a workflow error includes a pending action.
func containsPending(err error) bool {
	return err != nil && strings.Contains(err.Error(), actions.ErrPending.Error())
}

// newRunID creates an opaque durable run id.
func newRunID() (string, error) {
	return randomID("run")
}

// newPendingID creates an opaque pending item id.
func newPendingID() (string, error) {
	return randomID("pending")
}

// randomID creates a prefixed random hex id.
func randomID(prefix string) (string, error) {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", fmt.Errorf("create %s id: %w", prefix, err)
	}
	return prefix + "_" + hex.EncodeToString(bytes[:]), nil
}

// containsSensitiveKey reports whether a pending payload appears to contain secrets.
func containsSensitiveKey(value any) bool {
	switch typed := value.(type) {
	case map[string]any:
		for key, item := range typed {
			normalized := strings.ToLower(strings.TrimSpace(key))
			if normalized == "password" ||
				strings.HasSuffix(normalized, "_password") ||
				normalized == "secret" ||
				strings.HasSuffix(normalized, "_secret") ||
				normalized == "token" ||
				strings.HasSuffix(normalized, "_token") ||
				normalized == "credential" ||
				strings.HasSuffix(normalized, "_credential") {
				return true
			}
			if containsSensitiveKey(item) {
				return true
			}
		}
	case []any:
		for _, item := range typed {
			if containsSensitiveKey(item) {
				return true
			}
		}
	}
	return false
}
