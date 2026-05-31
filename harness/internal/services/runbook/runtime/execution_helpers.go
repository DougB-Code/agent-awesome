// This file contains state-machine execution state and policy helpers.
package runtime

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/qmuntal/stateless"

	"agentawesome/internal/services/runbook/actions"
	"agentawesome/internal/services/runbook/contracts"
	"agentawesome/internal/services/runbook/definition"
	"agentawesome/internal/services/runbook/envelope"
	"agentawesome/internal/services/runbook/policy"
	"agentawesome/internal/services/runbook/store"
)

// completePendingSignals turns completed pending items into action outputs.
func (s *Service) completePendingSignals(ctx context.Context, run store.RunRecord, items []store.PendingItem, payload map[string]any) error {
	for _, item := range items {
		if item.RunID != run.ID {
			continue
		}
		attempts := nodeStateAttempts(ctx, s.store, run.ID, item.StepID)
		if attempts <= 0 {
			attempts = 1
		}
		output := envelope.New(run.ID, item.StepID, attempts, payload)
		output.Control.Status = envelope.StatusSucceeded
		outputMap := output.ToMap()
		if err := s.store.SaveStepOutput(ctx, run.ID, item.StepID, outputMap); err != nil {
			return err
		}
		if strings.HasSuffix(item.StepID, ".policy") {
			continue
		}
		if err := s.fireNodeStateTrigger(ctx, run.ID, item.StepID, nodeTriggerSucceed, attempts, outputMap, ""); err != nil {
			return err
		}
	}
	return s.store.UpdateRunState(ctx, run.ID, statusRunning, run.State, run.Output)
}

// policyApprovalGranted reports whether a policy gate was already approved for a node.
func (s *Service) policyApprovalGranted(ctx context.Context, runID string, nodeID string) bool {
	output, ok, err := s.store.StepOutput(ctx, runID, nodeID+".policy")
	if err != nil || !ok {
		return false
	}
	body, _ := output["body"].(map[string]any)
	value, _ := body["value"].(map[string]any)
	if approved, ok := value["approved"].(bool); ok {
		return approved
	}
	if approved, ok := output["approved"].(bool); ok {
		return approved
	}
	return true
}

// policyApprovalPrompt builds the pending-item prompt for one policy gate.
func policyApprovalPrompt(node definition.NodeDefinition, decision policy.Decision) string {
	reason := strings.Join(decision.Reasons, "; ")
	if reason == "" {
		reason = "node declares user-confirmed effects"
	}
	return fmt.Sprintf("Approve runbook node %q: %s", node.ID, reason)
}

// fireNodeStateTrigger uses stateless to persist one node lifecycle transition.
func (s *Service) fireNodeStateTrigger(ctx context.Context, runID string, stateID string, trigger string, attempts int, output map[string]any, message string) error {
	current := statusPending
	if record, ok, err := s.store.GetNodeState(ctx, runID, stateID); err != nil {
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
				return s.store.MarkNodeStateRunning(ctx, runID, stateID, attempts)
			case statusSucceeded:
				return s.store.MarkNodeStateSucceeded(ctx, runID, stateID, attempts, output)
			case statusFailed:
				return s.store.MarkNodeStateFailed(ctx, runID, stateID, attempts, message)
			case statusSkipped:
				return s.store.MarkNodeStateSkipped(ctx, runID, stateID, attempts, output)
			default:
				return fmt.Errorf("unsupported node state status %q", next)
			}
		},
		stateless.FiringQueued,
	)
	machine.Configure(statusPending).
		Permit(nodeTriggerStart, statusRunning).
		Permit(nodeTriggerSkip, statusSkipped)
	machine.Configure(statusRunning).
		PermitReentry(nodeTriggerStart).
		Permit(nodeTriggerSucceed, statusSucceeded).
		Permit(nodeTriggerFail, statusFailed)
	if err := machine.FireCtx(ctx, trigger); err != nil {
		return fmt.Errorf("node state %q transition %q from %q: %w", stateID, trigger, current, err)
	}
	return nil
}

// failRun marks a run failed and records the error.
func (s *Service) failRun(ctx context.Context, run store.RunRecord, err error) {
	_ = s.store.UpdateRunState(ctx, run.ID, statusFailed, run.State, map[string]any{"error": err.Error()})
	_ = s.appendEvent(ctx, run.ID, "run_failed", err.Error(), nil)
}

// nodeRetryDelay parses fixed retry delay settings for one action node.
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

// nodeTimeout resolves node timeout from duration or runtime milliseconds.
func nodeTimeout(node definition.NodeDefinition, runtime contracts.Runtime) time.Duration {
	if strings.TrimSpace(node.Timeout) != "" {
		timeout, err := time.ParseDuration(node.Timeout)
		if err == nil {
			return timeout
		}
	}
	if runtime.TimeoutMS > 0 {
		return time.Duration(runtime.TimeoutMS) * time.Millisecond
	}
	return 0
}

