// This file implements portable tool-package validation execution.
package toolvalidation

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/agentvalidation"
	"agentawesome/internal/services/command/command"
	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/jsondata"
)

const (
	// StatusPassed means all validation assertions succeeded.
	StatusPassed = "passed"
	// StatusFailed means at least one validation assertion failed.
	StatusFailed = "failed"
	// StatusUnsupported means the runner cannot execute the target mode yet.
	StatusUnsupported = "unsupported"
)

// CommandExecutor runs configured command templates through the command boundary.
type CommandExecutor interface {
	Execute(context.Context, command.ExecuteRequest) (command.StatusResult, error)
}

// MCPExecutor runs configured MCP tools through an MCP boundary.
type MCPExecutor interface {
	CallMCP(context.Context, actions.MCPRequest) (map[string]any, error)
}

// Runner executes portable validations from one tool package.
type Runner struct {
	commands  CommandExecutor
	mcp       MCPExecutor
	agent     schema.Agent
	agentHost agentvalidation.AgentHost
}

// MissingValidationError reports selected validation IDs absent from a package.
type MissingValidationError struct {
	IDs []string
}

// Error returns a compact missing validation message for CLI and UI callers.
func (e MissingValidationError) Error() string {
	return "tool validations not found: " + strings.Join(e.IDs, ", ")
}

// NewRunner creates a validation runner with optional boundary clients.
func NewRunner(commands CommandExecutor) *Runner {
	return &Runner{commands: commands}
}

// NewRunnerWithMCP creates a validation runner with live MCP support.
func NewRunnerWithMCP(commands CommandExecutor, mcp MCPExecutor) *Runner {
	return &Runner{commands: commands, mcp: mcp}
}

// NewRunnerWithAgentHost creates a validation runner with live agent-call support.
func NewRunnerWithAgentHost(commands CommandExecutor, agent schema.Agent, host agentvalidation.AgentHost) *Runner {
	return &Runner{commands: commands, agent: agent, agentHost: host}
}

// NewRunnerWithBoundaries creates a runner with every live validation boundary.
func NewRunnerWithBoundaries(commands CommandExecutor, mcp MCPExecutor, agent schema.Agent, host agentvalidation.AgentHost) *Runner {
	return &Runner{commands: commands, mcp: mcp, agent: agent, agentHost: host}
}

// SuiteResult stores one full validation run for a tool package.
type SuiteResult struct {
	Total               int                          `json:"total"`
	Passed              int                          `json:"passed"`
	Failed              int                          `json:"failed"`
	Unsupported         int                          `json:"unsupported"`
	Results             []Result                     `json:"results"`
	Coverage            Coverage                     `json:"coverage"`
	InputSchemaCoverage Coverage                     `json:"input_schema_coverage"`
	MissingAssertions   []string                     `json:"missing_assertions,omitempty"`
	AgentToolCalls      []string                     `json:"agent_tool_calls,omitempty"`
	AgentToolContracts  map[string]AgentToolContract `json:"agent_tool_contracts,omitempty"`
}

// Result stores one validation case result.
type Result struct {
	ID          string                `json:"id"`
	Label       string                `json:"label,omitempty"`
	Description string                `json:"description,omitempty"`
	Mode        string                `json:"mode"`
	Status      string                `json:"status"`
	Target      TargetResult          `json:"target"`
	Command     *command.StatusResult `json:"command,omitempty"`
	Assertions  []AssertionResult     `json:"assertions,omitempty"`
	Diagnostics []Diagnostic          `json:"diagnostics,omitempty"`
}

// TargetResult describes the invocation target used for a validation.
type TargetResult struct {
	Type       string `json:"type"`
	PresetID   string `json:"preset_id,omitempty"`
	Command    string `json:"command,omitempty"`
	Operation  string `json:"operation,omitempty"`
	MCPServer  string `json:"mcp_server,omitempty"`
	MCPTool    string `json:"mcp_tool,omitempty"`
	TemplateID string `json:"template_id,omitempty"`
	Boundary   string `json:"boundary,omitempty"`
}

// AssertionResult stores the outcome of one validation assertion.
type AssertionResult struct {
	Type     string `json:"type"`
	Path     string `json:"path,omitempty"`
	Passed   bool   `json:"passed"`
	Expected any    `json:"expected,omitempty"`
	Actual   any    `json:"actual,omitempty"`
	Message  string `json:"message,omitempty"`
}

// Diagnostic stores one validation runner diagnostic.
type Diagnostic struct {
	Severity string `json:"severity"`
	Message  string `json:"message"`
}

// Coverage summarizes whether configured callable surfaces have validations.
type Coverage struct {
	Required int            `json:"required"`
	Covered  int            `json:"covered"`
	Missing  []CoverageItem `json:"missing,omitempty"`
}

// CoverageItem identifies one configured target missing validation coverage.
type CoverageItem struct {
	Type  string `json:"type"`
	ID    string `json:"id"`
	Label string `json:"label,omitempty"`
}

// AgentToolContract describes an agent-callable packaged tool surface.
type AgentToolContract struct {
	ID          string         `json:"id"`
	InputSchema map[string]any `json:"input_schema,omitempty"`
}

// RunAll executes every validation declared by the tool package.
func (r *Runner) RunAll(ctx context.Context, tools schema.Tools) SuiteResult {
	result := SuiteResult{
		Results:             make([]Result, 0, len(tools.Validations)),
		Coverage:            CoverageForMode(tools, ""),
		InputSchemaCoverage: InputSchemaCoverageFor(tools),
		AgentToolCalls:      AgentToolCallIDsFor(tools),
		AgentToolContracts:  AgentToolContractsFor(tools),
	}
	for _, validation := range tools.Validations {
		item := r.Run(ctx, tools, validation)
		addResult(&result, item)
	}
	return result
}

// RunSelected executes selected validation IDs from one tool package.
func (r *Runner) RunSelected(ctx context.Context, tools schema.Tools, validationIDs []string) (SuiteResult, error) {
	return r.RunSelectedModes(ctx, tools, validationIDs, "")
}

