// This file implements the in-memory Capability Registry.
package capabilities

import (
	"fmt"
	"sort"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/definition"
)

// Registry stores normalized capabilities by stable id.
type Registry struct {
	records []Capability
	byID    map[string]Capability
}

// NewRegistry builds a normalized registry from harness configuration.
func NewRegistry(tools *schema.Tools, agentCfg schema.Agent) *Registry {
	builder := &registryBuilder{byID: map[string]Capability{}}
	builder.addWorkflowActions()
	builder.addAgent(agentCfg)
	builder.addTools(tools)
	return builder.registry()
}

// List returns capabilities matching a query.
func (r *Registry) List(query Query) []Capability {
	if r == nil {
		return nil
	}
	kind := strings.TrimSpace(query.Kind)
	out := make([]Capability, 0, len(r.records))
	for _, record := range r.records {
		if kind != "" && string(record.Kind) != kind {
			continue
		}
		if query.UsableInChat != nil && record.UsableInChat != *query.UsableInChat {
			continue
		}
		if query.UsableInWorkflows != nil && record.UsableInWorkflows != *query.UsableInWorkflows {
			continue
		}
		out = append(out, record)
	}
	return out
}

// Get returns one capability by id.
func (r *Registry) Get(id string) (Capability, bool) {
	if r == nil {
		return Capability{}, false
	}
	record, ok := r.byID[strings.TrimSpace(id)]
	return record, ok
}

// ValidateDefinition reports unavailable capabilities required by a workflow.
func (r *Registry) ValidateDefinition(def definition.Definition) []Diagnostic {
	if r == nil {
		return nil
	}
	diagnostics := []Diagnostic{}
	for _, node := range allNodes(def) {
		action := definition.NodeAction(node)
		if action == "" {
			continue
		}
		path := "nodes." + strings.TrimSpace(node.ID)
		diagnostics = append(diagnostics, r.validateRequiredCapability(
			workflowActionID(action),
			path,
			"workflow action "+action,
		)...)
		args := nodeArguments(node)
		switch action {
		case "command.execute":
			diagnostics = append(diagnostics, r.validateCommandNode(args, path)...)
		case "mcp.call":
			diagnostics = append(diagnostics, r.validateMCPNode(args, path)...)
		case "tool.call":
			diagnostics = append(diagnostics, r.validateToolNode(args, path)...)
		}
	}
	return dedupeDiagnostics(diagnostics)
}

// registryBuilder accumulates normalized records.
type registryBuilder struct {
	records []Capability
	byID    map[string]Capability
}

// addWorkflowActions records built-in workflow action capabilities.
func (b *registryBuilder) addWorkflowActions() {
	registry := actions.NewRegistry()
	for _, name := range registry.Names() {
		meta := actions.MetadataFor(name)
		status := AvailabilityAvailable
		reasons := []string{}
		if !meta.Available {
			status = AvailabilityUnavailable
			reasons = append(reasons, "workflow action is not publishable yet")
		}
		b.add(Capability{
			ID:                workflowActionID(name),
			Kind:              KindWorkflowAction,
			Name:              name,
			Label:             meta.Label,
			Description:       meta.Description,
			UsableInWorkflows: meta.Available,
			Invocation:        CapabilityInvocation{WorkflowAction: name},
			Contract: CapabilityContract{
				InputSchema:  cloneMap(meta.InputSchema),
				OutputSchema: cloneMap(meta.OutputSchema),
			},
			Risk:         CapabilityRisk{Level: meta.Risk},
			Availability: CapabilityAvailability{Status: status, Reasons: reasons},
		})
	}
}

// addAgent records the configured default agent profile.
func (b *registryBuilder) addAgent(agentCfg schema.Agent) {
	name := strings.TrimSpace(agentCfg.Name)
	if name == "" {
		name = "Agent Awesome"
	}
	status := AvailabilityAvailable
	reasons := []string{}
	if strings.TrimSpace(agentCfg.Instruction) == "" {
		status = AvailabilityNeedsCheck
		reasons = append(reasons, "agent instructions are empty")
	}
	b.add(Capability{
		ID:                "agent_profile:default",
		Kind:              KindAgentProfile,
		Name:              "default",
		Label:             name,
		Description:       strings.TrimSpace(agentCfg.Description),
		UsableInChat:      true,
		UsableInWorkflows: true,
		Invocation:        CapabilityInvocation{AgentProfileID: "default"},
		Risk:              CapabilityRisk{Level: "agent"},
		Availability:      CapabilityAvailability{Status: status, Reasons: reasons},
	})
}