// runtimeInputPolicyError checks runtime limits that apply before invocation.
func runtimeInputPolicyError(input envelope.Envelope, runtime contracts.Runtime) error {
	if err := runtimeEnvelopeSizeError(input, runtime, "input"); err != nil {
		return err
	}
	return runtimeArtifactPolicyError(input, runtime, "input")
}

// runtimeOutputPolicyError checks runtime limits that apply after invocation.
func runtimeOutputPolicyError(output envelope.Envelope, runtime contracts.Runtime) error {
	if err := runtimeEnvelopeSizeError(output, runtime, "output"); err != nil {
		return err
	}
	return runtimeArtifactPolicyError(output, runtime, "output")
}

// runtimeSandboxBoundaryError checks that a node cannot claim a different host boundary.
func runtimeSandboxBoundaryError(action string, runtime contracts.Runtime) error {
	sandbox := strings.TrimSpace(runtime.Sandbox)
	if sandbox == "" {
		return nil
	}
	expected := actions.SandboxForAction(action)
	if sandbox == expected {
		return nil
	}
	return fmt.Errorf("action %q must use runtime sandbox %q, got %q", action, expected, sandbox)
}

// runtimeEnvelopeSizeError checks whole-envelope byte limits.
func runtimeEnvelopeSizeError(env envelope.Envelope, runtime contracts.Runtime, label string) error {
	if runtime.MaxInputBytes <= 0 {
		return nil
	}
	encoded, err := json.Marshal(env.ToMap())
	if err != nil {
		return fmt.Errorf("encode %s for runtime limit: %w", label, err)
	}
	if int64(len(encoded)) > runtime.MaxInputBytes {
		return fmt.Errorf("%s envelope size %d exceeds max_input_bytes %d", label, len(encoded), runtime.MaxInputBytes)
	}
	return nil
}

// runtimeArtifactPolicyError checks per-artifact declared byte limits.
func runtimeArtifactPolicyError(env envelope.Envelope, runtime contracts.Runtime, label string) error {
	if runtime.MaxArtifactBytes <= 0 {
		return nil
	}
	for _, artifact := range env.Artifacts {
		if artifact.Size > runtime.MaxArtifactBytes {
			return fmt.Errorf("%s artifact %q size %d exceeds max_artifact_bytes %d", label, artifact.ID, artifact.Size, runtime.MaxArtifactBytes)
		}
	}
	return nil
}

// actionNodeArgs builds action arguments from node config and type-specific defaults.
func actionNodeArgs(node definition.NodeDefinition) map[string]any {
	args := cloneMap(node.With)
	switch strings.ToLower(strings.TrimSpace(node.Type)) {
	case "tool":
		if mapString(args, "name") == "" && strings.TrimSpace(node.Tool) != "" {
			args["name"] = strings.TrimSpace(node.Tool)
		}
	case "mcp":
		if mapString(args, "tool") == "" && strings.TrimSpace(node.Tool) != "" {
			args["tool"] = strings.TrimSpace(node.Tool)
		}
	case "command":
		if mapString(args, "template_id") == "" && strings.TrimSpace(node.Tool) != "" {
			args["template_id"] = strings.TrimSpace(node.Tool)
		}
	case "runbook":
		if mapString(args, "runbook") == "" && strings.TrimSpace(node.Tool) != "" {
			args["runbook"] = strings.TrimSpace(node.Tool)
		}
	}
	return args
}

// mapString reads a trimmed string from an action argument map.
func mapString(values map[string]any, key string) string {
	value, _ := values[key].(string)
	return strings.TrimSpace(value)
}

// envelopeDiagnosticsError converts error diagnostics into a single runtime error.
func envelopeDiagnosticsError(stage string, diagnostics []envelope.Diagnostic) error {
	var messages []string
	for _, diagnostic := range diagnostics {
		if strings.EqualFold(strings.TrimSpace(diagnostic.Severity), "error") {
			messages = append(messages, diagnostic.Message)
		}
	}
	if len(messages) == 0 {
		return nil
	}
	return fmt.Errorf("%s envelope validation failed: %s", stage, strings.Join(messages, "; "))
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

// nodeStatusByID indexes durable node-state records by node id.
func nodeStatusByID(records []store.NodeStateRecord) map[string]store.NodeStateRecord {
	statuses := map[string]store.NodeStateRecord{}
	for _, record := range records {
		statuses[record.StateID] = record
	}
	return statuses
}

// nodeStateAttempts returns persisted attempts for one runbook node.
func nodeStateAttempts(ctx context.Context, runbookStore *store.Store, runID string, stateID string) int {
	record, ok, err := runbookStore.GetNodeState(ctx, runID, stateID)
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

// containsPending reports whether a runbook error includes a pending action.
func containsPending(err error) bool {
	return err != nil && strings.Contains(err.Error(), actions.ErrPending.Error())
}