// RunSelectedModes executes selected validations that match one validation mode.
func (r *Runner) RunSelectedModes(ctx context.Context, tools schema.Tools, validationIDs []string, mode string) (SuiteResult, error) {
	ids := selectedValidationIDs(validationIDs)
	filter := selectedValidationMode(mode)
	if len(ids) == 0 && filter == "" {
		return r.RunAll(ctx, tools), nil
	}
	byID := map[string]schema.ToolValidation{}
	for _, validation := range tools.Validations {
		id := strings.TrimSpace(validation.ID)
		if id != "" {
			byID[id] = validation
		}
	}
	result := SuiteResult{
		Results:             make([]Result, 0, len(ids)),
		Coverage:            CoverageForMode(tools, filter),
		InputSchemaCoverage: InputSchemaCoverageFor(tools),
		AgentToolCalls:      AgentToolCallIDsFor(tools),
		AgentToolContracts:  AgentToolContractsFor(tools),
	}
	if len(ids) == 0 {
		for _, validation := range tools.Validations {
			if !validationMatchesMode(validation.Mode, filter) {
				continue
			}
			addResult(&result, r.Run(ctx, tools, validation))
		}
		return result, nil
	}
	missing := make([]string, 0, len(ids))
	for _, id := range ids {
		validation, ok := byID[id]
		if !ok || !validationMatchesMode(validation.Mode, filter) {
			missing = append(missing, id)
			continue
		}
		addResult(&result, r.Run(ctx, tools, validation))
	}
	if len(missing) > 0 {
		return result, MissingValidationError{IDs: missing}
	}
	return result, nil
}

// CoverageFor reports configured targets that do or do not have validations.
func CoverageFor(tools schema.Tools) Coverage {
	return CoverageForMode(tools, "")
}

// CoverageForMode reports configured target coverage for one validation lane.
func CoverageForMode(tools schema.Tools, mode string) Coverage {
	required := validationCoverageTargets(tools)
	covered := validationCoveredTargets(filterToolValidationsByMode(tools.Validations, mode))
	missing := make([]CoverageItem, 0, len(required))
	coveredCount := 0
	for _, item := range required {
		if covered[coverageKey(item.Type, item.ID)] {
			coveredCount++
			continue
		}
		missing = append(missing, item)
	}
	return Coverage{
		Required: len(required),
		Covered:  coveredCount,
		Missing:  missing,
	}
}

// InputSchemaCoverageFor reports command operations missing input schemas.
func InputSchemaCoverageFor(tools schema.Tools) Coverage {
	required := inputSchemaCoverageTargets(tools)
	missing := make([]CoverageItem, 0, len(required))
	coveredCount := 0
	for _, item := range required {
		if len(inputSchemaForOperation(tools, item.ID)) > 0 {
			coveredCount++
			continue
		}
		missing = append(missing, item)
	}
	return Coverage{
		Required: len(required),
		Covered:  coveredCount,
		Missing:  missing,
	}
}

// AgentToolCallIDsFor reports callable tool ids available to agent validations.
func AgentToolCallIDsFor(tools schema.Tools) []string {
	ids := make([]string, 0)
	seen := map[string]struct{}{}
	for _, item := range validationCoverageTargets(tools) {
		if item.Type != "agent-tool-call" {
			continue
		}
		id := strings.TrimSpace(item.ID)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		ids = append(ids, id)
	}
	return ids
}

// AgentToolContractsFor reports agent-callable ids and their input schemas.
func AgentToolContractsFor(tools schema.Tools) map[string]AgentToolContract {
	contracts := map[string]AgentToolContract{}
	for _, command := range tools.LocalExec.Commands {
		commandName := strings.TrimSpace(command.Name)
		for _, operation := range command.Operations {
			operationName := strings.TrimSpace(operation.Name)
			if commandName == "" || operationName == "" {
				continue
			}
			id := "command:" + commandName + "." + operationName
			contracts[id] = AgentToolContract{
				ID:          id,
				InputSchema: cloneMap(operation.InputSchema),
			}
		}
	}
	for _, server := range tools.MCP.Servers {
		serverName := strings.TrimSpace(server.Name)
		for _, tool := range server.Tools.Allow {
			toolName := strings.TrimSpace(tool)
			if serverName == "" || toolName == "" {
				continue
			}
			id := "mcp:" + serverName + "." + toolName
			contracts[id] = AgentToolContract{ID: id}
		}
	}
	return contracts
}

// inputSchemaCoverageTargets returns all command operations needing schemas.
func inputSchemaCoverageTargets(tools schema.Tools) []CoverageItem {
	items := []CoverageItem{}
	for _, command := range tools.LocalExec.Commands {
		commandName := strings.TrimSpace(command.Name)
		for _, operation := range command.Operations {
			operationName := strings.TrimSpace(operation.Name)
			if commandName == "" || operationName == "" {
				continue
			}
			id := commandName + "." + operationName
			items = append(items, CoverageItem{
				Type:  "command-operation-input-schema",
				ID:    id,
				Label: firstNonEmpty(operation.Description, id),
			})
		}
	}
	return items
}

// inputSchemaForOperation returns the schema for a command.operation id.
func inputSchemaForOperation(tools schema.Tools, id string) map[string]any {
	parts := strings.Split(strings.TrimSpace(id), ".")
	if len(parts) != 2 {
		return nil
	}
	for _, command := range tools.LocalExec.Commands {
		if strings.TrimSpace(command.Name) != parts[0] {
			continue
		}
		for _, operation := range command.Operations {
			if strings.TrimSpace(operation.Name) == parts[1] {
				return operation.InputSchema
			}
		}
	}
	return nil
}

// validationCoverageTargets returns required package validation targets.
func validationCoverageTargets(tools schema.Tools) []CoverageItem {
	items := []CoverageItem{}
	for _, command := range tools.LocalExec.Commands {
		commandName := strings.TrimSpace(command.Name)
		for _, operation := range command.Operations {
			operationName := strings.TrimSpace(operation.Name)
			if commandName == "" || operationName == "" {
				continue
			}
			id := commandName + "." + operationName
			items = append(items, CoverageItem{
				Type:  "command-operation",
				ID:    id,
				Label: firstNonEmpty(operation.Description, id),
			})
			items = append(items, CoverageItem{
				Type:  "agent-tool-call",
				ID:    "command:" + id,
				Label: "Agent can select " + id,
			})
			items = append(items, CoverageItem{
				Type:  "workflow-node",
				ID:    "command:" + id,
				Label: "Workflow can invoke " + id,
			})
		}
	}
	for _, preset := range tools.NodePresets {
		id := strings.TrimSpace(preset.ID)
		if id == "" {
			continue
		}
		items = append(items, CoverageItem{
			Type:  "workflow-node",
			ID:    id,
			Label: firstNonEmpty(preset.Label, preset.Description, id),
		})
	}
	for _, server := range tools.MCP.Servers {
		serverName := strings.TrimSpace(server.Name)
		for _, tool := range server.Tools.Allow {
			toolName := strings.TrimSpace(tool)
			if serverName == "" || toolName == "" {
				continue
			}
			id := serverName + "." + toolName
			items = append(items, CoverageItem{Type: "mcp-tool", ID: id, Label: id})
			items = append(items, CoverageItem{
				Type:  "agent-tool-call",
				ID:    "mcp:" + id,
				Label: "Agent can select " + id,
			})
			items = append(items, CoverageItem{
				Type:  "workflow-node",
				ID:    "mcp:" + id,
				Label: "Workflow can invoke " + id,
			})
		}
	}
	return items
}

