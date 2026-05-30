// This file executes hierarchical state-machine workflow definitions.
package runtime

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/envelope"
	"agentawesome/internal/services/workflow/policy"
	"agentawesome/internal/services/workflow/store"
)

const maxStateMachineDepth = 128

// executeStateMachine runs hierarchical states through the generic action registry.
func (s *Service) executeStateMachine(ctx context.Context, def definition.Definition, run store.RunRecord) error {
	states := stateMachineStates(def)
	initial := strings.TrimSpace(def.Initial)
	if initial == "" && len(def.States) > 0 {
		initial = strings.TrimSpace(def.States[0].ID)
	}
	trigger, err := s.executeState(ctx, def, run, states, initial, 0)
	if err != nil {
		return err
	}
	if trigger != statusSucceeded {
		return fmt.Errorf("state machine ended with trigger %q", trigger)
	}
	output, err := s.stateActionContext(ctx, run)
	if err != nil {
		return err
	}
	current, err := s.store.GetRun(ctx, run.ID)
	if err != nil {
		return err
	}
	_ = s.store.UpdateRunState(ctx, run.ID, statusSucceeded, current.State, output)
	_ = s.appendEvent(ctx, run.ID, "run_succeeded", "workflow run succeeded", nil)
	return nil
}

// executeState enters one state, executes its children, and applies local transitions.
func (s *Service) executeState(ctx context.Context, def definition.Definition, run store.RunRecord, states map[string]definition.StateDefinition, stateID string, depth int) (string, error) {
	if depth > maxStateMachineDepth {
		return "", fmt.Errorf("state machine exceeded maximum transition depth")
	}
	state, ok := states[strings.TrimSpace(stateID)]
	if !ok {
		return "", fmt.Errorf("state %q is not defined", stateID)
	}
	_ = s.store.UpdateRunState(ctx, run.ID, statusRunning, state.ID, run.Output)
	entryTrigger, err := s.executeStateEntry(ctx, def, run, state)
	if err != nil {
		if errors.Is(err, actions.ErrPending) {
			return "", err
		}
		return s.executeStateTransition(ctx, def, run, states, state, statusFailed, depth)
	}
	trigger := statusSucceeded
	if strings.TrimSpace(entryTrigger) != "" {
		trigger = strings.TrimSpace(entryTrigger)
	}
	if len(state.States) > 0 {
		childID := strings.TrimSpace(state.Initial)
		if childID == "" {
			childID = strings.TrimSpace(state.States[0].ID)
		}
		childTrigger, err := s.executeState(ctx, def, run, states, childID, depth+1)
		if err != nil {
			return "", err
		}
		trigger = childTrigger
	}
	return s.executeStateTransition(ctx, def, run, states, state, trigger, depth)
}

// executeStateTransition follows a matching transition or bubbles its trigger to the parent.
func (s *Service) executeStateTransition(ctx context.Context, def definition.Definition, run store.RunRecord, states map[string]definition.StateDefinition, state definition.StateDefinition, trigger string, depth int) (string, error) {
	for _, transition := range state.Transitions {
		if strings.TrimSpace(transition.Trigger) != trigger {
			continue
		}
		target := strings.TrimSpace(transition.To)
		if target == "" {
			return trigger, nil
		}
		return s.executeState(ctx, def, run, states, target, depth+1)
	}
	return trigger, nil
}

// executeStateEntry executes all entry actions and returns the last suggested trigger.
func (s *Service) executeStateEntry(ctx context.Context, def definition.Definition, run store.RunRecord, state definition.StateDefinition) (string, error) {
	trigger := ""
	for _, actionNode := range state.OnEntry {
		record, ok, err := s.store.GetNodeState(ctx, run.ID, actionNode.ID)
		if err != nil {
			return "", err
		}
		if ok && record.Status == statusSucceeded {
			if savedTrigger := suggestedTriggerFromStepOutput(record.Output); savedTrigger != "" {
				trigger = savedTrigger
			}
			continue
		}
		if ok && record.Status == statusFailed {
			return "", fmt.Errorf("state action %q failed: %s", actionNode.ID, record.Error)
		}
		suggestedTrigger, err := s.executeStateAction(ctx, def, run, actionNode)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(suggestedTrigger) != "" {
			trigger = strings.TrimSpace(suggestedTrigger)
		}
	}
	return trigger, nil
}

