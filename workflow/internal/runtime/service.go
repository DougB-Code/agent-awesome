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

	flow "github.com/Azure/go-workflow"
	"github.com/cenkalti/backoff/v4"
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
)

// Service owns workflow definitions, persistence, and execution.
type Service struct {
	cfg     Config
	store   *store.Store
	actions *actions.Registry
	agent   *AgentClient
	tools   *ToolClient
	mcp     *MCPClient
	mu      sync.RWMutex
	defs    map[string]definition.Definition
	defHash map[string]string
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
		agent:   NewAgentClient(cfg.HarnessBaseURL, cfg.AppName, cfg.UserID, cfg.RequestTimeout),
		tools:   NewToolClient(cfg.HarnessContextBaseURL, cfg.RequestTimeout),
		mcp:     NewMCPClient(cfg.RequestTimeout),
		defs:    map[string]definition.Definition{},
		defHash: map[string]string{},
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
	if def.Kind == definition.KindStateMachine {
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
	if def.Kind != definition.KindStateMachine {
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

// RunAgent executes a scoped harness agent step.
func (s *Service) RunAgent(ctx context.Context, req actions.AgentRequest) (map[string]any, error) {
	return s.agent.Run(ctx, req)
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
	run, err := s.store.GetRun(ctx, runID)
	if err != nil || run.Status == statusCanceled || run.Status == statusSucceeded {
		return
	}
	def, ok := s.DescribeDefinition(run.DefinitionID)
	if !ok {
		s.failRun(ctx, run, fmt.Errorf("workflow definition %q not loaded", run.DefinitionID))
		return
	}
	switch def.Kind {
	case definition.KindStateMachine:
		err = s.executeStateEntry(ctx, def, run)
	case definition.KindDAG:
		err = s.executeDAG(ctx, def, run)
	default:
		err = fmt.Errorf("unsupported workflow kind %q", def.Kind)
	}
	if err == nil {
		run, _ = s.store.GetRun(ctx, run.ID)
		if def.Kind == definition.KindStateMachine {
			s.completeStateMachineRun(ctx, def, run)
			return
		}
		if run.Status == statusRunning {
			_ = s.store.UpdateRunState(ctx, run.ID, statusSucceeded, run.State, map[string]any{"status": statusSucceeded})
			_ = s.store.AppendEvent(ctx, run.ID, "run_succeeded", "workflow run succeeded", nil)
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

// executeDAG builds and runs a go-workflow DAG from declarative nodes.
func (s *Service) executeDAG(ctx context.Context, def definition.Definition, run store.RunRecord) error {
	steps := map[string]*actionStep{}
	for _, node := range def.Nodes {
		steps[node.ID] = &actionStep{
			service: s,
			run:     run,
			node:    node,
		}
	}
	var workflow flow.Workflow
	for _, node := range def.Nodes {
		builder := flow.Step(steps[node.ID])
		for _, dep := range node.DependsOn {
			builder = builder.DependsOn(steps[dep])
		}
		if node.Timeout != "" {
			timeout, err := time.ParseDuration(node.Timeout)
			if err != nil {
				return fmt.Errorf("node %q timeout: %w", node.ID, err)
			}
			builder = builder.Timeout(timeout)
		}
		if node.Retry > 0 {
			attempts := node.Retry + 1
			retryDelay, err := nodeRetryDelay(node)
			if err != nil {
				return err
			}
			builder = builder.Retry(func(option *flow.RetryOption) {
				option.Attempts = uint64(attempts)
				if retryDelay > 0 {
					option.Backoff = backoff.NewConstantBackOff(retryDelay)
				}
			})
		}
		workflow.Add(builder)
	}
	err := workflow.Do(ctx)
	if err != nil && containsPending(err) {
		return actions.ErrPending
	}
	return err
}

// nodeRetryDelay parses fixed retry delay settings for one DAG node.
func nodeRetryDelay(node definition.NodeDefinition) (time.Duration, error) {
	if strings.TrimSpace(node.RetryDelay) == "" {
		return 0, nil
	}
	delay, err := time.ParseDuration(node.RetryDelay)
	if err != nil {
		return 0, fmt.Errorf("node %q retry_delay: %w", node.ID, err)
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

// nodeInput builds the JSON input visible to a DAG node from parent outputs.
func (s *Service) nodeInput(ctx context.Context, run store.RunRecord, node definition.NodeDefinition) (map[string]any, error) {
	if len(node.DependsOn) == 0 {
		return run.Input, nil
	}
	input := map[string]any{"workflow_input": run.Input}
	for _, dependencyID := range node.DependsOn {
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

// actionStep adapts one declarative node to go-workflow.
type actionStep struct {
	service *Service
	run     store.RunRecord
	node    definition.NodeDefinition
}

// Do executes the DAG node action.
func (s *actionStep) Do(ctx context.Context) error {
	input, err := s.service.nodeInput(ctx, s.run, s.node)
	if err != nil {
		return err
	}
	_, err = s.service.executeActionWithInput(ctx, s.run, s.node.ID, s.node.Uses, s.node.With, input)
	return err
}