// addTools records configured command, MCP, preset, and validation capabilities.
func (b *registryBuilder) addTools(tools *schema.Tools) {
	if tools == nil {
		return
	}
	b.addCommands(tools.LocalExec)
	b.addMCP(tools.MCP)
	b.addPresets(tools.NodePresets)
	b.addValidations(tools.Validations)
}

// addCommands records command template capabilities.
func (b *registryBuilder) addCommands(local schema.LocalExec) {
	for _, command := range local.Commands {
		name := strings.TrimSpace(command.Name)
		if name == "" {
			continue
		}
		status := AvailabilityAvailable
		reasons := []string{}
		if !local.Enabled {
			status = AvailabilityUnavailable
			reasons = append(reasons, "local command execution is disabled")
		}
		if strings.TrimSpace(command.Executable) == "" {
			status = AvailabilityUnavailable
			reasons = append(reasons, "command executable is missing")
		}
		if len(command.Operations) > 0 {
			for _, operation := range command.Operations {
				b.addCommandOperation(command, operation, status, reasons)
			}
			continue
		}
		usable := status == AvailabilityAvailable
		b.add(Capability{
			ID:                commandID(name),
			Kind:              KindCommand,
			Name:              name,
			Label:             name,
			Description:       strings.TrimSpace(command.Description),
			UsableInChat:      usable,
			UsableInWorkflows: usable,
			Invocation: CapabilityInvocation{
				DirectToolName:  "command_execute",
				WorkflowAction:  "command.execute",
				CommandTemplate: name,
			},
			Contract: CapabilityContract{ConfirmationRequired: true},
			Risk: CapabilityRisk{
				Level:                "tool",
				RequiresConfirmation: true,
			},
			Availability: CapabilityAvailability{Status: status, Reasons: reasons},
		})
	}
}

// addCommandOperation records one deterministic workflow-callable CLI operation.
func (b *registryBuilder) addCommandOperation(command schema.LocalExecCommand, operation schema.CommandOperation, status AvailabilityStatus, reasons []string) {
	commandName := strings.TrimSpace(command.Name)
	operationName := strings.TrimSpace(operation.Name)
	if commandName == "" || operationName == "" {
		return
	}
	templateID := commandName + "." + operationName
	usable := status == AvailabilityAvailable
	b.add(Capability{
		ID:                commandID(templateID),
		Kind:              KindCommand,
		Name:              templateID,
		Label:             templateID,
		Description:       strings.TrimSpace(operation.Description),
		UsableInChat:      usable,
		UsableInWorkflows: usable,
		Invocation: CapabilityInvocation{
			DirectToolName:  "command_execute",
			WorkflowAction:  "command.execute",
			CommandTemplate: templateID,
		},
		Contract: CapabilityContract{
			InputSchema:          cloneMap(operation.InputSchema),
			OutputSchema:         cloneMap(operation.OutputSchema),
			ConfirmationRequired: true,
		},
		Risk: CapabilityRisk{
			Level:                "tool",
			RequiresConfirmation: true,
		},
		Availability: CapabilityAvailability{
			Status:  status,
			Reasons: append([]string(nil), reasons...),
		},
		Metadata: map[string]any{
			"command":   commandName,
			"operation": operationName,
		},
	})
}

