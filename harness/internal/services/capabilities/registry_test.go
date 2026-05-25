// This file tests Capability Registry normalization and workflow gating.
package capabilities

import (
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/workflow/definition"
)

// TestRegistryLoadsConfiguredCapabilities verifies each configured boundary is normalized.
func TestRegistryLoadsConfiguredCapabilities(t *testing.T) {
	registry := NewRegistry(testToolsConfig(true), schema.Agent{
		Name:        "Agent Awesome",
		Description: "Primary assistant profile.",
		Instruction: "Help with configured work.",
	})

	command, ok := registry.Get("command:lint")
	if !ok {
		t.Fatalf("command:lint not found")
	}
	if !command.UsableInChat || !command.UsableInWorkflows {
		t.Fatalf("command usability = chat %v workflow %v, want both true", command.UsableInChat, command.UsableInWorkflows)
	}
	if command.Invocation.DirectToolName != "command_execute" || command.Invocation.WorkflowAction != "command.execute" {
		t.Fatalf("command invocation = %#v, want distinct direct and workflow calls", command.Invocation)
	}
	if command.Invocation.CommandTemplate != "lint" {
		t.Fatalf("command template = %q, want lint", command.Invocation.CommandTemplate)
	}

	mcpTool, ok := registry.Get("mcp_tool:sourcecontrol:sourcecontrol.push")
	if !ok {
		t.Fatalf("sourcecontrol push MCP tool not found")
	}
	if !mcpTool.Contract.ConfirmationRequired || !mcpTool.Risk.RequiresConfirmation {
		t.Fatalf("MCP push confirmation metadata = %#v / %#v, want required", mcpTool.Contract, mcpTool.Risk)
	}

	expectCapability(t, registry, "workflow_action:data.assert", KindWorkflowAction)
	expectCapability(t, registry, "agent_profile:default", KindAgentProfile)
	expectCapability(t, registry, "node_preset:lint", KindNodePreset)
	validation := expectCapability(t, registry, "tool_validation:lint_success", KindToolValidation)
	if validation.TestResults[0].Type != TestMockedValidation {
		t.Fatalf("validation test type = %q, want %q", validation.TestResults[0].Type, TestMockedValidation)
	}
	if validation.Invocation.ValidationTarget["type"] != "workflow-node" {
		t.Fatalf("validation target = %#v, want workflow-node", validation.Invocation.ValidationTarget)
	}
}

// TestValidateDefinitionBlocksUnavailableCapabilities verifies publish checks are explicit.
func TestValidateDefinitionBlocksUnavailableCapabilities(t *testing.T) {
	registry := NewRegistry(testToolsConfig(false), schema.Agent{Name: "AA", Instruction: "Work."})
	def := definition.Definition{
		Kind: definition.KindWorkflow,
		ID:   "missing_capabilities",
		Nodes: []definition.NodeDefinition{
			{
				ID:   "run_lint",
				Uses: "command.execute",
				With: map[string]any{"template_id": "lint"},
			},
			{
				ID:   "push",
				Uses: "mcp.call",
				With: map[string]any{
					"server_id": "sourcecontrol",
					"tool":      "sourcecontrol.missing",
				},
			},
		},
	}

	diagnostics := registry.ValidateDefinition(def)
	if len(diagnostics) != 2 {
		t.Fatalf("diagnostics = %#v, want command unavailable and MCP tool missing", diagnostics)
	}
	if !containsDiagnostic(diagnostics, "command:lint", "local command execution is disabled") {
		t.Fatalf("diagnostics = %#v, want display-safe disabled command reason", diagnostics)
	}
	if !containsDiagnostic(diagnostics, "mcp_tool:sourcecontrol:sourcecontrol.missing", "not configured") {
		t.Fatalf("diagnostics = %#v, want missing MCP tool reason", diagnostics)
	}
}

// TestValidateDefinitionAcceptsShorthandNodeTool verifies builder shorthand resolves before gating.
func TestValidateDefinitionAcceptsShorthandNodeTool(t *testing.T) {
	registry := NewRegistry(testToolsConfig(true), schema.Agent{Name: "AA", Instruction: "Work."})
	def := definition.Definition{
		Kind: definition.KindWorkflow,
		ID:   "shorthand",
		Nodes: []definition.NodeDefinition{
			{ID: "run_lint", Type: "command", Tool: "lint"},
			{ID: "inspect", Type: "mcp", Tool: "sourcecontrol.inspect_repository", With: map[string]any{"server_id": "sourcecontrol"}},
			{ID: "tool_call", Type: "tool", Tool: "sourcecontrol.inspect_repository"},
		},
	}

	if diagnostics := registry.ValidateDefinition(def); len(diagnostics) != 0 {
		t.Fatalf("ValidateDefinition() = %#v, want no diagnostics", diagnostics)
	}
}

// expectCapability loads one capability and checks its kind.
func expectCapability(t *testing.T, registry *Registry, id string, kind CapabilityKind) Capability {
	t.Helper()
	record, ok := registry.Get(id)
	if !ok {
		t.Fatalf("%s not found", id)
	}
	if record.Kind != kind {
		t.Fatalf("%s kind = %q, want %q", id, record.Kind, kind)
	}
	return record
}

// containsDiagnostic reports whether a diagnostic references one capability and message.
func containsDiagnostic(diagnostics []Diagnostic, capabilityID string, message string) bool {
	for _, diagnostic := range diagnostics {
		if diagnostic.CapabilityID == capabilityID && strings.Contains(diagnostic.Message, message) {
			return true
		}
	}
	return false
}

// testToolsConfig builds a focused registry fixture.
func testToolsConfig(localExecEnabled bool) *schema.Tools {
	return &schema.Tools{
		LocalExec: schema.LocalExec{
			Enabled: localExecEnabled,
			Commands: []schema.LocalExecCommand{{
				Name:        "lint",
				Executable:  "go",
				Description: "Run lint checks.",
			}},
		},
		MCP: schema.MCP{
			Enabled: true,
			Servers: []schema.MCPServer{{
				Name:                     "sourcecontrol",
				Transport:                "streamable-http",
				Endpoint:                 "http://127.0.0.1:8095/mcp",
				RequireConfirmationTools: []string{"sourcecontrol.push"},
				Tools: schema.MCPToolFilter{Allow: []string{
					"sourcecontrol.inspect_repository",
					"sourcecontrol.push",
				}},
			}},
		},
		NodePresets: []schema.NodePreset{{
			ID:     "lint",
			Label:  "Lint",
			Action: "command.execute",
			Arguments: map[string]any{
				"template_id": "lint",
			},
		}},
		Validations: []schema.ToolValidation{{
			ID:    "lint_success",
			Label: "Lint success",
			Mode:  "mocked",
			Target: schema.ToolValidationTarget{
				Type:     "workflow-node",
				PresetID: "lint",
			},
			Expected: map[string]any{"status": "succeeded"},
		}},
	}
}