// validationCoveredTargets returns validation targets declared by the package.
func validationCoveredTargets(validations []schema.ToolValidation) map[string]bool {
	covered := map[string]bool{}
	for _, validation := range validations {
		if !validationHasConfiguredAssertion(validation) {
			continue
		}
		target := validation.Target
		switch strings.TrimSpace(target.Type) {
		case "command-operation":
			command := strings.TrimSpace(target.Command)
			operation := strings.TrimSpace(target.Operation)
			if command != "" && operation != "" {
				covered[coverageKey("command-operation", command+"."+operation)] = true
			}
		case "workflow-node":
			command := strings.TrimSpace(target.Command)
			operation := strings.TrimSpace(target.Operation)
			if command != "" && operation != "" {
				covered[coverageKey("workflow-node", "command:"+command+"."+operation)] = true
				continue
			}
			server := strings.TrimSpace(target.MCPServer)
			tool := strings.TrimSpace(target.MCPTool)
			if server != "" && tool != "" {
				covered[coverageKey("workflow-node", "mcp:"+server+"."+tool)] = true
				continue
			}
			if id := strings.TrimSpace(target.PresetID); id != "" {
				covered[coverageKey("workflow-node", id)] = true
			}
		case "mcp-tool":
			server := strings.TrimSpace(target.MCPServer)
			tool := strings.TrimSpace(target.MCPTool)
			if server != "" && tool != "" {
				covered[coverageKey("mcp-tool", server+"."+tool)] = true
			}
		case "agent-tool-call":
			command := strings.TrimSpace(target.Command)
			operation := strings.TrimSpace(target.Operation)
			if command != "" && operation != "" {
				covered[coverageKey("agent-tool-call", "command:"+command+"."+operation)] = true
				continue
			}
			server := strings.TrimSpace(target.MCPServer)
			tool := strings.TrimSpace(target.MCPTool)
			if server != "" && tool != "" {
				covered[coverageKey("agent-tool-call", "mcp:"+server+"."+tool)] = true
			}
		}
	}
	return covered
}

// validationHasConfiguredAssertion reports whether a validation can prove behavior.
func validationHasConfiguredAssertion(validation schema.ToolValidation) bool {
	for key, value := range validation.Expected {
		switch strings.TrimSpace(key) {
		case "status":
			if strings.TrimSpace(fmt.Sprint(value)) != "" {
				return true
			}
		case "exit_code":
			if value != nil {
				return true
			}
		}
	}
	for _, assertion := range validation.Assertions {
		switch strings.TrimSpace(assertion.Type) {
		case "status":
			if assertion.Equals != nil && strings.TrimSpace(fmt.Sprint(assertion.Equals)) != "" {
				return true
			}
		case "exit-code":
			if assertion.Equals != nil {
				return true
			}
		case "stdout-contains", "stderr-contains":
			if strings.TrimSpace(assertion.Contains) != "" {
				return true
			}
		case "json-path":
			if strings.TrimSpace(assertion.Path) != "" &&
				(strings.TrimSpace(assertion.Contains) != "" ||
					strings.TrimSpace(assertion.Matches) != "" ||
					assertion.Equals != nil) {
				return true
			}
		case "schema":
			if len(assertion.Schema) > 0 {
				return true
			}
		}
	}
	return false
}

// coverageKey returns a stable map key for one coverage target.
func coverageKey(itemType string, id string) string {
	return strings.TrimSpace(itemType) + ":" + strings.TrimSpace(id)
}

// Run executes one validation declared by a tool package.
func (r *Runner) Run(ctx context.Context, tools schema.Tools, validation schema.ToolValidation) Result {
	mode := validationMode(validation.Mode)
	result := Result{
		ID:          strings.TrimSpace(validation.ID),
		Label:       strings.TrimSpace(validation.Label),
		Description: strings.TrimSpace(validation.Description),
		Mode:        mode,
		Status:      StatusFailed,
		Target:      targetResult(tools, validation.Target),
	}
	var ok bool
	result, ok = validateValidationInputSchema(tools, validation, result)
	if !ok {
		return result
	}
	switch result.Target.Type {
	case "command-operation":
		return r.runCommandOperation(ctx, validation, result)
	case "workflow-node":
		if mode == "mocked" {
			return runMockedBoundary(validation, result)
		}
		return r.runWorkflowNode(ctx, tools, validation, result)
	case "mcp-tool":
		if mode == "mocked" {
			return runMockedBoundary(validation, result)
		}
		return r.runMCPTool(ctx, validation, result)
	case "agent-tool-call":
		if mode == "mocked" {
			return runMockedBoundary(validation, result)
		}
		return r.runAgentToolCall(ctx, validation, result)
	default:
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  fmt.Sprintf("unsupported validation target %q", result.Target.Type),
		})
		return result
	}
}

// addResult appends a validation result and updates suite counters.
func addResult(result *SuiteResult, item Result) {
	result.Total++
	result.Results = append(result.Results, item)
	switch item.Status {
	case StatusPassed:
		result.Passed++
	case StatusUnsupported:
		result.Unsupported++
	default:
		result.Failed++
	}
}

// validationActionHost exposes command execution to live workflow validations.
type validationActionHost struct {
	commands CommandExecutor
	mcp      MCPExecutor
}

// RequestHuman rejects human actions in portable tool validations.
func (h validationActionHost) RequestHuman(context.Context, actions.HumanRequest) (string, error) {
	return "", fmt.Errorf("human.request is not supported in tool validations")
}

