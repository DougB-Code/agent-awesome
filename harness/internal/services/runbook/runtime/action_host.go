// This file implements the action host boundary used by runbook actions.
package runtime

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"agentawesome/internal/services/command/command"
	"agentawesome/internal/services/runbook/actions"
	"agentawesome/internal/services/runbook/jsondata"
	"agentawesome/internal/services/runbook/policy"
	"agentawesome/internal/services/runbook/store"
)

// RequestHuman records a pending user-visible item without contacting channels.
func (s *Service) RequestHuman(ctx context.Context, req actions.HumanRequest) (string, error) {
	if policy.ContainsSensitiveKey(req.Payload) {
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
		Status:  store.PendingStatusOpen,
		Prompt:  req.Prompt,
		Payload: req.Payload,
	}); err != nil {
		return "", err
	}
	_ = s.appendEvent(ctx, req.RunID, "human_requested", "runbook is waiting for user input", map[string]any{"pending_id": id, "step_id": req.StepID})
	return id, nil
}

// CallTool invokes one harness context tool.
func (s *Service) CallTool(ctx context.Context, req actions.ToolRequest) (map[string]any, error) {
	return s.tools.Call(ctx, req)
}

// CallMCP invokes one MCP tool endpoint.
func (s *Service) CallMCP(ctx context.Context, req actions.MCPRequest) (map[string]any, error) {
	if strings.TrimSpace(req.Endpoint) == "" {
		endpoint, ok := s.mcpEndpoints[strings.TrimSpace(req.ServerID)]
		if !ok || strings.TrimSpace(endpoint) == "" {
			return nil, fmt.Errorf("mcp.call server %q is not configured", req.ServerID)
		}
		req.Endpoint = endpoint
	}
	return s.mcp.Call(ctx, req)
}

// ExecuteCommand runs one configured command template.
func (s *Service) ExecuteCommand(ctx context.Context, req actions.CommandRequest) (map[string]any, error) {
	if s.commands == nil {
		return nil, fmt.Errorf("command.execute host is not configured")
	}
	status, err := s.commands.Execute(ctx, command.ExecuteRequest{
		TemplateID: strings.TrimSpace(req.TemplateID),
		Parameters: req.Parameters,
		WorkingDir: strings.TrimSpace(req.WorkingDir),
		Reason:     strings.TrimSpace(req.Reason),
		Actor:      strings.TrimSpace(req.Actor),
		SessionID:  strings.TrimSpace(req.SessionID),
	})
	if err != nil {
		return nil, err
	}
	return commandStatusMap(status)
}

// GenerateLLM invokes the configured model boundary for structured JSON output.
func (s *Service) GenerateLLM(ctx context.Context, req actions.LLMRequest) (map[string]any, error) {
	if s.llm == nil {
		return nil, fmt.Errorf("llm.generate host is not configured")
	}
	if strings.TrimSpace(req.Prompt) == "" {
		return nil, fmt.Errorf("llm.generate prompt is required")
	}
	result, err := s.llm.GenerateRunbookJSON(ctx, req)
	if err != nil {
		return nil, err
	}
	if result == nil {
		return nil, fmt.Errorf("llm.generate returned no structured result")
	}
	if len(req.OutputSchema) > 0 {
		if errors := jsondata.ValidateSchema(result, req.OutputSchema, "result", true); len(errors) > 0 {
			return nil, fmt.Errorf("llm.generate output schema validation failed: %s", schemaErrorSummary(errors))
		}
	}
	return result, nil
}

// commandStatusMap converts command results into runbook step output data.
func commandStatusMap(status command.StatusResult) (map[string]any, error) {
	data, err := json.Marshal(status)
	if err != nil {
		return nil, fmt.Errorf("encode command result: %w", err)
	}
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("decode command result: %w", err)
	}
	return result, nil
}

// schemaErrorSummary returns a compact schema validation summary.
func schemaErrorSummary(errors []jsondata.SchemaError) string {
	messages := make([]string, 0, len(errors))
	for _, err := range errors {
		messages = append(messages, err.Message)
	}
	return strings.Join(messages, "; ")
}

// SignalRunbook applies an internal signal from an action.
func (s *Service) SignalRunbook(ctx context.Context, signal actions.RunbookSignal) error {
	_, err := s.Signal(ctx, signal.RunID, signal.Signal, signal.Payload)
	return err
}

// StartNestedRunbook starts a child runbook from a runbook action.
func (s *Service) StartNestedRunbook(ctx context.Context, req actions.NestedRunbookRequest) (map[string]any, error) {
	run, err := s.StartRunbook(ctx, req.DefinitionID, req.Input)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"run_id":        run.ID,
		"definition_id": run.DefinitionID,
		"status":        run.Status,
	}, nil
}
