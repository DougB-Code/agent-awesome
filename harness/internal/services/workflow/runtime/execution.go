// This file schedules and invokes workflow pipe graph nodes.
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

// executeRun resumes a run according to the workflow graph definition.
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
	err = s.executePipeGraph(ctx, def, run)
	if err == nil {
		return
	}
	if errors.Is(err, actions.ErrPending) {
		run, _ = s.store.GetRun(ctx, run.ID)
		_ = s.store.UpdateRunState(ctx, run.ID, statusWaiting, run.State, run.Output)
		return
	}
	s.failRun(ctx, run, err)
}

// executePipeGraph schedules ready pipe graph nodes until the graph completes.
func (s *Service) executePipeGraph(ctx context.Context, def definition.Definition, run store.RunRecord) error {
	nodes := pipeNodesByID(def)
	execCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	inFlight := map[string]struct{}{}
	results := make(chan nodeStateResult, len(nodes))
	for {
		records, err := s.store.ListNodeStates(ctx, run.ID)
		if err != nil {
			return err
		}
		statuses := nodeStatusByID(records)
		if pipeNodesSucceeded(nodes, statuses) {
			output, err := s.pipeGraphOutput(ctx, def, run.ID)
			if err != nil {
				return err
			}
			_ = s.store.UpdateRunState(ctx, run.ID, statusSucceeded, run.State, output)
			_ = s.appendEvent(ctx, run.ID, "run_succeeded", "workflow run succeeded", nil)
			return nil
		}
		if failedID, failed := firstFailedPipeNode(nodes, statuses); failed {
			return fmt.Errorf("node %q failed: %s", failedID, statuses[failedID].Error)
		}
		progressed := false
		for _, node := range def.Nodes {
			if _, ok := inFlight[node.ID]; ok {
				continue
			}
			if record, ok := statuses[node.ID]; ok && pipeNodeTerminalStatus(record.Status) {
				continue
			}
			if !pipeDependenciesTerminal(def, node.ID, statuses) {
				continue
			}
			if len(incomingEdges(def, node.ID)) > 0 {
				active, err := s.pipeActiveIncomingEdges(ctx, def, run.ID, node.ID, statuses)
				if err != nil {
					return err
				}
				if len(active) == 0 {
					if err := s.skipPipeNode(ctx, run, node, "no active incoming edges"); err != nil {
						return err
					}
					progressed = true
					continue
				}
			}
			inFlight[node.ID] = struct{}{}
			go func(item definition.NodeDefinition) {
				results <- nodeStateResult{stateID: item.ID, err: s.executePipeNode(execCtx, def, run, item)}
			}(node)
		}
		if len(inFlight) == 0 {
			if progressed {
				continue
			}
			return fmt.Errorf("workflow nodes are blocked by incomplete dependencies")
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

// executePipeNode runs one pipe graph node with envelope validation and policy.
func (s *Service) executePipeNode(ctx context.Context, def definition.Definition, run store.RunRecord, node definition.NodeDefinition) error {
	if record, ok, err := s.store.GetNodeState(ctx, run.ID, node.ID); err != nil {
		return err
	} else if ok && pipeNodeTerminalStatus(record.Status) {
		return nil
	}
	attempts := nodeStateAttempts(ctx, s.store, run.ID, node.ID)
	maxAttempts := node.Retry + 1
	retryDelay, err := nodeRetryDelay(node)
	if err != nil {
		return err
	}
	var lastErr error
	for attempts < maxAttempts {
		attempts++
		if err := s.fireNodeStateTrigger(ctx, run.ID, node.ID, nodeTriggerStart, attempts, nil, ""); err != nil {
			return err
		}
		manifest := manifestForNode(node)
		input, err := s.pipeNodeInput(ctx, def, run, node, attempts)
		if err == nil && definition.NodeAction(node) == "llm.generate" {
			input = policy.SanitizeLLMInput(input)
		}
		if err != nil {
			lastErr = err
		} else if err := envelopeDiagnosticsError("input", contracts.ValidateInput(input, node.Input)); err != nil {
			lastErr = err
		} else if err := runtimeInputPolicyError(input, manifest.Runtime); err != nil {
			lastErr = err
		} else if err := runtimeSandboxBoundaryError(definition.NodeAction(node), manifest.Runtime); err != nil {
			lastErr = err
		} else {
			decision := policy.EvaluateInvocation(input, manifest.Effects, manifest.Runtime)
			_ = s.appendEvent(ctx, run.ID, "node_policy_decision", "workflow node policy evaluated", map[string]any{
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
					lastErr = err
				} else {
					return actions.ErrPending
				}
			} else if !decision.Allowed() && !policyApproved {
				lastErr = fmt.Errorf("node %q policy %s: %s", node.ID, decision.Status, strings.Join(decision.Reasons, "; "))
			} else {
				actionCtx := ctx
				var cancel context.CancelFunc
				if timeout := nodeTimeout(node, manifest.Runtime); timeout > 0 {
					actionCtx, cancel = context.WithTimeout(ctx, timeout)
				}
				if rateErr := s.checkInvocationRateLimit(manifest.ID, manifest.Runtime); rateErr != nil {
					lastErr = rateErr
					if cancel != nil {
						cancel()
					}
				} else if output, err := s.executePipeAction(actionCtx, run, node, attempts, input); err == nil {
					if cancel != nil {
						cancel()
					}
					if validationErr := envelopeDiagnosticsError("output", contracts.ValidateOutput(output, manifest.Output)); validationErr != nil {
						lastErr = validationErr
					} else if policyErr := runtimeOutputPolicyError(output, manifest.Runtime); policyErr != nil {
						lastErr = policyErr
					} else {
						outputMap := output.ToMap()
						if err := s.store.SaveStepOutput(ctx, run.ID, node.ID, outputMap); err != nil {
							return err
						}
						if err := s.recordObservedContract(ctx, def, node, output); err != nil {
							_ = s.appendEvent(ctx, run.ID, "contract_observation_failed", err.Error(), map[string]any{"node_id": node.ID})
						}
						return s.fireNodeStateTrigger(ctx, run.ID, node.ID, nodeTriggerSucceed, attempts, outputMap, "")
					}
				} else if errors.Is(err, actions.ErrPending) {
					if cancel != nil {
						cancel()
					}
					_ = s.store.SaveStepOutput(ctx, run.ID, node.ID+".pending", output.ToMap())
					return err
				} else {
					if cancel != nil {
						cancel()
					}
					lastErr = err
				}
			}
		}
		if attempts < maxAttempts && retryDelay > 0 {
			if err := sleepContext(ctx, retryDelay); err != nil {
				return err
			}
		}
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("node %q failed", node.ID)
	}
	if err := s.fireNodeStateTrigger(ctx, run.ID, node.ID, nodeTriggerFail, attempts, nil, lastErr.Error()); err != nil {
		return err
	}
	return lastErr
}

// executePipeAction invokes one node action and persists its input envelope.
func (s *Service) executePipeAction(ctx context.Context, run store.RunRecord, node definition.NodeDefinition, attempts int, input envelope.Envelope) (envelope.Envelope, error) {
	action := definition.NodeAction(node)
	stepID := node.ID
	actionInput := input
	_ = s.appendEvent(ctx, run.ID, "step_started", "workflow node started", map[string]any{
		"step_id": stepID,
		"action":  action,
		"tool":    strings.TrimSpace(node.Tool),
		"type":    strings.TrimSpace(node.Type),
		"attempt": attempts,
	})
	_ = s.store.SaveStepOutput(ctx, run.ID, stepID+".input", actionInput.ToMap())
	output, err := s.actions.Execute(ctx, action, actions.Context{
		RunID:  run.ID,
		StepID: stepID,
		Input:  actionInput.ToMap(),
		Host:   s,
	}, pipeNodeArgs(node))
	status := envelope.StatusSucceeded
	if err != nil {
		status = envelope.StatusFailed
	}
	env := envelope.NormalizeResult(run.ID, node.ID, attempts, output, status)
	if err != nil {
		if errors.Is(err, actions.ErrPending) {
			env.Control.Status = envelope.StatusNeedsInput
			_ = s.appendEvent(ctx, run.ID, "step_pending", "workflow node is pending", map[string]any{"step_id": stepID})
			return env, err
		}
		env.AddDiagnostic("error", "node_action_failed", "", err.Error())
		_ = s.appendEvent(ctx, run.ID, "step_failed", err.Error(), map[string]any{"step_id": stepID})
		return env, err
	}
	_ = s.appendEvent(ctx, run.ID, "step_succeeded", "workflow node succeeded", map[string]any{"step_id": stepID})
	return env, nil
}