// CallTool rejects generic context-tool calls in portable tool validations.
func (h validationActionHost) CallTool(context.Context, actions.ToolRequest) (map[string]any, error) {
	return nil, fmt.Errorf("tool.call is not supported in tool validations")
}

// CallMCP delegates mcp.call to the configured MCP boundary.
func (h validationActionHost) CallMCP(ctx context.Context, req actions.MCPRequest) (map[string]any, error) {
	if h.mcp == nil {
		return nil, fmt.Errorf("mcp.call host is not configured")
	}
	return h.mcp.CallMCP(ctx, req)
}

// ExecuteCommand delegates command.execute to the configured command boundary.
func (h validationActionHost) ExecuteCommand(ctx context.Context, req actions.CommandRequest) (map[string]any, error) {
	if h.commands == nil {
		return nil, fmt.Errorf("command.execute host is not configured")
	}
	status, err := h.commands.Execute(ctx, command.ExecuteRequest{
		TemplateID: strings.TrimSpace(req.TemplateID),
		Parameters: req.Parameters,
		WorkingDir: strings.TrimSpace(req.WorkingDir),
		Reason:     strings.TrimSpace(req.Reason),
		Actor:      strings.TrimSpace(req.Actor),
		SessionID:  strings.TrimSpace(req.SessionID),
	})
	return commandStatusMap(status), err
}

// GenerateLLM rejects model actions in portable tool validations.
func (h validationActionHost) GenerateLLM(context.Context, actions.LLMRequest) (map[string]any, error) {
	return nil, fmt.Errorf("llm.generate is not supported in tool validations")
}

// SignalWorkflow rejects nested workflow signals in portable tool validations.
func (h validationActionHost) SignalWorkflow(context.Context, actions.WorkflowSignal) error {
	return fmt.Errorf("workflow.signal is not supported in tool validations")
}

// StartNestedWorkflow rejects nested workflow starts in portable tool validations.
func (h validationActionHost) StartNestedWorkflow(context.Context, actions.NestedWorkflowRequest) (map[string]any, error) {
	return nil, fmt.Errorf("workflow.run is not supported in tool validations")
}

// runCommandOperation executes or mocks one deterministic command operation.
func (r *Runner) runCommandOperation(ctx context.Context, validation schema.ToolValidation, result Result) Result {
	if result.Mode == "mocked" {
		return runMockedBoundary(validation, result)
	}
	if r.commands == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  "live command-operation validation needs a command executor",
		})
		return result
	}
	workingDir, cleanup, err := prepareFixtureWorkspace(validation)
	if cleanup != nil {
		defer cleanup()
	}
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
		result.Status = StatusFailed
		return result
	}
	if cwd := stringFromAny(validation.Input["cwd"]); cwd != "" {
		workingDir = cwd
	}
	status, err := r.commands.Execute(ctx, command.ExecuteRequest{
		TemplateID: result.Target.TemplateID,
		Parameters: validation.Input,
		WorkingDir: workingDir,
		Reason:     "tool validation " + result.ID,
		Actor:      "tool-validation",
	})
	result.Command = &status
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
	}
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// runMCPTool executes one live MCP boundary validation.
func (r *Runner) runMCPTool(ctx context.Context, validation schema.ToolValidation, result Result) Result {
	if r.mcp == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  "live mcp-tool validation needs an MCP executor",
		})
		return result
	}
	output, err := r.mcp.CallMCP(ctx, actions.MCPRequest{
		ServerID:  result.Target.MCPServer,
		Tool:      result.Target.MCPTool,
		Arguments: cloneMap(validation.Input),
	})
	status := mcpStatusFromOutput(result.ID, output)
	result.Command = &status
	if err != nil {
		status.Status = "failed"
		status.ExitCode = 1
		status.Error = err.Error()
		result.Command = &status
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
	}
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// runAgentToolCall executes one live direct-agent-call validation.
func (r *Runner) runAgentToolCall(ctx context.Context, validation schema.ToolValidation, result Result) Result {
	if r.agentHost == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "warning",
			Message:  "live agent-tool-call validation needs an agent runtime host",
		})
		return result
	}
	response, err := r.agentHost.Respond(ctx, agentvalidation.Request{
		Agent: toolValidationAgent(r.agent),
		Validation: schema.AgentValidation{
			ID:       strings.TrimSpace(validation.ID),
			Prompt:   strings.TrimSpace(validation.Prompt),
			Input:    cloneMap(validation.Input),
			Fixtures: cloneMap(validation.Fixtures),
		},
		Prompt:   strings.TrimSpace(validation.Prompt),
		Input:    cloneMap(validation.Input),
		Fixtures: cloneMap(validation.Fixtures),
	})
	status := agentToolCallStatus(validation.ID, response)
	result.Command = &status
	if err != nil {
		status.Status = "failed"
		status.Error = err.Error()
		result.Command = &status
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
	}
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// toolValidationAgent supplies a focused default agent when no package agent is provided.
func toolValidationAgent(agent schema.Agent) schema.Agent {
	if strings.TrimSpace(agent.Name) != "" || strings.TrimSpace(agent.Instruction) != "" {
		return agent
	}
	return schema.Agent{
		Name: "tool-validation-agent",
		Instruction: strings.TrimSpace(`You are validating a configured Agent Awesome tool package.
Use the available tool when the user request calls for it. Prefer a tool call over prose when a configured tool can satisfy the request.`),
	}
}

