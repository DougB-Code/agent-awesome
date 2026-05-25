// This file defines built-in workflow action metadata and manifests.
package actions

import (
	"encoding/json"
	"strings"

	"agentawesome/internal/services/workflow/contracts"
)

const (
	// DefaultManifestVersion is the version assigned to AA-owned action manifests.
	DefaultManifestVersion = "1"
	// DefaultManifestTimeoutMS is the default action invocation timeout in milliseconds.
	DefaultManifestTimeoutMS = 30000
)

// Metadata describes one built-in action for authoring and manifest generation.
type Metadata struct {
	Name            string
	Label           string
	Description     string
	Risk            string
	Available       bool
	InputSchema     map[string]any
	OutputSchema    map[string]any
	InputContracts  []string
	OutputContracts []string
}

// MetadataFor returns authoring metadata for one registered action.
func MetadataFor(name string) Metadata {
	action := Metadata{
		Name:           strings.TrimSpace(name),
		Label:          strings.TrimSpace(name),
		Description:    "Workflow action.",
		Risk:           "read",
		Available:      true,
		InputSchema:    map[string]any{"type": "object"},
		OutputSchema:   map[string]any{"type": "object"},
		InputContracts: []string{"aa.workflow.action_input.v1"},
	}
	switch action.Name {
	case "tool.call":
		action.Label = "Run Tool"
		action.Description = "Call a harness-exposed context or MCP-backed tool."
		action.Risk = "tool"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"name"}, "properties": map[string]any{"name": map[string]any{"type": "string"}, "domain_id": map[string]any{"type": "string"}, "arguments": map[string]any{"type": "object"}}}
		action.InputContracts = []string{"aa.external_call_request.v1"}
		action.OutputContracts = []string{"aa.external_call_result.v1"}
	case "mcp.call":
		action.Label = "Call MCP Tool"
		action.Description = "Call an installed MCP tool endpoint."
		action.Risk = "tool"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"tool"}, "properties": map[string]any{"server_id": map[string]any{"type": "string"}, "endpoint": map[string]any{"type": "string"}, "tool": map[string]any{"type": "string"}, "arguments": map[string]any{"type": "object"}}}
		action.InputContracts = []string{"aa.external_call_request.v1"}
		action.OutputContracts = []string{"aa.external_call_result.v1"}
	case "command.execute":
		action.Label = "Run Command"
		action.Description = "Run a configured deterministic command operation."
		action.Risk = "tool"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"template_id"}, "properties": map[string]any{"template_id": map[string]any{"type": "string"}, "parameters": map[string]any{"type": "object"}, "cwd": map[string]any{"type": "string"}, "reason": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.command_execute_request.v1"}
		action.OutputContracts = []string{"aa.command_result.v1"}
	case "data.assert":
		action.Label = "Assert Data"
		action.Description = "Gate workflow progression on deterministic input data checks."
		action.Risk = "validation"
		action.InputSchema = map[string]any{"type": "object", "properties": map[string]any{"path": map[string]any{"type": "string"}, "mode": map[string]any{"type": "string"}, "value": map[string]any{}, "checks": map[string]any{"type": "array"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"passed": map[string]any{"type": "boolean"}, "checks": map[string]any{"type": "array"}}}
		action.InputContracts = []string{"aa.validation_request.v1"}
		action.OutputContracts = []string{"aa.validation_result.v1"}
	case "data.defaults":
		action.Label = "Apply Defaults"
		action.Description = "Merge an input object with declarative default values."
		action.Risk = "validation"
		action.InputSchema = map[string]any{"type": "object", "properties": map[string]any{"input": map[string]any{"type": "object"}, "defaults": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object"}
		action.InputContracts = []string{"aa.workflow.action_input.v1"}
		action.OutputContracts = []string{"aa.workflow.action_output.v1"}
	case "decision.route":
		action.Label = "Choose Route"
		action.Description = "Select one deterministic downstream route from ordered rules."
		action.Risk = "validation"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"default"}, "properties": map[string]any{"rules": map[string]any{"type": "array"}, "default": map[string]any{"type": "string"}}}
		action.OutputSchema = map[string]any{"type": "object", "required": []any{"route", "matched"}, "properties": map[string]any{"route": map[string]any{"type": "string"}, "rule_id": map[string]any{"type": "string"}, "matched": map[string]any{"type": "boolean"}}}
		action.InputContracts = []string{"aa.decision_route_request.v1"}
		action.OutputContracts = []string{"aa.decision_route_result.v1"}
	case "llm.generate":
		action.Label = "Generate Structured Output"
		action.Description = "Call a configured model boundary and require JSON-shaped output."
		action.Risk = "llm"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"prompt"}, "properties": map[string]any{"model": map[string]any{"type": "string"}, "prompt": map[string]any{"type": "string"}, "output_schema": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object"}
		action.InputContracts = []string{"aa.llm_generate_request.v1"}
		action.OutputContracts = []string{"aa.llm_generate_result.v1"}
	case "workflow.run":
		action.Label = "Run Workflow"
		action.Description = "Start a nested workflow definition."
		action.Risk = "workflow"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"workflow"}, "properties": map[string]any{"workflow": map[string]any{"type": "string"}, "input": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"run_id": map[string]any{"type": "string"}, "definition_id": map[string]any{"type": "string"}, "status": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.workflow_run_request.v1"}
		action.OutputContracts = []string{"aa.workflow_run_result.v1"}
	case "workflow.signal":
		action.Label = "Signal Workflow"
		action.Description = "Emit a workflow signal."
		action.Risk = "workflow"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"signal"}, "properties": map[string]any{"run_id": map[string]any{"type": "string"}, "signal": map[string]any{"type": "string"}, "payload": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"run_id": map[string]any{"type": "string"}, "signal": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.workflow_signal_request.v1"}
		action.OutputContracts = []string{"aa.workflow_signal_result.v1"}
	case "human.request":
		action.Label = "Ask User"
		action.Description = "Create a pending user item through the gateway-facing inbox."
		action.Risk = "approval"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"prompt"}, "properties": map[string]any{"prompt": map[string]any{"type": "string"}, "payload": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"pending_id": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.human_request.v1"}
		action.OutputContracts = []string{"aa.human_request_result.v1"}
	case "delay.until":
		action.Label = "Wait"
		action.Description = "Pause until a timestamp or duration elapses."
		action.Risk = "time"
		action.InputSchema = map[string]any{"type": "object", "properties": map[string]any{"until": map[string]any{"type": "string"}, "duration": map[string]any{"type": "string"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"waited": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.wait_request.v1"}
		action.OutputContracts = []string{"aa.wait_result.v1"}
	}
	return action
}

// ManifestForMetadata converts action metadata into an AA-owned tool manifest.
func ManifestForMetadata(meta Metadata) contracts.ToolManifest {
	return contracts.ToolManifest{
		ID:          strings.TrimSpace(meta.Name),
		Version:     DefaultManifestVersion,
		Title:       strings.TrimSpace(meta.Label),
		Description: strings.TrimSpace(meta.Description),
		Input: contracts.Contract{
			Schema: cloneMap(meta.InputSchema),
		},
		Output: contracts.Contract{
			Schema: cloneMap(meta.OutputSchema),
		},
		Effects: effectsForRisk(meta.Risk),
		Runtime: contracts.Runtime{
			TimeoutMS: DefaultManifestTimeoutMS,
			Retryable: meta.Risk != "approval" &&
				meta.Risk != "time",
			Sandbox: SandboxForAction(meta.Name),
		},
		Source: contracts.ManifestSourceAA,
	}
}

// effectsForRisk maps a coarse authoring risk label to deterministic effects.
func effectsForRisk(risk string) contracts.Effects {
	switch strings.TrimSpace(risk) {
	case "tool", "llm":
		return contracts.Effects{
			Network: contracts.NetworkEffects{AllowedHosts: []string{contracts.NetworkBoundaryConfiguredTool}},
		}
	case "approval":
		return contracts.Effects{}
	default:
		return contracts.Effects{}
	}
}

// SandboxForAction maps built-in actions to their execution boundary.
func SandboxForAction(name string) string {
	switch strings.TrimSpace(name) {
	case "tool.call":
		return contracts.RuntimeSandboxHarnessContext
	case "mcp.call":
		return contracts.RuntimeSandboxMCP
	case "command.execute":
		return contracts.RuntimeSandboxCommandDaemon
	case "llm.generate":
		return contracts.RuntimeSandboxModel
	default:
		return contracts.RuntimeSandboxAA
	}
}

// cloneMap returns a JSON-deep-copy of action schema data.
func cloneMap(value map[string]any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return map[string]any{}
	}
	var cloned map[string]any
	if err := json.Unmarshal(encoded, &cloned); err != nil {
		return map[string]any{}
	}
	return cloned
}
