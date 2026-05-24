// This file defines dumb Capability Registry data models.
package capabilities

// CapabilityKind identifies one class of runnable or design-time capability.
type CapabilityKind string

const (
	// KindCommand identifies one configured command template.
	KindCommand CapabilityKind = "command"
	// KindMCPServer identifies one configured MCP server.
	KindMCPServer CapabilityKind = "mcp_server"
	// KindMCPTool identifies one configured MCP tool.
	KindMCPTool CapabilityKind = "mcp_tool"
	// KindAgentProfile identifies one configured agent identity.
	KindAgentProfile CapabilityKind = "agent_profile"
	// KindWorkflowAction identifies one built-in workflow action.
	KindWorkflowAction CapabilityKind = "workflow_action"
	// KindNodePreset identifies one workflow node preset.
	KindNodePreset CapabilityKind = "node_preset"
	// KindNodeScenario identifies one node preset scenario.
	KindNodeScenario CapabilityKind = "node_scenario"
)

// AvailabilityStatus describes whether a capability can be used.
type AvailabilityStatus string

const (
	// AvailabilityAvailable means required static checks are satisfied.
	AvailabilityAvailable AvailabilityStatus = "available"
	// AvailabilityUnavailable means the capability cannot be used.
	AvailabilityUnavailable AvailabilityStatus = "unavailable"
	// AvailabilityNeedsCheck means a lab check is required before publish.
	AvailabilityNeedsCheck AvailabilityStatus = "needs_check"
)

// Capability stores one normalized registry entry.
type Capability struct {
	ID                string                 `json:"id"`
	Kind              CapabilityKind         `json:"kind"`
	Name              string                 `json:"name"`
	Label             string                 `json:"label"`
	Description       string                 `json:"description,omitempty"`
	UsableInChat      bool                   `json:"usable_in_chat"`
	UsableInWorkflows bool                   `json:"usable_in_workflows"`
	Invocation        CapabilityInvocation   `json:"invocation"`
	Contract          CapabilityContract     `json:"contract"`
	Risk              CapabilityRisk         `json:"risk"`
	Availability      CapabilityAvailability `json:"availability"`
	TestResults       []CapabilityTestResult `json:"test_results,omitempty"`
	Metadata          map[string]any         `json:"metadata,omitempty"`
}

// CapabilityInvocation stores direct-call and workflow-node invocation details.
type CapabilityInvocation struct {
	DirectToolName   string         `json:"direct_tool_name,omitempty"`
	WorkflowAction   string         `json:"workflow_action,omitempty"`
	MCPServer        string         `json:"mcp_server,omitempty"`
	MCPTool          string         `json:"mcp_tool,omitempty"`
	CommandTemplate  string         `json:"command_template,omitempty"`
	AgentProfileID   string         `json:"agent_profile_id,omitempty"`
	NodePresetID     string         `json:"node_preset_id,omitempty"`
	NodeScenarioID   string         `json:"node_scenario_id,omitempty"`
	DefaultArguments map[string]any `json:"default_arguments,omitempty"`
}

// CapabilityContract stores schema-like invocation contracts.
type CapabilityContract struct {
	InputSchema          map[string]any `json:"input_schema,omitempty"`
	OutputSchema         map[string]any `json:"output_schema,omitempty"`
	ConfirmationRequired bool           `json:"confirmation_required,omitempty"`
}

// CapabilityRisk stores user-facing risk metadata.
type CapabilityRisk struct {
	Level                string `json:"level"`
	RequiresConfirmation bool   `json:"requires_confirmation,omitempty"`
}

// CapabilityAvailability stores display-safe availability state.
type CapabilityAvailability struct {
	Status  AvailabilityStatus `json:"status"`
	Reasons []string           `json:"reasons,omitempty"`
}

// CapabilityTestResult stores one deterministic lab check result.
type CapabilityTestResult struct {
	Type      string `json:"type"`
	Status    string `json:"status"`
	Message   string `json:"message,omitempty"`
	CheckedAt string `json:"checked_at,omitempty"`
}

const (
	// TestConnection verifies that a configured boundary can be reached.
	TestConnection = "connection"
	// TestSchema verifies that exposed input and output schemas are usable.
	TestSchema = "schema"
	// TestSafeSmoke verifies a bounded non-destructive live invocation.
	TestSafeSmoke = "safe_smoke"
	// TestMockedScenario verifies deterministic behavior with mocked boundary responses.
	TestMockedScenario = "mocked_scenario"
	// TestRiskReview verifies user-facing risk and confirmation metadata.
	TestRiskReview = "risk_review"
)

// Query selects capability records for listing.
type Query struct {
	Kind              string
	UsableInChat      *bool
	UsableInWorkflows *bool
}

// Diagnostic reports one unavailable capability required by a workflow.
type Diagnostic struct {
	Severity     string `json:"severity"`
	Path         string `json:"path"`
	Message      string `json:"message"`
	CapabilityID string `json:"capability_id,omitempty"`
}
