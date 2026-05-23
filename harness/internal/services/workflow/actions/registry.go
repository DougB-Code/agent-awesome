// This file defines the workflow action registry and shared execution context.
package actions

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"agentawesome/internal/services/workflow/decision"
	"agentawesome/internal/services/workflow/envelope"
)

// decisionEnvelopeAttempt marks action-local output before the runtime normalizes attempts.
const decisionEnvelopeAttempt = 0

// ErrPending reports that a workflow is waiting for a user or external signal.
var ErrPending = errors.New("workflow action pending")

// Executor runs one registered workflow action.
type Executor func(context.Context, Context, map[string]any) (map[string]any, error)

// Context carries durable workflow identifiers into action execution.
type Context struct {
	RunID  string
	StepID string
	Input  map[string]any
	Host   Host
}

// Host exposes workflow services needed by selected actions.
type Host interface {
	RequestHuman(context.Context, HumanRequest) (string, error)
	CallTool(context.Context, ToolRequest) (map[string]any, error)
	CallMCP(context.Context, MCPRequest) (map[string]any, error)
	ExecuteCommand(context.Context, CommandRequest) (map[string]any, error)
	GenerateLLM(context.Context, LLMRequest) (map[string]any, error)
	SignalWorkflow(context.Context, WorkflowSignal) error
	StartNestedWorkflow(context.Context, NestedWorkflowRequest) (map[string]any, error)
}

// HumanRequest describes a pending user work item.
type HumanRequest struct {
	RunID   string
	StepID  string
	Prompt  string
	Payload map[string]any
}

// MCPRequest describes one MCP tool call action.
type MCPRequest struct {
	ServerID  string
	Endpoint  string
	Tool      string
	Arguments map[string]any
}

// ToolRequest describes one harness-owned context tool call action.
type ToolRequest struct {
	Name      string
	DomainID  string
	Arguments map[string]any
}

// CommandRequest describes one configured command execution action.
type CommandRequest struct {
	TemplateID string
	Parameters map[string]any
	WorkingDir string
	Reason     string
	Actor      string
	SessionID  string
}

// LLMRequest describes one schema-constrained model invocation.
type LLMRequest struct {
	Model        string
	Prompt       string
	Input        map[string]any
	OutputSchema map[string]any
}

// WorkflowSignal describes an internal workflow signal action.
type WorkflowSignal struct {
	RunID   string
	Signal  string
	Payload map[string]any
}

// NestedWorkflowRequest describes a child workflow start action.
type NestedWorkflowRequest struct {
	DefinitionID string
	Input        map[string]any
}

// Registry stores installed action executors by action type.
type Registry struct {
	actions map[string]Executor
}

// NewRegistry returns the default built-in workflow action registry.
func NewRegistry() *Registry {
	r := &Registry{actions: map[string]Executor{}}
	r.Register("tool.call", toolCall)
	r.Register("mcp.call", mcpCall)
	r.Register("command.execute", commandExecute)
	r.Register("data.assert", dataAssert)
	r.Register("data.defaults", dataDefaults)
	r.Register("decision.route", decisionRoute)
	r.Register("llm.generate", llmGenerate)
	r.Register("workflow.run", workflowRun)
	r.Register("workflow.signal", workflowSignal)
	r.Register("human.request", humanRequest)
	r.Register("delay.until", delayUntil)
	return r
}

// Register installs or replaces one action executor.
func (r *Registry) Register(name string, executor Executor) {
	if r.actions == nil {
		r.actions = map[string]Executor{}
	}
	r.actions[strings.TrimSpace(name)] = executor
}

// Has reports whether an action type is installed.
func (r *Registry) Has(name string) bool {
	if r == nil {
		return false
	}
	_, ok := r.actions[strings.TrimSpace(name)]
	return ok
}

// Names returns installed action names in stable order.
func (r *Registry) Names() []string {
	names := make([]string, 0, len(r.actions))
	for name := range r.actions {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// Execute runs one installed action by name.
func (r *Registry) Execute(ctx context.Context, action string, execCtx Context, args map[string]any) (map[string]any, error) {
	if r == nil {
		return nil, fmt.Errorf("action registry is nil")
	}
	executor, ok := r.actions[strings.TrimSpace(action)]
	if !ok {
		return nil, fmt.Errorf("action %q is not registered", action)
	}
	return executor(ctx, execCtx, args)
}

// decisionRoute evaluates ordered route rules over the node input envelope.
func decisionRoute(_ context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	def, err := decision.FromMap(args)
	if err != nil {
		return nil, err
	}
	result, err := decision.Evaluate(def, envelope.FromMap(execCtx.Input))
	if err != nil {
		return nil, err
	}
	output := decision.OutputEnvelope(execCtx.RunID, execCtx.StepID, decisionEnvelopeAttempt, result)
	return output.ToMap(), nil
}

// toolCall delegates a generic tool call to the harness context API.
func toolCall(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("tool.call host is not configured")
	}
	return execCtx.Host.CallTool(ctx, ToolRequest{
		Name:      resolvedStringArg(args, "name", execCtx.Input),
		DomainID:  resolvedStringArg(args, "domain_id", execCtx.Input),
		Arguments: resolvedMapArg(args, "arguments", nil, execCtx.Input),
	})
}

// mcpCall delegates a tool call to a configured MCP endpoint.
func mcpCall(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("mcp.call host is not configured")
	}
	return execCtx.Host.CallMCP(ctx, MCPRequest{
		ServerID:  resolvedStringArg(args, "server_id", execCtx.Input),
		Endpoint:  resolvedStringArg(args, "endpoint", execCtx.Input),
		Tool:      resolvedStringArg(args, "tool", execCtx.Input),
		Arguments: resolvedMapArg(args, "arguments", nil, execCtx.Input),
	})
}