// addMCP records MCP server and explicitly allowed tool capabilities.
func (b *registryBuilder) addMCP(mcp schema.MCP) {
	for _, server := range mcp.Servers {
		name := strings.TrimSpace(server.Name)
		if name == "" {
			continue
		}
		status := AvailabilityAvailable
		reasons := []string{}
		if !mcp.Enabled {
			status = AvailabilityUnavailable
			reasons = append(reasons, "MCP is disabled")
		}
		if !serverHasEndpoint(server) {
			status = AvailabilityUnavailable
			reasons = append(reasons, "server transport is incomplete")
		}
		usable := status == AvailabilityAvailable
		serverRequiresConfirmation := server.RequireConfirmation || len(server.RequireConfirmationTools) > 0
		b.add(Capability{
			ID:                mcpServerID(name),
			Kind:              KindMCPServer,
			Name:              name,
			Label:             name,
			UsableInChat:      usable,
			UsableInWorkflows: usable,
			Invocation:        CapabilityInvocation{MCPServer: name},
			Contract:          CapabilityContract{ConfirmationRequired: serverRequiresConfirmation},
			Risk: CapabilityRisk{
				Level:                "tool",
				RequiresConfirmation: serverRequiresConfirmation,
			},
			Availability: CapabilityAvailability{Status: status, Reasons: reasons},
		})
		for _, tool := range server.Tools.Allow {
			toolName := strings.TrimSpace(tool)
			if toolName == "" {
				continue
			}
			toolStatus := status
			toolReasons := append([]string(nil), reasons...)
			requiresConfirmation := server.RequireConfirmation || contains(server.RequireConfirmationTools, toolName)
			b.add(Capability{
				ID:                mcpToolID(name, toolName),
				Kind:              KindMCPTool,
				Name:              toolName,
				Label:             toolName,
				UsableInChat:      usable,
				UsableInWorkflows: usable,
				Invocation: CapabilityInvocation{
					DirectToolName: toolName,
					WorkflowAction: "mcp.call",
					MCPServer:      name,
					MCPTool:        toolName,
				},
				Contract: CapabilityContract{ConfirmationRequired: requiresConfirmation},
				Risk: CapabilityRisk{
					Level:                "tool",
					RequiresConfirmation: requiresConfirmation,
				},
				Availability: CapabilityAvailability{Status: toolStatus, Reasons: toolReasons},
			})
		}
	}
}

// addPresets records workflow node preset capabilities.
func (b *registryBuilder) addPresets(presets []schema.NodePreset) {
	for _, preset := range presets {
		id := strings.TrimSpace(preset.ID)
		if id == "" {
			continue
		}
		b.add(Capability{
			ID:                nodePresetID(id),
			Kind:              KindNodePreset,
			Name:              id,
			Label:             firstNonEmpty(preset.Label, id),
			Description:       strings.TrimSpace(preset.Description),
			UsableInWorkflows: true,
			Invocation: CapabilityInvocation{
				WorkflowAction:   strings.TrimSpace(preset.Action),
				NodePresetID:     id,
				DefaultArguments: cloneMap(preset.Arguments),
			},
			Contract:     CapabilityContract{InputSchema: cloneMap(preset.InputSchema)},
			Risk:         CapabilityRisk{Level: "workflow"},
			Availability: CapabilityAvailability{Status: AvailabilityAvailable},
		})
	}
}

// addValidations records portable tool-package validation capabilities.
func (b *registryBuilder) addValidations(validations []schema.ToolValidation) {
	for _, validation := range validations {
		id := strings.TrimSpace(validation.ID)
		if id == "" {
			continue
		}
		status := AvailabilityAvailable
		reasons := []string{}
		if strings.TrimSpace(validation.Mode) == "live" {
			status = AvailabilityNeedsCheck
			reasons = append(reasons, "live validation needs an explicit lab run")
		}
		b.add(Capability{
			ID:                toolValidationID(id),
			Kind:              KindToolValidation,
			Name:              id,
			Label:             firstNonEmpty(validation.Label, id),
			Description:       strings.TrimSpace(validation.Description),
			UsableInWorkflows: false,
			Invocation: CapabilityInvocation{
				NodePresetID:     strings.TrimSpace(validation.Target.PresetID),
				ToolValidationID: id,
				ValidationTarget: validationTargetMetadata(validation.Target),
			},
			Risk:         CapabilityRisk{Level: "test"},
			Availability: CapabilityAvailability{Status: status, Reasons: reasons},
			TestResults: []CapabilityTestResult{{
				Type:   validationTestType(validation.Mode),
				Status: string(status),
			}},
		})
	}
}

// add stores one capability using its stable id.
func (b *registryBuilder) add(record Capability) {
	record.ID = strings.TrimSpace(record.ID)
	if record.ID == "" {
		return
	}
	if record.Availability.Status == "" {
		record.Availability.Status = AvailabilityAvailable
	}
	if record.Metadata == nil {
		record.Metadata = map[string]any{}
	}
	b.byID[record.ID] = record
}