// runWorkflowNode executes one live workflow node preset through action metadata.
func (r *Runner) runWorkflowNode(ctx context.Context, tools schema.Tools, validation schema.ToolValidation, result Result) Result {
	if result.Target.Command != "" || result.Target.Operation != "" {
		return r.runWorkflowCommandOperation(ctx, validation, result)
	}
	if result.Target.MCPServer != "" || result.Target.MCPTool != "" {
		return r.runWorkflowMCPTool(ctx, validation, result, map[string]any{
			"server_id": result.Target.MCPServer,
			"tool":      result.Target.MCPTool,
			"arguments": cloneMap(validation.Input),
		})
	}
	preset, ok := findNodePreset(tools.NodePresets, result.Target.PresetID)
	if !ok {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  fmt.Sprintf("workflow node preset %q was not found", result.Target.PresetID),
		})
		result.Status = StatusFailed
		return result
	}
	if strings.TrimSpace(preset.Action) == "mcp.call" {
		arguments := cloneMap(preset.Arguments)
		return r.runWorkflowMCPTool(ctx, validation, result, arguments)
	}
	if strings.TrimSpace(preset.Action) != "command.execute" {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "warning",
			Message:  fmt.Sprintf("live workflow-node validations for %s are not supported yet", preset.Action),
		})
		return result
	}
	if r.commands == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  "live workflow-node validation needs a command executor",
		})
		return result
	}
	workingDir, cleanup, err := prepareFixtureWorkspace(validation)
	if cleanup != nil {
		defer cleanup()
	}
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
		result.Status = StatusFailed
		return result
	}
	arguments := cloneMap(preset.Arguments)
	if workingDir != "" && stringFromAny(arguments["cwd"]) == "" {
		arguments["cwd"] = workingDir
	}
	output, err := actions.NewRegistry().Execute(ctx, preset.Action, actions.Context{
		RunID:  "tool-validation",
		StepID: result.ID,
		Input:  cloneMap(validation.Input),
		Host:   validationActionHost{commands: r.commands, mcp: r.mcp},
	}, arguments)
	status := commandStatusFromMap(output)
	result.Command = &status
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
	}
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// runWorkflowCommandOperation executes a command operation through workflow actions.
func (r *Runner) runWorkflowCommandOperation(ctx context.Context, validation schema.ToolValidation, result Result) Result {
	if r.commands == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  "live workflow-node validation needs a command executor",
		})
		return result
	}
	workingDir, cleanup, err := prepareFixtureWorkspace(validation)
	if cleanup != nil {
		defer cleanup()
	}
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
		result.Status = StatusFailed
		return result
	}
	if cwd := stringFromAny(validation.Input["cwd"]); cwd != "" {
		workingDir = cwd
	}
	arguments := map[string]any{
		"template_id": result.Target.TemplateID,
		"parameters":  cloneMap(validation.Input),
	}
	if workingDir != "" {
		arguments["cwd"] = workingDir
	}
	output, err := actions.NewRegistry().Execute(ctx, "command.execute", actions.Context{
		RunID:  "tool-validation",
		StepID: result.ID,
		Input:  cloneMap(validation.Input),
		Host:   validationActionHost{commands: r.commands, mcp: r.mcp},
	}, arguments)
	status := commandStatusFromMap(output)
	result.Command = &status
	if err != nil {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
	}
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// runWorkflowMCPTool executes an MCP-backed workflow node through mcp.call.
func (r *Runner) runWorkflowMCPTool(
	ctx context.Context,
	validation schema.ToolValidation,
	result Result,
	arguments map[string]any,
) Result {
	if r.mcp == nil {
		result.Status = StatusUnsupported
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  "live workflow-node validation needs an MCP executor",
		})
		return result
	}
	output, err := actions.NewRegistry().Execute(ctx, "mcp.call", actions.Context{
		RunID:  "tool-validation",
		StepID: result.ID,
		Input:  cloneMap(validation.Input),
		Host:   validationActionHost{commands: r.commands, mcp: r.mcp},
	}, arguments)
	status := mcpStatusFromOutput(result.ID, output)
	result.Command = &status
	if err != nil {
		status.Status = "failed"
		status.ExitCode = 1
		status.Error = err.Error()
		result.Command = &status
		result.Diagnostics = append(result.Diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
	}
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// prepareFixtureWorkspace writes declared validation files into a temp cwd.
func prepareFixtureWorkspace(validation schema.ToolValidation) (string, func(), error) {
	files, err := validationFixtureFiles(validation.Fixtures["files"])
	if err != nil || len(files) == 0 {
		return "", nil, err
	}
	dir, err := os.MkdirTemp("", "agent-awesome-tool-validation-*")
	if err != nil {
		return "", nil, fmt.Errorf("create validation fixture workspace: %w", err)
	}
	cleanup := func() {
		_ = os.RemoveAll(dir)
	}
	for _, file := range files {
		path, err := fixtureFilePath(dir, file.Path)
		if err != nil {
			cleanup()
			return "", nil, err
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			cleanup()
			return "", nil, fmt.Errorf("create fixture directory: %w", err)
		}
		if err := os.WriteFile(path, []byte(file.Content), 0o600); err != nil {
			cleanup()
			return "", nil, fmt.Errorf("write fixture %q: %w", file.Path, err)
		}
	}
	return dir, cleanup, nil
}

// validationFixtureFile stores one filesystem fixture file.
type validationFixtureFile struct {
	Path    string
	Content string
}

// validationFixtureFiles converts generic YAML fixture maps into file fixtures.
func validationFixtureFiles(value any) ([]validationFixtureFile, error) {
	items, ok := value.([]any)
	if !ok || len(items) == 0 {
		return nil, nil
	}
	files := make([]validationFixtureFile, 0, len(items))
	for index, item := range items {
		fields, ok := item.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("fixture file %d must be an object", index+1)
		}
		path := stringFromAny(fields["path"])
		if path == "" {
			return nil, fmt.Errorf("fixture file %d path must not be empty", index+1)
		}
		content, err := fixtureContent(fields["content"])
		if err != nil {
			return nil, fmt.Errorf("fixture file %q content: %w", path, err)
		}
		files = append(files, validationFixtureFile{Path: path, Content: content})
	}
	return files, nil
}