// commandExecute runs a configured command template through the command boundary.
func commandExecute(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("command.execute host is not configured")
	}
	return execCtx.Host.ExecuteCommand(ctx, CommandRequest{
		TemplateID: resolvedStringArg(args, "template_id", execCtx.Input),
		Parameters: resolvedMapArg(args, "parameters", nil, execCtx.Input),
		WorkingDir: resolvedStringArg(args, "cwd", execCtx.Input),
		Reason:     resolvedStringArg(args, "reason", execCtx.Input),
		Actor:      resolvedStringArg(args, "actor", execCtx.Input),
		SessionID:  resolvedStringArg(args, "session_id", execCtx.Input),
	})
}

// llmGenerate calls the configured model boundary and requires structured output.
func llmGenerate(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("llm.generate host is not configured")
	}
	prompt := resolvedStringArg(args, "prompt", execCtx.Input)
	if prompt == "" {
		return nil, fmt.Errorf("llm.generate prompt is required")
	}
	return execCtx.Host.GenerateLLM(ctx, LLMRequest{
		Model:        resolvedStringArg(args, "model", execCtx.Input),
		Prompt:       prompt,
		Input:        execCtx.Input,
		OutputSchema: resolvedMapArg(args, "output_schema", nil, execCtx.Input),
	})
}

// workflowRun starts a nested workflow through the durable workflow host.
func workflowRun(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("workflow.run host is not configured")
	}
	workflow := stringArg(args, "workflow")
	if workflow == "" {
		return nil, fmt.Errorf("workflow.run workflow is required")
	}
	return execCtx.Host.StartNestedWorkflow(ctx, NestedWorkflowRequest{
		DefinitionID: workflow,
		Input:        resolvedMapArg(args, "input", execCtx.Input, execCtx.Input),
	})
}

// workflowSignal emits an internal workflow signal through the host.
func workflowSignal(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("workflow.signal host is not configured")
	}
	signal := WorkflowSignal{
		RunID:   stringArg(args, "run_id"),
		Signal:  stringArg(args, "signal"),
		Payload: mapArg(args, "payload", nil),
	}
	if signal.RunID == "" {
		signal.RunID = execCtx.RunID
	}
	if signal.Signal == "" {
		return nil, fmt.Errorf("workflow.signal signal is required")
	}
	if err := execCtx.Host.SignalWorkflow(ctx, signal); err != nil {
		return nil, err
	}
	return map[string]any{"run_id": signal.RunID, "signal": signal.Signal}, nil
}

// humanRequest creates a pending item and pauses workflow execution.
func humanRequest(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("human.request host is not configured")
	}
	pendingID, err := execCtx.Host.RequestHuman(ctx, HumanRequest{
		RunID:   execCtx.RunID,
		StepID:  execCtx.StepID,
		Prompt:  stringArg(args, "prompt"),
		Payload: mapArg(args, "payload", nil),
	})
	if err != nil {
		return nil, err
	}
	return map[string]any{"pending_id": pendingID}, ErrPending
}

// delayUntil sleeps until the configured RFC3339 timestamp or duration.
func delayUntil(ctx context.Context, _ Context, args map[string]any) (map[string]any, error) {
	until := stringArg(args, "until")
	duration := stringArg(args, "duration")
	var wait time.Duration
	switch {
	case until != "":
		timestamp, err := time.Parse(time.RFC3339, until)
		if err != nil {
			return nil, fmt.Errorf("delay.until invalid until: %w", err)
		}
		wait = time.Until(timestamp)
	case duration != "":
		parsed, err := time.ParseDuration(duration)
		if err != nil {
			return nil, fmt.Errorf("delay.until invalid duration: %w", err)
		}
		wait = parsed
	default:
		return nil, fmt.Errorf("delay.until requires until or duration")
	}
	if wait <= 0 {
		return map[string]any{"waited": "0s"}, nil
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-timer.C:
		return map[string]any{"waited": wait.String()}, nil
	}
}

// stringArg returns a string argument by key.
func stringArg(args map[string]any, key string) string {
	value, _ := args[key].(string)
	return strings.TrimSpace(value)
}

// mapArg returns a map argument by key or a fallback.
func mapArg(args map[string]any, key string, fallback map[string]any) map[string]any {
	value, ok := args[key].(map[string]any)
	if !ok || value == nil {
		return fallback
	}
	return value
}