// executeStateAction invokes one state entry action with runtime policy and retries.
func (s *Service) executeStateAction(ctx context.Context, def definition.Definition, run store.RunRecord, node definition.NodeDefinition) (string, error) {
	attempts := nodeStateAttempts(ctx, s.store, run.ID, node.ID)
	maxAttempts := node.Retry + 1
	retryDelay, err := nodeRetryDelay(node)
	if err != nil {
		return "", err
	}
	var lastErr error
	for attempts < maxAttempts {
		attempts++
		if err := s.fireNodeStateTrigger(ctx, run.ID, node.ID, nodeTriggerStart, attempts, nil, ""); err != nil {
			return "", err
		}
		output, err := s.executeStateActionAttempt(ctx, def, run, node, attempts)
		if err == nil {
			outputMap := output.ToMap()
			if err := s.store.SaveStepOutput(ctx, run.ID, node.ID, outputMap); err != nil {
				return "", err
			}
			if err := s.recordObservedContract(ctx, def, node, output); err != nil {
				_ = s.appendEvent(ctx, run.ID, "contract_observation_failed", err.Error(), map[string]any{"node_id": node.ID})
			}
			if err := s.fireNodeStateTrigger(ctx, run.ID, node.ID, nodeTriggerSucceed, attempts, outputMap, ""); err != nil {
				return "", err
			}
			_ = s.appendEvent(ctx, run.ID, "step_succeeded", "workflow state action succeeded", map[string]any{"step_id": node.ID})
			return strings.TrimSpace(output.Control.SuggestedTrigger), nil
		}
		if errors.Is(err, actions.ErrPending) {
			output.Control.Status = envelope.StatusNeedsInput
			_ = s.store.SaveStepOutput(ctx, run.ID, node.ID+".pending", output.ToMap())
			_ = s.appendEvent(ctx, run.ID, "step_pending", "workflow state action is pending", map[string]any{"step_id": node.ID})
			return "", err
		}
		lastErr = err
		if attempts < maxAttempts && retryDelay > 0 {
			if err := sleepContext(ctx, retryDelay); err != nil {
				return "", err
			}
		}
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("state action %q failed", node.ID)
	}
	failed := envelope.NormalizeResult(run.ID, node.ID, attempts, nil, envelope.StatusFailed)
	failed.AddDiagnostic("error", "state_action_failed", "", lastErr.Error())
	_ = s.store.SaveStepOutput(ctx, run.ID, node.ID, failed.ToMap())
	if fireErr := s.fireNodeStateTrigger(ctx, run.ID, node.ID, nodeTriggerFail, attempts, nil, lastErr.Error()); fireErr != nil {
		return "", fireErr
	}
	_ = s.appendEvent(ctx, run.ID, "step_failed", lastErr.Error(), map[string]any{"step_id": node.ID})
	return "", lastErr
}

// suggestedTriggerFromStepOutput reads a persisted action route hint.
func suggestedTriggerFromStepOutput(output map[string]any) string {
	return strings.TrimSpace(envelope.FromMap(output).Control.SuggestedTrigger)
}