// fixtureContent returns a stable string representation for fixture content.
func fixtureContent(value any) (string, error) {
	if value == nil {
		return "", nil
	}
	if text, ok := value.(string); ok {
		return text, nil
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	return string(encoded), nil
}

// fixtureFilePath resolves a fixture path safely inside the workspace.
func fixtureFilePath(root string, path string) (string, error) {
	cleanPath := filepath.Clean(strings.TrimSpace(path))
	if cleanPath == "." || filepath.IsAbs(cleanPath) {
		return "", fmt.Errorf("fixture path %q must be relative", path)
	}
	target := filepath.Join(root, cleanPath)
	rel, err := filepath.Rel(root, target)
	if err != nil {
		return "", fmt.Errorf("resolve fixture path %q: %w", path, err)
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("fixture path %q escapes the workspace", path)
	}
	return target, nil
}

// runMockedBoundary evaluates one validation using a mocked boundary response.
func runMockedBoundary(validation schema.ToolValidation, result Result) Result {
	mock, ok := mapValue(validation.Mocks, result.Target.Boundary)
	if !ok {
		result.Diagnostics = append(result.Diagnostics, Diagnostic{
			Severity: "error",
			Message:  fmt.Sprintf("mocked validation needs %q response", result.Target.Boundary),
		})
		result.Status = StatusFailed
		return result
	}
	status := mockedCommandStatus(validation.ID, mock)
	result.Command = &status
	result.Assertions = evaluateAssertions(validation, result, status)
	result.Status = assertionStatus(result.Assertions, result.Diagnostics)
	return result
}

// validateValidationInputSchema checks command-bound validation parameters.
func validateValidationInputSchema(tools schema.Tools, validation schema.ToolValidation, result Result) (Result, bool) {
	parameters, inputSchema, ok := validationInputContract(tools, validation, result.Target)
	if !ok || len(inputSchema) == 0 {
		return result, true
	}
	checked := command.ValidateOutput(parameters, inputSchema)
	if checked.Valid {
		return result, true
	}
	result.Assertions = append(result.Assertions, AssertionResult{
		Type:     "input-schema",
		Path:     "input",
		Passed:   false,
		Expected: inputSchema,
		Actual:   parameters,
		Message:  "validation input does not match command input schema: " + strings.Join(checked.Errors, "; "),
	})
	result.Status = StatusFailed
	return result, false
}

// validationInputContract returns the command parameters and schema for a case.
func validationInputContract(
	tools schema.Tools,
	validation schema.ToolValidation,
	target TargetResult,
) (map[string]any, map[string]any, bool) {
	switch target.Type {
	case "command-operation":
		return cloneMap(validation.Input), inputSchemaForOperation(tools, target.TemplateID), true
	case "workflow-node":
		if target.TemplateID != "" {
			return cloneMap(validation.Input), inputSchemaForOperation(tools, target.TemplateID), true
		}
		preset, ok := findNodePreset(tools.NodePresets, target.PresetID)
		if !ok || strings.TrimSpace(preset.Action) != "command.execute" {
			return nil, nil, false
		}
		templateID := stringFromAny(preset.Arguments["template_id"])
		inputSchema := inputSchemaForOperation(tools, templateID)
		if len(inputSchema) == 0 {
			return nil, nil, false
		}
		parameters := resolvedValidationMapArg(preset.Arguments, "parameters", nil, validation.Input)
		if parameters == nil {
			parameters = map[string]any{}
		}
		return parameters, inputSchema, true
	default:
		return nil, nil, false
	}
}

// resolvedValidationMapArg resolves a map argument using validation input.
func resolvedValidationMapArg(args map[string]any, key string, fallback map[string]any, input map[string]any) map[string]any {
	value, ok := args[key]
	if !ok {
		return fallback
	}
	resolved := resolveValidationInputRefs(value, input)
	if resolvedMap, ok := resolved.(map[string]any); ok {
		return resolvedMap
	}
	return fallback
}

// resolveValidationInputRefs applies workflow-style ${path} input references.
func resolveValidationInputRefs(value any, input map[string]any) any {
	switch typed := normalizeValue(value).(type) {
	case string:
		return resolveValidationInputRefString(typed, input)
	case map[string]any:
		next := make(map[string]any, len(typed))
		for key, item := range typed {
			next[key] = resolveValidationInputRefs(item, input)
		}
		return next
	case []any:
		next := make([]any, len(typed))
		for index, item := range typed {
			next[index] = resolveValidationInputRefs(item, input)
		}
		return next
	default:
		return typed
	}
}

// resolveValidationInputRefString resolves whole-string and embedded refs.
func resolveValidationInputRefString(value string, input map[string]any) any {
	trimmed := strings.TrimSpace(value)
	if strings.HasPrefix(trimmed, "${") && strings.HasSuffix(trimmed, "}") && strings.Count(trimmed, "${") == 1 {
		if resolved, ok := jsondata.Dotted(input, strings.TrimSuffix(strings.TrimPrefix(trimmed, "${"), "}")); ok {
			return resolved
		}
		return value
	}
	result := value
	for {
		start := strings.Index(result, "${")
		if start < 0 {
			return result
		}
		end := strings.Index(result[start:], "}")
		if end < 0 {
			return result
		}
		end += start
		resolved, ok := jsondata.Dotted(input, result[start+2:end])
		if !ok {
			return result
		}
		result = result[:start] + fmt.Sprint(resolved) + result[end+1:]
	}
}

// targetResult normalizes validation target metadata for result output.
func targetResult(tools schema.Tools, target schema.ToolValidationTarget) TargetResult {
	result := TargetResult{
		Type:      strings.TrimSpace(target.Type),
		PresetID:  strings.TrimSpace(target.PresetID),
		Command:   strings.TrimSpace(target.Command),
		Operation: strings.TrimSpace(target.Operation),
		MCPServer: strings.TrimSpace(target.MCPServer),
		MCPTool:   strings.TrimSpace(target.MCPTool),
	}
	if result.Type == "command-operation" {
		result.TemplateID = result.Command + "." + result.Operation
		result.Boundary = "command.execute"
	}
	if result.Type == "mcp-tool" {
		result.Boundary = "mcp.call"
	}
	if result.Type == "agent-tool-call" {
		result.Boundary = "agent.tool_call"
	}
	if result.Type == "workflow-node" {
		if result.Command != "" && result.Operation != "" {
			result.TemplateID = result.Command + "." + result.Operation
			result.Boundary = "command.execute"
		} else if result.MCPServer != "" && result.MCPTool != "" {
			result.Boundary = "mcp.call"
		} else {
			result.Boundary = workflowNodeBoundary(tools.NodePresets, result.PresetID)
		}
	}
	return result
}

// findNodePreset returns one node preset by stable id.
func findNodePreset(presets []schema.NodePreset, presetID string) (schema.NodePreset, bool) {
	for _, preset := range presets {
		if strings.TrimSpace(preset.ID) == strings.TrimSpace(presetID) {
			return preset, true
		}
	}
	return schema.NodePreset{}, false
}

// workflowNodeBoundary returns the generic action behind one node preset.
func workflowNodeBoundary(presets []schema.NodePreset, presetID string) string {
	if preset, ok := findNodePreset(presets, presetID); ok {
		return strings.TrimSpace(preset.Action)
	}
	return "workflow.node"
}

// commandStatusMap converts command status to generic workflow action output.
func commandStatusMap(status command.StatusResult) map[string]any {
	encoded, err := json.Marshal(status)
	if err != nil {
		return map[string]any{}
	}
	var out map[string]any
	if err := json.Unmarshal(encoded, &out); err != nil {
		return map[string]any{}
	}
	return out
}

// commandStatusFromMap converts workflow action output back to command status.
func commandStatusFromMap(value map[string]any) command.StatusResult {
	encoded, err := json.Marshal(value)
	if err != nil {
		return command.StatusResult{}
	}
	var status command.StatusResult
	if err := json.Unmarshal(encoded, &status); err != nil {
		return command.StatusResult{}
	}
	return status
}

// mockedCommandStatus converts a mocked boundary response into command status shape.
func mockedCommandStatus(validationID string, mock map[string]any) command.StatusResult {
	status := command.StatusResult{
		JobID:      "mock:" + strings.TrimSpace(validationID),
		Status:     stringField(mock, "status"),
		ExitCode:   intField(mock, "exit_code", 0),
		StdoutTail: stringField(mock, "stdout"),
		StderrTail: stringField(mock, "stderr"),
		Output:     mock["output"],
		Validation: command.ValidationResult{Valid: true},
	}
	if status.Status == "" {
		status.Status = "succeeded"
	}
	if status.Output == nil {
		status.Output = map[string]any{"text": status.StdoutTail}
	}
	return status
}

// mcpStatusFromOutput converts an MCP tool response into validation evidence.
func mcpStatusFromOutput(validationID string, output map[string]any) command.StatusResult {
	return command.StatusResult{
		JobID:      "mcp:" + strings.TrimSpace(validationID),
		Status:     "succeeded",
		ExitCode:   0,
		StdoutTail: stringFromAny(output["text"]),
		Output:     cloneMap(output),
		Validation: command.ValidationResult{Valid: true},
	}
}

// agentToolCallStatus converts a live agent response into generic validation evidence.
func agentToolCallStatus(validationID string, response agentvalidation.Response) command.StatusResult {
	output := map[string]any{
		"text":       strings.TrimSpace(response.Text),
		"tool_calls": agentToolCallMaps(response.ToolCalls),
	}
	if response.Output != nil {
		output["output"] = response.Output
	}
	return command.StatusResult{
		JobID:      "agent:" + strings.TrimSpace(validationID),
		Status:     "succeeded",
		ExitCode:   0,
		StdoutTail: strings.TrimSpace(response.Text),
		Output:     output,
		Validation: command.ValidationResult{Valid: true},
	}
}

// agentToolCallMaps converts observed agent tool calls into assertion-friendly maps.
func agentToolCallMaps(calls []agentvalidation.ToolCall) []any {
	out := make([]any, 0, len(calls))
	for _, call := range calls {
		out = append(out, map[string]any{
			"id":        strings.TrimSpace(call.ID),
			"name":      strings.TrimSpace(call.Name),
			"arguments": cloneMap(call.Arguments),
		})
	}
	return out
}

// evaluateAssertions checks expected metadata and explicit assertions.
func evaluateAssertions(validation schema.ToolValidation, result Result, status command.StatusResult) []AssertionResult {
	assertions := make([]AssertionResult, 0, len(validation.Assertions)+2)
	if expected, ok := validation.Expected["status"]; ok {
		assertions = append(assertions, compareAssertion("status", "", expected, status.Status, "status matches expected result"))
	}
	if expected, ok := validation.Expected["exit_code"]; ok {
		assertions = append(assertions, compareAssertion("exit-code", "", expected, status.ExitCode, "exit code matches expected result"))
	}
	for _, assertion := range validation.Assertions {
		assertions = append(assertions, evaluateAssertion(assertion, result, status))
	}
	if len(assertions) == 0 {
		assertions = append(assertions, AssertionResult{Type: "configured", Passed: true})
	}
	return assertions
}

// evaluateAssertion checks one explicit assertion record.
func evaluateAssertion(assertion schema.ValidationAssertion, result Result, status command.StatusResult) AssertionResult {
	assertionType := strings.TrimSpace(assertion.Type)
	switch assertionType {
	case "status":
		return compareAssertion(assertionType, assertion.Path, assertion.Equals, status.Status, assertion.Message)
	case "exit-code":
		return compareAssertion(assertionType, assertion.Path, assertion.Equals, status.ExitCode, assertion.Message)
	case "stdout-contains":
		return containsAssertion(assertionType, assertion.Path, assertion.Contains, status.StdoutTail, assertion.Message)
	case "stderr-contains":
		return containsAssertion(assertionType, assertion.Path, assertion.Contains, status.StderrTail, assertion.Message)
	case "json-path":
		actual := pathValue(resultMap(result, status), assertion.Path)
		if assertion.Contains != "" {
			return containsAssertion(assertionType, assertion.Path, assertion.Contains, fmt.Sprint(actual), assertion.Message)
		}
		if assertion.Matches != "" {
			return matchesAssertion(assertionType, assertion.Path, assertion.Matches, fmt.Sprint(actual), assertion.Message)
		}
		return compareAssertion(assertionType, assertion.Path, assertion.Equals, actual, assertion.Message)
	case "schema":
		actual := pathValue(resultMap(result, status), assertion.Path)
		validation := command.ValidateOutput(actual, assertion.Schema)
		return AssertionResult{
			Type:    assertionType,
			Path:    assertion.Path,
			Passed:  validation.Valid,
			Message: strings.Join(validation.Errors, "; "),
		}
	default:
		return AssertionResult{
			Type:    assertionType,
			Path:    assertion.Path,
			Passed:  false,
			Message: "unsupported assertion type",
		}
	}
}

// compareAssertion checks exact value equality through display-stable values.
func compareAssertion(assertionType string, path string, expected any, actual any, message string) AssertionResult {
	passed := fmt.Sprint(expected) == fmt.Sprint(actual)
	return AssertionResult{
		Type:     assertionType,
		Path:     path,
		Passed:   passed,
		Expected: expected,
		Actual:   actual,
		Message:  assertionMessage(passed, message, fmt.Sprintf("expected %v, got %v", expected, actual)),
	}
}

// containsAssertion checks that actual text contains expected text.
func containsAssertion(assertionType string, path string, expected string, actual string, message string) AssertionResult {
	passed := expected != "" && strings.Contains(actual, expected)
	return AssertionResult{
		Type:     assertionType,
		Path:     path,
		Passed:   passed,
		Expected: expected,
		Actual:   actual,
		Message:  assertionMessage(passed, message, fmt.Sprintf("expected %q to contain %q", actual, expected)),
	}
}

// matchesAssertion checks actual text against a regular expression.
func matchesAssertion(assertionType string, path string, pattern string, actual string, message string) AssertionResult {
	matched, err := regexp.MatchString(pattern, actual)
	passed := pattern != "" && err == nil && matched
	if err != nil {
		message = err.Error()
	}
	return AssertionResult{
		Type:     assertionType,
		Path:     path,
		Passed:   passed,
		Expected: pattern,
		Actual:   actual,
		Message:  assertionMessage(passed, message, fmt.Sprintf("expected %q to match %q", actual, pattern)),
	}
}

// assertionMessage returns an empty message when an assertion passed.
func assertionMessage(passed bool, configured string, fallback string) string {
	if passed {
		return ""
	}
	if strings.TrimSpace(configured) != "" {
		return strings.TrimSpace(configured)
	}
	return fallback
}

// assertionStatus computes a result status from assertions and diagnostics.
func assertionStatus(assertions []AssertionResult, diagnostics []Diagnostic) string {
	for _, diagnostic := range diagnostics {
		if strings.EqualFold(diagnostic.Severity, "error") {
			return StatusFailed
		}
	}
	for _, assertion := range assertions {
		if !assertion.Passed {
			return StatusFailed
		}
	}
	return StatusPassed
}

// firstNonEmpty returns the first non-empty trimmed value.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

// resultMap builds a generic result object for path assertions.
func resultMap(result Result, status command.StatusResult) map[string]any {
	return map[string]any{
		"id":      result.ID,
		"mode":    result.Mode,
		"target":  result.Target,
		"command": status,
		"output":  status.Output,
		"stdout":  status.StdoutTail,
		"stderr":  status.StderrTail,
		"status":  status.Status,
	}
}

// pathValue resolves simple dot-separated paths from maps and known structs.
func pathValue(value any, path string) any {
	trimmed := strings.Trim(strings.TrimSpace(path), "$.")
	if trimmed == "" {
		return value
	}
	current := value
	for _, part := range strings.Split(trimmed, ".") {
		switch typed := current.(type) {
		case map[string]any:
			current = typed[part]
		case []any:
			index, err := strconv.Atoi(part)
			if err != nil || index < 0 || index >= len(typed) {
				return nil
			}
			current = typed[index]
		case command.StatusResult:
			current = commandStatusField(typed, part)
		case TargetResult:
			current = targetResultField(typed, part)
		default:
			return nil
		}
	}
	return current
}

// commandStatusField returns one command status field by JSON-style name.
func commandStatusField(status command.StatusResult, name string) any {
	switch name {
	case "status":
		return status.Status
	case "exit_code":
		return status.ExitCode
	case "stdout_tail", "stdout":
		return status.StdoutTail
	case "stderr_tail", "stderr":
		return status.StderrTail
	case "output":
		return status.Output
	default:
		return nil
	}
}

// targetResultField returns one target field by JSON-style name.
func targetResultField(target TargetResult, name string) any {
	switch name {
	case "type":
		return target.Type
	case "preset_id":
		return target.PresetID
	case "command":
		return target.Command
	case "operation":
		return target.Operation
	case "mcp_server":
		return target.MCPServer
	case "mcp_tool":
		return target.MCPTool
	case "template_id":
		return target.TemplateID
	case "boundary":
		return target.Boundary
	default:
		return nil
	}
}

// validationMode normalizes empty validation modes to mocked.
func validationMode(value string) string {
	if strings.TrimSpace(value) == "live" {
		return "live"
	}
	return "mocked"
}

// selectedValidationMode normalizes optional validation mode filters.
func selectedValidationMode(value string) string {
	switch strings.TrimSpace(value) {
	case "mocked":
		return "mocked"
	case "live":
		return "live"
	default:
		return ""
	}
}

// validationMatchesMode reports whether a validation should run for a filter.
func validationMatchesMode(value string, mode string) bool {
	filter := selectedValidationMode(mode)
	return filter == "" || validationMode(value) == filter
}

// filterToolValidationsByMode returns validations visible to one mode lane.
func filterToolValidationsByMode(validations []schema.ToolValidation, mode string) []schema.ToolValidation {
	filter := selectedValidationMode(mode)
	if filter == "" {
		return validations
	}
	out := make([]schema.ToolValidation, 0, len(validations))
	for _, validation := range validations {
		if validationMatchesMode(validation.Mode, filter) {
			out = append(out, validation)
		}
	}
	return out
}

// selectedValidationIDs normalizes requested validation IDs while preserving order.
func selectedValidationIDs(values []string) []string {
	ids := make([]string, 0, len(values))
	seen := map[string]bool{}
	for _, value := range values {
		id := strings.TrimSpace(value)
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		ids = append(ids, id)
	}
	return ids
}

// cloneMap returns a normalized deep copy of generic arguments.
func cloneMap(values map[string]any) map[string]any {
	if len(values) == 0 {
		return map[string]any{}
	}
	out := make(map[string]any, len(values))
	for key, value := range values {
		out[key] = normalizeValue(value)
	}
	return out
}

// normalizeValue converts decoded YAML maps into JSON-like maps for references.
func normalizeValue(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		return cloneMap(typed)
	case map[any]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[fmt.Sprint(key)] = normalizeValue(item)
		}
		return out
	case map[string]string:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[key] = item
		}
		return out
	case []any:
		out := make([]any, len(typed))
		for index, item := range typed {
			out[index] = normalizeValue(item)
		}
		return out
	default:
		return value
	}
}

// mapValue returns a nested map field.
func mapValue(values map[string]any, key string) (map[string]any, bool) {
	value, ok := values[key]
	if !ok {
		return nil, false
	}
	switch typed := value.(type) {
	case map[string]any:
		return typed, true
	default:
		return nil, false
	}
}

// stringField returns a string field from a map.
func stringField(values map[string]any, key string) string {
	value, _ := values[key].(string)
	return strings.TrimSpace(value)
}

// stringFromAny returns a trimmed string from a generic map value.
func stringFromAny(value any) string {
	text, _ := value.(string)
	return strings.TrimSpace(text)
}

// intField returns an integer field from decoded metadata.
func intField(values map[string]any, key string, fallback int) int {
	switch value := values[key].(type) {
	case int:
		return value
	case int64:
		return int(value)
	case float64:
		return int(value)
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(value))
		if err == nil {
			return parsed
		}
	}
	return fallback
}
