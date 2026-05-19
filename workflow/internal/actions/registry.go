// This file defines the workflow action registry and shared execution context.
package actions

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"
)

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
	RunAgent(context.Context, AgentRequest) (map[string]any, error)
	CallTool(context.Context, ToolRequest) (map[string]any, error)
	CallMCP(context.Context, MCPRequest) (map[string]any, error)
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

// AgentRequest describes one scoped harness agent invocation.
type AgentRequest struct {
	RunID        string
	StepID       string
	Agent        string
	Instructions string
	Input        map[string]any
}

// MCPRequest describes one MCP tool call action.
type MCPRequest struct {
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
	r.Register("agent.run", agentRun)
	r.Register("tool.call", toolCall)
	r.Register("mcp.call", mcpCall)
	r.Register("cli.command", cliCommand)
	r.Register("dag.run", dagRun)
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

// agentRun delegates a reasoning step to the harness through the workflow host.
func agentRun(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("agent.run host is not configured")
	}
	return execCtx.Host.RunAgent(ctx, AgentRequest{
		RunID:        execCtx.RunID,
		StepID:       execCtx.StepID,
		Agent:        stringArg(args, "agent"),
		Instructions: stringArg(args, "instructions"),
		Input:        mapArgWithInputFallback(args, "input", execCtx.Input),
	})
}

// toolCall delegates a generic tool call to the harness context API.
func toolCall(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("tool.call host is not configured")
	}
	return execCtx.Host.CallTool(ctx, ToolRequest{
		Name:      stringArg(args, "name"),
		DomainID:  stringArg(args, "domain_id"),
		Arguments: mapArgWithInputFallback(args, "arguments", execCtx.Input),
	})
}

// mcpCall delegates a tool call to a configured MCP endpoint.
func mcpCall(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("mcp.call host is not configured")
	}
	return execCtx.Host.CallMCP(ctx, MCPRequest{
		Endpoint:  stringArg(args, "endpoint"),
		Tool:      stringArg(args, "tool"),
		Arguments: mapArg(args, "arguments", nil),
	})
}

// cliCommand rejects direct command execution until an allowlist host is added.
func cliCommand(context.Context, Context, map[string]any) (map[string]any, error) {
	return nil, fmt.Errorf("cli.command is registered but no command allowlist executor is configured")
}

// dagRun starts a nested workflow through the durable workflow host.
func dagRun(ctx context.Context, execCtx Context, args map[string]any) (map[string]any, error) {
	if execCtx.Host == nil {
		return nil, fmt.Errorf("dag.run host is not configured")
	}
	workflow := stringArg(args, "workflow")
	if workflow == "" {
		return nil, fmt.Errorf("dag.run workflow is required")
	}
	return execCtx.Host.StartNestedWorkflow(ctx, NestedWorkflowRequest{
		DefinitionID: workflow,
		Input:        mapArgWithInputFallback(args, "input", execCtx.Input),
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

// mapArgWithInputFallback returns action input when an editable JSON object is empty.
func mapArgWithInputFallback(args map[string]any, key string, fallback map[string]any) map[string]any {
	value := mapArg(args, key, fallback)
	if len(value) == 0 && len(fallback) > 0 {
		return fallback
	}
	return value
}