// registry returns a stable sorted Registry.
func (b *registryBuilder) registry() *Registry {
	ids := make([]string, 0, len(b.byID))
	for id := range b.byID {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	records := make([]Capability, 0, len(ids))
	for _, id := range ids {
		records = append(records, b.byID[id])
	}
	return &Registry{records: records, byID: b.byID}
}

// allNodes returns executable nodes from graph and state-machine definitions.
func allNodes(def definition.Definition) []definition.NodeDefinition {
	nodes := append([]definition.NodeDefinition(nil), def.Nodes...)
	var walkStates func([]definition.StateDefinition)
	walkStates = func(states []definition.StateDefinition) {
		for _, state := range states {
			nodes = append(nodes, state.OnEntry...)
			walkStates(state.States)
		}
	}
	walkStates(def.States)
	return nodes
}

// validateCommandNode checks a command.execute node against configured templates.
func (r *Registry) validateCommandNode(args map[string]any, path string) []Diagnostic {
	templateID := firstNonEmpty(stringArg(args, "template_id"), stringArg(args, "template"))
	if templateID == "" {
		return []Diagnostic{{
			Severity: "error",
			Path:     path + ".template_id",
			Message:  "command.execute requires a configured command template",
		}}
	}
	return r.validateRequiredCapability(commandID(templateID), path+".template_id", "command "+templateID)
}

// validateMCPNode checks an mcp.call node against configured MCP servers and tools.
func (r *Registry) validateMCPNode(args map[string]any, path string) []Diagnostic {
	serverID := firstNonEmpty(stringArg(args, "server_id"), stringArg(args, "server"))
	toolName := stringArg(args, "tool")
	if toolName == "" {
		return []Diagnostic{{
			Severity: "error",
			Path:     path + ".tool",
			Message:  "mcp.call requires a configured MCP tool",
		}}
	}
	if serverID == "" {
		return r.validateUniqueMCPTool(toolName, path+".tool")
	}
	diagnostics := r.validateRequiredCapability(mcpServerID(serverID), path+".server_id", "MCP server "+serverID)
	diagnostics = append(diagnostics, r.validateRequiredCapability(mcpToolID(serverID, toolName), path+".tool", "MCP tool "+toolName)...)
	return diagnostics
}

// validateToolNode checks a generic tool.call node against configured direct tools.
func (r *Registry) validateToolNode(args map[string]any, path string) []Diagnostic {
	toolName := stringArg(args, "name")
	if toolName == "" {
		return []Diagnostic{{
			Severity: "error",
			Path:     path + ".name",
			Message:  "tool.call requires a configured tool name",
		}}
	}
	return r.validateUniqueMCPTool(toolName, path+".name")
}

// validateRequiredCapability checks that one exact capability is workflow-usable.
func (r *Registry) validateRequiredCapability(id string, path string, label string) []Diagnostic {
	record, ok := r.Get(id)
	if !ok {
		return []Diagnostic{{
			Severity:     "error",
			Path:         path,
			Message:      fmt.Sprintf("%s is not configured", label),
			CapabilityID: id,
		}}
	}
	if record.UsableInWorkflows && record.Availability.Status == AvailabilityAvailable {
		return nil
	}
	return []Diagnostic{unavailableDiagnostic(record, path)}
}

// validateUniqueMCPTool resolves a direct tool name to one configured MCP tool.
func (r *Registry) validateUniqueMCPTool(toolName string, path string) []Diagnostic {
	matches := r.matchingMCPTools(toolName)
	if len(matches) == 0 {
		return []Diagnostic{{
			Severity: "error",
			Path:     path,
			Message:  fmt.Sprintf("tool %q is not configured", toolName),
		}}
	}
	if len(matches) > 1 {
		return []Diagnostic{{
			Severity: "error",
			Path:     path,
			Message:  fmt.Sprintf("tool %q is configured on multiple MCP servers; choose a server_id", toolName),
		}}
	}
	record := matches[0]
	if record.UsableInWorkflows && record.Availability.Status == AvailabilityAvailable {
		return nil
	}
	return []Diagnostic{unavailableDiagnostic(record, path)}
}

// matchingMCPTools returns configured MCP tools with the provided exposed name.
func (r *Registry) matchingMCPTools(toolName string) []Capability {
	trimmed := strings.TrimSpace(toolName)
	matches := []Capability{}
	for _, record := range r.records {
		if record.Kind != KindMCPTool {
			continue
		}
		if strings.TrimSpace(record.Name) == trimmed || strings.TrimSpace(record.Invocation.DirectToolName) == trimmed {
			matches = append(matches, record)
		}
	}
	return matches
}

// unavailableDiagnostic converts one unavailable record into a display-safe diagnostic.
func unavailableDiagnostic(record Capability, path string) Diagnostic {
	reason := strings.Join(record.Availability.Reasons, "; ")
	if reason == "" {
		reason = "required Capability Lab checks have not passed"
	}
	return Diagnostic{
		Severity:     "error",
		Path:         path,
		Message:      fmt.Sprintf("%s is unavailable: %s", record.Label, reason),
		CapabilityID: record.ID,
	}
}

// nodeArguments applies the same shorthand argument defaults used at execution time.
func nodeArguments(node definition.NodeDefinition) map[string]any {
	args := cloneMap(node.With)
	switch definition.NodeAction(node) {
	case "tool.call":
		if stringArg(args, "name") == "" && strings.TrimSpace(node.Tool) != "" {
			args["name"] = strings.TrimSpace(node.Tool)
		}
	case "mcp.call":
		if stringArg(args, "tool") == "" && strings.TrimSpace(node.Tool) != "" {
			args["tool"] = strings.TrimSpace(node.Tool)
		}
	case "command.execute":
		if stringArg(args, "template_id") == "" && strings.TrimSpace(node.Tool) != "" {
			args["template_id"] = strings.TrimSpace(node.Tool)
		}
	}
	return args
}

// dedupeDiagnostics preserves first diagnostics for repeated capability checks.
func dedupeDiagnostics(values []Diagnostic) []Diagnostic {
	seen := map[string]struct{}{}
	out := make([]Diagnostic, 0, len(values))
	for _, value := range values {
		key := value.Path + "|" + value.CapabilityID + "|" + value.Message
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, value)
	}
	return out
}