// executeStateActionAttempt runs one state action attempt and returns a normalized output envelope.
func (s *Service) executeStateActionAttempt(ctx context.Context, def definition.Definition, run store.RunRecord, node definition.NodeDefinition, attempts int) (envelope.Envelope, error) {
	input, err := s.stateActionContext(ctx, run)
	if err != nil {
		return envelope.Envelope{}, err
	}
	manifest := manifestForNode(node)
	inputEnvelope := envelope.New(run.ID, node.ID, attempts, input)
	inputEnvelope.Control.Status = envelope.StatusSucceeded
	policyEnvelope := inputEnvelope
	if definition.NodeAction(node) == "llm.generate" {
		policyEnvelope = policy.SanitizeLLMInput(inputEnvelope)
	}
	if err := envelopeDiagnosticsError("input", contracts.ValidateInput(inputEnvelope, node.Input)); err != nil {
		return envelope.Envelope{}, err
	}
	if err := runtimeInputPolicyError(policyEnvelope, manifest.Runtime); err != nil {
		return envelope.Envelope{}, err
	}
	if err := runtimeSandboxBoundaryError(definition.NodeAction(node), manifest.Runtime); err != nil {
		return envelope.Envelope{}, err
	}
	decision := policy.EvaluateInvocation(policyEnvelope, manifest.Effects, manifest.Runtime)
	_ = s.appendEvent(ctx, run.ID, "node_policy_decision", "workflow state action policy evaluated", map[string]any{
		"node_id": node.ID,
		"status":  decision.Status,
		"reasons": decision.Reasons,
	})
	policyApproved := decision.Status == policy.DecisionNeedsApproval && s.policyApprovalGranted(ctx, run.ID, node.ID)
	if decision.Status == policy.DecisionNeedsApproval && !policyApproved {
		if _, err := s.RequestHuman(ctx, actions.HumanRequest{
			RunID:   run.ID,
			StepID:  node.ID + ".policy",
			Prompt:  policyApprovalPrompt(node, decision),
			Payload: map[string]any{"node_id": node.ID, "policy": decision.Status, "reasons": decision.Reasons},
		}); err != nil {
			return envelope.Envelope{}, err
		}
		return envelope.Empty(run.ID, node.ID, attempts), actions.ErrPending
	}
	if !decision.Allowed() && !policyApproved {
		return envelope.Envelope{}, fmt.Errorf("state action %q policy %s: %s", node.ID, decision.Status, strings.Join(decision.Reasons, "; "))
	}
	actionCtx := ctx
	var cancel context.CancelFunc
	if timeout := nodeTimeout(node, manifest.Runtime); timeout > 0 {
		actionCtx, cancel = context.WithTimeout(ctx, timeout)
	}
	defer func() {
		if cancel != nil {
			cancel()
		}
	}()
	if rateErr := s.checkInvocationRateLimit(manifest.ID, manifest.Runtime); rateErr != nil {
		return envelope.Envelope{}, rateErr
	}
	actionInput := input
	if definition.NodeAction(node) == "llm.generate" {
		actionInput = policyEnvelope.ToMap()
	}
	output, err := s.executeStateActionOnce(actionCtx, run, node, attempts, actionInput)
	if err != nil {
		return output, err
	}
	if err := envelopeDiagnosticsError("output", contracts.ValidateOutput(output, manifest.Output)); err != nil {
		return output, err
	}
	if err := runtimeOutputPolicyError(output, manifest.Runtime); err != nil {
		return output, err
	}
	return output, nil
}

// executeStateActionOnce invokes one registered action and normalizes its output.
func (s *Service) executeStateActionOnce(ctx context.Context, run store.RunRecord, node definition.NodeDefinition, attempts int, input map[string]any) (envelope.Envelope, error) {
	action := definition.NodeAction(node)
	_ = s.appendEvent(ctx, run.ID, "step_started", "workflow state action started", map[string]any{
		"step_id": node.ID,
		"action":  action,
		"attempt": attempts,
	})
	_ = s.store.SaveStepOutput(ctx, run.ID, node.ID+".input", input)
	output, err := s.actions.Execute(ctx, action, actions.Context{
		RunID:  run.ID,
		StepID: node.ID,
		Input:  input,
		Host:   s,
	}, actionNodeArgs(node))
	status := envelope.StatusSucceeded
	if err != nil {
		status = envelope.StatusFailed
	}
	env := envelope.NormalizeResult(run.ID, node.ID, attempts, output, status)
	if err != nil && !errors.Is(err, actions.ErrPending) {
		env.AddDiagnostic("error", "state_action_failed", "", err.Error())
	}
	return env, err
}

// stateActionContext builds the reference map exposed to state-machine actions.
func (s *Service) stateActionContext(ctx context.Context, run store.RunRecord) (map[string]any, error) {
	outputs, err := s.store.StepOutputs(ctx, run.ID)
	if err != nil {
		return nil, err
	}
	input := map[string]any{
		"workflow_input":  run.Input,
		"workflow_output": run.Output,
	}
	for stepID, output := range outputs {
		if strings.HasSuffix(stepID, ".input") || strings.HasSuffix(stepID, ".pending") {
			continue
		}
		input[stepID] = stateOutputValue(output)
	}
	input["body"] = map[string]any{"value": cloneMap(input)}
	return input, nil
}

// stateOutputValue returns the action result value from a normalized envelope when present.
func stateOutputValue(output map[string]any) any {
	body, _ := output["body"].(map[string]any)
	if value, ok := body["value"]; ok {
		return value
	}
	return output
}

// stateMachineStates indexes hierarchical states by globally unique id.
func stateMachineStates(def definition.Definition) map[string]definition.StateDefinition {
	states := map[string]definition.StateDefinition{}
	var visit func([]definition.StateDefinition)
	visit = func(items []definition.StateDefinition) {
		for _, item := range items {
			states[item.ID] = item
			visit(item.States)
		}
	}
	visit(def.States)
	return states
}