// workflowActionID returns the stable workflow action capability id.
func workflowActionID(name string) string {
	return "workflow_action:" + strings.TrimSpace(name)
}

// commandID returns the stable command capability id.
func commandID(name string) string {
	return "command:" + strings.TrimSpace(name)
}

// mcpServerID returns the stable MCP server capability id.
func mcpServerID(name string) string {
	return "mcp_server:" + strings.TrimSpace(name)
}

// mcpToolID returns the stable MCP tool capability id.
func mcpToolID(server string, tool string) string {
	return "mcp_tool:" + strings.TrimSpace(server) + ":" + strings.TrimSpace(tool)
}

// nodePresetID returns the stable node preset capability id.
func nodePresetID(id string) string {
	return "node_preset:" + strings.TrimSpace(id)
}

// toolValidationID returns the stable tool validation capability id.
func toolValidationID(id string) string {
	return "tool_validation:" + strings.TrimSpace(id)
}

// validationTestType returns the registry test result type for one validation mode.
func validationTestType(mode string) string {
	if strings.TrimSpace(mode) == "live" {
		return TestSafeSmoke
	}
	return TestMockedValidation
}

// validationTargetMetadata returns display-safe target metadata for a validation.
func validationTargetMetadata(target schema.ToolValidationTarget) map[string]any {
	out := map[string]any{}
	if value := strings.TrimSpace(target.Type); value != "" {
		out["type"] = value
	}
	if value := strings.TrimSpace(target.PresetID); value != "" {
		out["preset_id"] = value
	}
	if value := strings.TrimSpace(target.Command); value != "" {
		out["command"] = value
	}
	if value := strings.TrimSpace(target.Operation); value != "" {
		out["operation"] = value
	}
	if value := strings.TrimSpace(target.MCPServer); value != "" {
		out["mcp_server"] = value
	}
	if value := strings.TrimSpace(target.MCPTool); value != "" {
		out["mcp_tool"] = value
	}
	return out
}

// serverHasEndpoint reports whether a server has static transport information.
func serverHasEndpoint(server schema.MCPServer) bool {
	switch strings.TrimSpace(server.Transport) {
	case "stdio":
		return strings.TrimSpace(server.Command) != ""
	default:
		return strings.TrimSpace(server.Endpoint) != "" || strings.TrimSpace(server.URL) != ""
	}
}

// contains reports whether values contains target.
func contains(values []string, target string) bool {
	target = strings.TrimSpace(target)
	for _, value := range values {
		if strings.TrimSpace(value) == target {
			return true
		}
	}
	return false
}

// stringArg returns one string argument from a map.
func stringArg(values map[string]any, key string) string {
	if values == nil {
		return ""
	}
	value, ok := values[key]
	if !ok || value == nil {
		return ""
	}
	if text, ok := value.(string); ok {
		return strings.TrimSpace(text)
	}
	return strings.TrimSpace(fmt.Sprint(value))
}

// firstNonEmpty returns the first non-empty string.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

// cloneMap copies JSON-like maps.
func cloneMap(values map[string]any) map[string]any {
	if len(values) == 0 {
		return map[string]any{}
	}
	out := make(map[string]any, len(values))
	for key, value := range values {
		out[key] = value
	}
	return out
}
