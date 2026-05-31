// This file tests portable tool-package validation execution.
package toolvalidation

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/agentvalidation"
	"agentawesome/internal/services/command/command"
	"agentawesome/internal/services/runbook/actions"
)

// TestRunAllPassesLinuxToolMockedValidations verifies shipped utility checks are runnable.
func TestRunAllPassesLinuxToolMockedValidations(t *testing.T) {
	tools, err := config.LoadTools(filepath.Join(repoRoot(t), "harness", "tool.yaml"), true)
	if err != nil {
		t.Fatalf("LoadTools() error = %v", err)
	}

	result := NewRunner(nil).RunAll(context.Background(), *tools)
	if result.Total != 51 || result.Passed != 51 || result.Failed != 0 || result.Unsupported != 0 {
		t.Fatalf("RunAll() = %#v, want fifty-one passing mocked validations", result)
	}
	if result.Coverage.Required != 34 || result.Coverage.Covered != 34 || len(result.Coverage.Missing) != 0 {
		t.Fatalf("Coverage = %#v, want full command-operation and runbook envelope coverage", result.Coverage)
	}
	if result.InputSchemaCoverage.Required != 17 || result.InputSchemaCoverage.Covered != 17 || len(result.InputSchemaCoverage.Missing) != 0 {
		t.Fatalf("InputSchemaCoverage = %#v, want schemas for all command operations", result.InputSchemaCoverage)
	}
	if len(result.AgentToolCalls) != 17 {
		t.Fatalf("AgentToolCalls = %#v, want one id per command operation", result.AgentToolCalls)
	}
}

// TestCoverageForReportsMissingTargets verifies shared-library coverage diagnostics.
func TestCoverageForReportsMissingTargets(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "rg",
			Operations: []schema.CommandOperation{{
				Name:        "search_text",
				Description: "Search text.",
			}},
		}}},
		NodePresets: []schema.NodePreset{{ID: "rg_search", Label: "RG search"}},
		Validations: []schema.ToolValidation{{
			ID: "rg_search_text_mocked",
			Target: schema.ToolValidationTarget{
				Type:      "command-operation",
				Command:   "rg",
				Operation: "search_text",
			},
		}},
	}

	coverage := CoverageFor(tools)
	if coverage.Required != 3 || coverage.Covered != 0 || len(coverage.Missing) != 3 {
		t.Fatalf("CoverageFor() = %#v, want placeholder validation to leave all targets uncovered", coverage)
	}
	if !missingCoverage(coverage.Missing, "command-operation", "rg.search_text") {
		t.Fatalf("Missing = %#v, want rg.search_text command coverage", coverage.Missing)
	}
	if !missingCoverage(coverage.Missing, "runbook-node", "command:rg.search_text") {
		t.Fatalf("Missing = %#v, want rg.search_text runbook-node coverage", coverage.Missing)
	}
	if !missingCoverage(coverage.Missing, "runbook-node", "rg_search") {
		t.Fatalf("Missing = %#v, want rg_search preset", coverage.Missing)
	}
}

// TestInputSchemaCoverageForReportsMissingSchemas verifies schema diagnostics.
func TestInputSchemaCoverageForReportsMissingSchemas(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "rg",
			Operations: []schema.CommandOperation{
				{Name: "search_text", Description: "Search text."},
				{
					Name:        "list_files",
					Description: "List files.",
					InputSchema: map[string]any{"type": "object"},
				},
			},
		}}},
	}

	coverage := InputSchemaCoverageFor(tools)
	if coverage.Required != 2 || coverage.Covered != 1 || len(coverage.Missing) != 1 {
		t.Fatalf("InputSchemaCoverageFor() = %#v, want one missing schema", coverage)
	}
	if coverage.Missing[0].ID != "rg.search_text" {
		t.Fatalf("Missing = %#v, want rg.search_text", coverage.Missing)
	}
}

// TestCoverageForCountsRunbookEnvelopeTargets verifies runbook envelopes are required.
func TestCoverageForCountsRunbookEnvelopeTargets(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "rg",
			Operations: []schema.CommandOperation{{
				Name:        "search_text",
				Description: "Search text.",
			}},
		}}},
		Validations: []schema.ToolValidation{
			{
				ID: "rg_search_text_mocked",
				Expected: map[string]any{
					"status": "succeeded",
				},
				Target: schema.ToolValidationTarget{
					Type:      "command-operation",
					Command:   "rg",
					Operation: "search_text",
				},
			},
			{
				ID: "rg_search_text_runbook_mocked",
				Expected: map[string]any{
					"status": "succeeded",
				},
				Target: schema.ToolValidationTarget{
					Type:      "runbook-node",
					Command:   "rg",
					Operation: "search_text",
				},
			},
		},
	}

	coverage := CoverageFor(tools)
	if coverage.Required != 2 || coverage.Covered != 2 || len(coverage.Missing) != 0 {
		t.Fatalf("CoverageFor() = %#v, want command and runbook envelope coverage", coverage)
	}
}

// TestAgentToolCallIDsForReportsContracts verifies shared-library lookup ids.
func TestAgentToolCallIDsForReportsContracts(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "rg",
			Operations: []schema.CommandOperation{{
				Name: "search_text",
			}},
		}}},
		MCP: schema.MCP{Servers: []schema.MCPServer{{
			Name: "memory",
			Tools: schema.MCPToolFilter{
				Allow: []string{"search_memory"},
			},
		}}},
	}

	ids := AgentToolCallIDsFor(tools)
	if len(ids) != 2 || ids[0] != "command:rg.search_text" || ids[1] != "mcp:memory.search_memory" {
		t.Fatalf("AgentToolCallIDsFor() = %#v, want command and mcp ids", ids)
	}
}

// TestAgentToolContractsForReportsInputSchemas verifies argument contracts.
func TestAgentToolContractsForReportsInputSchemas(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "tar",
			Operations: []schema.CommandOperation{{
				Name: "create_archive",
				InputSchema: map[string]any{
					"type":     "object",
					"required": []any{"archive_path"},
				},
			}},
		}}},
	}

	contracts := AgentToolContractsFor(tools)
	contract, ok := contracts["command:tar.create_archive"]
	if !ok {
		t.Fatalf("AgentToolContractsFor() = %#v, want tar contract", contracts)
	}
	if contract.InputSchema["type"] != "object" {
		t.Fatalf("InputSchema = %#v, want object schema", contract.InputSchema)
	}
}

// TestCoverageForCountsMCPRunbookTargets verifies MCP tools require envelope coverage.
func TestCoverageForCountsMCPRunbookTargets(t *testing.T) {
	tools := schema.Tools{
		MCP: schema.MCP{Servers: []schema.MCPServer{{
			Name: "memory",
			Tools: schema.MCPToolFilter{
				Allow: []string{"search_memory"},
			},
		}}},
		Validations: []schema.ToolValidation{
			{
				ID: "memory_search_mocked",
				Expected: map[string]any{
					"status": "succeeded",
				},
				Target: schema.ToolValidationTarget{
					Type:      "mcp-tool",
					MCPServer: "memory",
					MCPTool:   "search_memory",
				},
			},
			{
				ID: "memory_search_runbook_mocked",
				Expected: map[string]any{
					"status": "succeeded",
				},
				Target: schema.ToolValidationTarget{
					Type:      "runbook-node",
					MCPServer: "memory",
					MCPTool:   "search_memory",
				},
			},
		},
	}

	coverage := CoverageFor(tools)
	if coverage.Required != 2 || coverage.Covered != 2 || len(coverage.Missing) != 0 {
		t.Fatalf("CoverageFor() = %#v, want mcp and runbook envelope coverage", coverage)
	}
}

// TestRunSelectedRunsOnlyRequestedValidations verifies row-level selection.
func TestRunSelectedRunsOnlyRequestedValidations(t *testing.T) {
	tools := schema.Tools{Validations: []schema.ToolValidation{
		mockedValidation("first"),
		mockedValidation("second"),
	}}

	result, err := NewRunner(nil).RunSelected(context.Background(), tools, []string{"second"})
	if err != nil {
		t.Fatalf("RunSelected() error = %v", err)
	}
	if result.Total != 1 || result.Passed != 1 || len(result.Results) != 1 || result.Results[0].ID != "second" {
		t.Fatalf("RunSelected() = %#v, want only second validation", result)
	}
}

// TestRunSelectedReportsMissingValidationIDs verifies stale UI selections fail clearly.
func TestRunSelectedReportsMissingValidationIDs(t *testing.T) {
	tools := schema.Tools{Validations: []schema.ToolValidation{mockedValidation("known")}}

	result, err := NewRunner(nil).RunSelected(context.Background(), tools, []string{"known", "missing"})
	if result.Total != 1 || result.Passed != 1 {
		t.Fatalf("RunSelected() result = %#v, want known validation result", result)
	}
	missing, ok := err.(MissingValidationError)
	if !ok {
		t.Fatalf("RunSelected() error = %T %v, want MissingValidationError", err, err)
	}
	if len(missing.IDs) != 1 || missing.IDs[0] != "missing" {
		t.Fatalf("missing IDs = %#v, want missing", missing.IDs)
	}
}

// TestRunSelectedModesFiltersLiveValidations verifies portable CI selection.
func TestRunSelectedModesFiltersLiveValidations(t *testing.T) {
	tools := schema.Tools{Validations: []schema.ToolValidation{
		mockedValidation("mocked_check"),
		{
			ID:   "live_check",
			Mode: "live",
			Target: schema.ToolValidationTarget{
				Type:      "command-operation",
				Command:   "test",
				Operation: "live_check",
			},
			Expected: map[string]any{"status": "succeeded"},
		},
	}}

	result, err := NewRunner(nil).RunSelectedModes(context.Background(), tools, nil, "mocked")
	if err != nil {
		t.Fatalf("RunSelectedModes() error = %v", err)
	}
	if result.Total != 1 || result.Passed != 1 || result.Results[0].ID != "mocked_check" {
		t.Fatalf("RunSelectedModes() = %#v, want mocked case only", result)
	}
}

// TestCoverageForModeCountsOnlySelectedLane verifies lane-specific coverage.
func TestCoverageForModeCountsOnlySelectedLane(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "rg",
			Operations: []schema.CommandOperation{{
				Name:        "search_text",
				Description: "Search text.",
			}},
		}}},
		Validations: []schema.ToolValidation{{
			ID:   "rg_search_text_live",
			Mode: "live",
			Target: schema.ToolValidationTarget{
				Type:      "command-operation",
				Command:   "rg",
				Operation: "search_text",
			},
			Expected: map[string]any{"status": "succeeded"},
		}},
	}

	mocked := CoverageForMode(tools, "mocked")
	if mocked.Covered != 0 || !missingCoverage(mocked.Missing, "command-operation", "rg.search_text") {
		t.Fatalf("CoverageForMode(mocked) = %#v, want live case ignored", mocked)
	}
	live := CoverageForMode(tools, "live")
	if live.Covered != 1 || missingCoverage(live.Missing, "command-operation", "rg.search_text") {
		t.Fatalf("CoverageForMode(live) = %#v, want live command coverage", live)
	}
}

// TestRunLiveCommandOperationUsesCommandExecutor verifies live checks use command.execute.
func TestRunLiveCommandOperationUsesCommandExecutor(t *testing.T) {
	executor := &recordingCommandExecutor{
		result: command.StatusResult{Status: "succeeded", ExitCode: 0, StdoutTail: "ok"},
	}
	tools := schema.Tools{Validations: []schema.ToolValidation{{
		ID:   "curl_live",
		Mode: "live",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "curl",
			Operation: "http_get",
		},
		Input:    map[string]any{"url": "http://127.0.0.1:8080/health"},
		Expected: map[string]any{"status": "succeeded"},
	}}}

	result := NewRunner(executor).Run(context.Background(), tools, tools.Validations[0])
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if executor.request.TemplateID != "curl.http_get" {
		t.Fatalf("TemplateID = %q, want curl.http_get", executor.request.TemplateID)
	}
	if executor.request.Parameters["url"] != "http://127.0.0.1:8080/health" {
		t.Fatalf("Parameters = %#v, want validation input", executor.request.Parameters)
	}
}

// TestRunMockedCommandOperationValidatesInputSchema verifies portable examples.
func TestRunMockedCommandOperationValidatesInputSchema(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "rg",
			Operations: []schema.CommandOperation{{
				Name: "search_text",
				InputSchema: map[string]any{
					"type":     "object",
					"required": []any{"pattern"},
					"properties": map[string]any{
						"pattern": map[string]any{"type": "string"},
					},
				},
			}},
		}}},
	}
	validation := schema.ToolValidation{
		ID:   "rg_missing_input",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "rg",
			Operation: "search_text",
		},
		Mocks: map[string]any{
			"command.execute": map[string]any{"status": "succeeded"},
		},
		Assertions: []schema.ValidationAssertion{{Type: "status", Equals: "succeeded"}},
	}

	result := NewRunner(nil).Run(context.Background(), tools, validation)
	if result.Status != StatusFailed {
		t.Fatalf("Run() status = %q, want failed", result.Status)
	}
	if len(result.Assertions) != 1 || result.Assertions[0].Type != "input-schema" || result.Assertions[0].Passed {
		t.Fatalf("Assertions = %#v, want failed input-schema assertion", result.Assertions)
	}
}

// TestRunLiveCommandOperationMaterializesFixtures verifies live tests get a fixture cwd.
func TestRunLiveCommandOperationMaterializesFixtures(t *testing.T) {
	executor := &fixtureCommandExecutor{}
	validation := schema.ToolValidation{
		ID:   "cat_fixture",
		Mode: "live",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "cat",
			Operation: "read",
		},
		Input: map[string]any{"path": "input.txt"},
		Fixtures: map[string]any{
			"files": []any{
				map[string]any{"path": "input.txt", "content": "hello from fixture"},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:     "stdout-contains",
			Contains: "hello from fixture",
		}},
	}

	result := NewRunner(executor).Run(context.Background(), schema.Tools{Validations: []schema.ToolValidation{validation}}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if executor.workingDir == "" {
		t.Fatalf("workingDir is empty, want fixture workspace")
	}
	if _, err := os.Stat(executor.workingDir); !os.IsNotExist(err) {
		t.Fatalf("fixture workspace still exists or stat failed: %v", err)
	}
}

// TestRunLiveRunbookNodeUsesCommandAction verifies presets execute through runbook actions.
func TestRunLiveRunbookNodeUsesCommandAction(t *testing.T) {
	executor := &fixtureCommandExecutor{}
	tools := schema.Tools{
		NodePresets: []schema.NodePreset{{
			ID:     "cat_read",
			Action: "command.execute",
			Arguments: map[string]any{
				"template_id": "cat.read",
				"parameters": map[string]any{
					"path": "${path}",
				},
			},
		}},
	}
	validation := schema.ToolValidation{
		ID:   "cat_runbook_node_live",
		Mode: "live",
		Target: schema.ToolValidationTarget{
			Type:     "runbook-node",
			PresetID: "cat_read",
		},
		Input: map[string]any{"path": "input.txt"},
		Fixtures: map[string]any{
			"files": []any{
				map[string]any{"path": "input.txt", "content": "runbook fixture"},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:     "stdout-contains",
			Contains: "runbook fixture",
		}},
	}

	result := NewRunner(executor).Run(context.Background(), tools, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if executor.request.TemplateID != "cat.read" {
		t.Fatalf("TemplateID = %q, want cat.read", executor.request.TemplateID)
	}
}

// TestRunMockedRunbookPresetValidatesResolvedInputSchema verifies presets.
func TestRunMockedRunbookPresetValidatesResolvedInputSchema(t *testing.T) {
	tools := schema.Tools{
		LocalExec: schema.LocalExec{Commands: []schema.LocalExecCommand{{
			Name: "cat",
			Operations: []schema.CommandOperation{{
				Name: "read",
				InputSchema: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"path": map[string]any{"type": "string"},
					},
				},
			}},
		}}},
		NodePresets: []schema.NodePreset{{
			ID:     "cat_read",
			Action: "command.execute",
			Arguments: map[string]any{
				"template_id": "cat.read",
				"parameters": map[string]any{
					"path": "${path}",
				},
			},
		}},
	}
	validation := schema.ToolValidation{
		ID:   "cat_bad_path_type",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:     "runbook-node",
			PresetID: "cat_read",
		},
		Input: map[string]any{"path": 1},
		Mocks: map[string]any{
			"command.execute": map[string]any{"status": "succeeded"},
		},
		Assertions: []schema.ValidationAssertion{{Type: "status", Equals: "succeeded"}},
	}

	result := NewRunner(nil).Run(context.Background(), tools, validation)
	if result.Status != StatusFailed {
		t.Fatalf("Run() status = %q, want failed", result.Status)
	}
	if len(result.Assertions) != 1 || result.Assertions[0].Type != "input-schema" || result.Assertions[0].Passed {
		t.Fatalf("Assertions = %#v, want failed input-schema assertion", result.Assertions)
	}
	actual, ok := result.Assertions[0].Actual.(map[string]any)
	if !ok || actual["path"] != 1 {
		t.Fatalf("Actual = %#v, want resolved numeric path", result.Assertions[0].Actual)
	}
}

// TestRunLiveRunbookNodeUsesCommandOperation verifies operations work without presets.
func TestRunLiveRunbookNodeUsesCommandOperation(t *testing.T) {
	executor := &fixtureCommandExecutor{}
	validation := schema.ToolValidation{
		ID:   "cat_runbook_operation_live",
		Mode: "live",
		Target: schema.ToolValidationTarget{
			Type:      "runbook-node",
			Command:   "cat",
			Operation: "read",
		},
		Input: map[string]any{"path": "input.txt"},
		Fixtures: map[string]any{
			"files": []any{
				map[string]any{"path": "input.txt", "content": "runbook operation fixture"},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:     "stdout-contains",
			Contains: "runbook operation fixture",
		}},
	}

	result := NewRunner(executor).Run(context.Background(), schema.Tools{}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if result.Target.TemplateID != "cat.read" || result.Target.Boundary != "command.execute" {
		t.Fatalf("Target = %#v, want command.execute cat.read", result.Target)
	}
	if executor.request.TemplateID != "cat.read" {
		t.Fatalf("TemplateID = %q, want cat.read", executor.request.TemplateID)
	}
}

// TestRunMockedRunbookNodeUsesMCPBoundary verifies MCP runbook checks are portable.
func TestRunMockedRunbookNodeUsesMCPBoundary(t *testing.T) {
	validation := schema.ToolValidation{
		ID:   "memory_search_runbook_mocked",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "runbook-node",
			MCPServer: "memory",
			MCPTool:   "search_memory",
		},
		Mocks: map[string]any{
			"mcp.call": map[string]any{
				"status": "succeeded",
				"output": map[string]any{"count": 1},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:   "json-path",
			Path:   "output.count",
			Equals: 1,
		}},
	}

	result := NewRunner(nil).Run(context.Background(), schema.Tools{}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if result.Target.Boundary != "mcp.call" {
		t.Fatalf("Boundary = %q, want mcp.call", result.Target.Boundary)
	}
}

// TestRunMockedRunbookNodeRecordsCommandEnvelope verifies node request wiring.
func TestRunMockedRunbookNodeRecordsCommandEnvelope(t *testing.T) {
	validation := schema.ToolValidation{
		ID:   "grep_runbook_envelope",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "runbook-node",
			Command:   "grep",
			Operation: "recursive_search",
		},
		Input: map[string]any{"pattern": "needle", "path": "."},
		Mocks: map[string]any{
			"command.execute": map[string]any{
				"status":    "succeeded",
				"exit_code": 0,
				"stdout":    "./haystack.txt:1:needle",
			},
		},
		Assertions: []schema.ValidationAssertion{
			{Type: "json-path", Path: "output.request.template_id", Equals: "grep.recursive_search"},
			{Type: "json-path", Path: "output.request.parameters.pattern", Equals: "needle"},
			{Type: "stdout-contains", Contains: "needle"},
		},
	}

	result := NewRunner(nil).Run(context.Background(), schema.Tools{}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
}

// TestRunLiveMCPToolUsesMCPExecutor verifies live MCP boundary checks execute.
func TestRunLiveMCPToolUsesMCPExecutor(t *testing.T) {
	executor := &recordingMCPExecutor{
		output: map[string]any{"tool": "remember", "content": "saved"},
	}
	validation := schema.ToolValidation{
		ID:   "memory_remember_live",
		Mode: "live",
		Target: schema.ToolValidationTarget{
			Type:      "mcp-tool",
			MCPServer: "memory",
			MCPTool:   "remember",
		},
		Input: map[string]any{"content": "saved"},
		Assertions: []schema.ValidationAssertion{{
			Type:   "json-path",
			Path:   "output.tool",
			Equals: "remember",
		}},
	}

	result := NewRunnerWithMCP(nil, executor).Run(context.Background(), schema.Tools{}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if executor.request.ServerID != "memory" || executor.request.Tool != "remember" {
		t.Fatalf("request = %#v, want memory remember", executor.request)
	}
	if executor.request.Arguments["content"] != "saved" {
		t.Fatalf("arguments = %#v, want validation input", executor.request.Arguments)
	}
}

// TestRunLiveRunbookNodeUsesMCPAction verifies MCP runbook validations use mcp.call.
func TestRunLiveRunbookNodeUsesMCPAction(t *testing.T) {
	executor := &recordingMCPExecutor{
		output: map[string]any{"tool": "remember", "content": "runbook saved"},
	}
	tools := schema.Tools{
		NodePresets: []schema.NodePreset{{
			ID:     "memory_remember",
			Action: "mcp.call",
			Arguments: map[string]any{
				"server_id": "memory",
				"tool":      "remember",
				"arguments": map[string]any{
					"content": "${content}",
				},
			},
		}},
	}
	validation := schema.ToolValidation{
		ID:   "memory_remember_runbook_live",
		Mode: "live",
		Target: schema.ToolValidationTarget{
			Type:     "runbook-node",
			PresetID: "memory_remember",
		},
		Input: map[string]any{"content": "runbook saved"},
		Assertions: []schema.ValidationAssertion{{
			Type:   "json-path",
			Path:   "output.content",
			Equals: "runbook saved",
		}},
	}

	result := NewRunnerWithMCP(nil, executor).Run(context.Background(), tools, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if executor.request.ServerID != "memory" || executor.request.Tool != "remember" {
		t.Fatalf("request = %#v, want mcp.call memory remember", executor.request)
	}
	if executor.request.Arguments["content"] != "runbook saved" {
		t.Fatalf("arguments = %#v, want resolved validation input", executor.request.Arguments)
	}
}

// TestRunMockedValidationFailsAssertion verifies assertion failures are reported.
func TestRunMockedValidationFailsAssertion(t *testing.T) {
	validation := schema.ToolValidation{
		ID:   "grep_missing",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "grep",
			Operation: "recursive_search",
		},
		Mocks: map[string]any{
			"command.execute": map[string]any{
				"status":    "succeeded",
				"exit_code": 0,
				"stdout":    "haystack",
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:     "stdout-contains",
			Contains: "needle",
		}},
	}

	result := NewRunner(nil).Run(context.Background(), schema.Tools{Validations: []schema.ToolValidation{validation}}, validation)
	if result.Status != StatusFailed {
		t.Fatalf("Run() status = %q, want failed", result.Status)
	}
	if len(result.Assertions) != 1 || result.Assertions[0].Passed {
		t.Fatalf("Assertions = %#v, want failed stdout assertion", result.Assertions)
	}
}

// TestRunMockedValidationSupportsExitCodeComparisons verifies numeric exit checks.
func TestRunMockedValidationSupportsExitCodeComparisons(t *testing.T) {
	validation := schema.ToolValidation{
		ID:   "grep_exit_code",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "grep",
			Operation: "recursive_search",
		},
		Mocks: map[string]any{
			"command.execute": map[string]any{
				"status":    "failed",
				"exit_code": 1,
			},
		},
		Assertions: []schema.ValidationAssertion{
			{Type: "exit-code-not-equals", Equals: 0},
			{Type: "exit-code-greater-than", Equals: 0},
			{Type: "exit-code-less-than", Equals: 2},
		},
	}

	result := NewRunner(nil).Run(context.Background(), schema.Tools{Validations: []schema.ToolValidation{validation}}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
}

// TestRunMockedValidationFailsEmptyContains verifies assertions are meaningful.
func TestRunMockedValidationFailsEmptyContains(t *testing.T) {
	validation := schema.ToolValidation{
		ID:   "grep_empty",
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "grep",
			Operation: "recursive_search",
		},
		Mocks: map[string]any{
			"command.execute": map[string]any{
				"status":    "succeeded",
				"exit_code": 0,
				"stdout":    "haystack",
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type: "stdout-contains",
		}},
	}

	result := NewRunner(nil).Run(context.Background(), schema.Tools{Validations: []schema.ToolValidation{validation}}, validation)
	if result.Status != StatusFailed || len(result.Assertions) != 1 || result.Assertions[0].Passed {
		t.Fatalf("Run() = %#v, want empty contains assertion failure", result)
	}
}

// TestRunMockedAgentToolCallValidation verifies agent selection checks are portable.
func TestRunMockedAgentToolCallValidation(t *testing.T) {
	validation := schema.ToolValidation{
		ID:     "agent_uses_rg",
		Mode:   "mocked",
		Prompt: "Find TODO comments.",
		Target: schema.ToolValidationTarget{
			Type:      "agent-tool-call",
			Command:   "rg",
			Operation: "search_text",
		},
		Mocks: map[string]any{
			"agent.tool_call": map[string]any{
				"status": "succeeded",
				"output": map[string]any{
					"tool_name": "command_execute",
					"arguments": map[string]any{"template_id": "rg.search_text"},
				},
			},
		},
		Assertions: []schema.ValidationAssertion{{
			Type:   "json-path",
			Path:   "output.arguments.template_id",
			Equals: "rg.search_text",
		}},
	}

	result := NewRunner(nil).Run(context.Background(), schema.Tools{Validations: []schema.ToolValidation{validation}}, validation)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if result.Target.Boundary != "agent.tool_call" {
		t.Fatalf("Boundary = %q, want agent.tool_call", result.Target.Boundary)
	}
}

// TestRunLiveAgentToolCallValidationUsesAgentHost verifies live direct-agent checks.
func TestRunLiveAgentToolCallValidationUsesAgentHost(t *testing.T) {
	host := &recordingAgentHost{
		response: agentvalidation.Response{
			Text: "Searching with rg.",
			ToolCalls: []agentvalidation.ToolCall{{
				Name: "command_execute",
				Arguments: map[string]any{
					"template_id": "rg.search_text",
					"query":       "TODO",
				},
			}},
		},
	}
	validation := schema.ToolValidation{
		ID:     "agent_uses_rg_live",
		Mode:   "live",
		Prompt: "Find TODO comments.",
		Target: schema.ToolValidationTarget{
			Type:      "agent-tool-call",
			Command:   "rg",
			Operation: "search_text",
		},
		Input: map[string]any{"query": "TODO"},
		Assertions: []schema.ValidationAssertion{
			{
				Type:   "json-path",
				Path:   "output.tool_calls.0.arguments.template_id",
				Equals: "rg.search_text",
			},
			{
				Type:   "json-path",
				Path:   "output.tool_calls.0.arguments.query",
				Equals: "TODO",
			},
		},
	}

	result := NewRunnerWithAgentHost(nil, schema.Agent{Name: "Configured agent"}, host).Run(
		context.Background(),
		schema.Tools{Validations: []schema.ToolValidation{validation}},
		validation,
	)
	if result.Status != StatusPassed {
		t.Fatalf("Run() status = %q diagnostics = %#v assertions = %#v", result.Status, result.Diagnostics, result.Assertions)
	}
	if host.request.Agent.Name != "Configured agent" {
		t.Fatalf("Agent = %#v, want configured agent", host.request.Agent)
	}
	if host.request.Prompt != "Find TODO comments." {
		t.Fatalf("Prompt = %q, want validation prompt", host.request.Prompt)
	}
	if result.Command == nil || result.Command.Status != "succeeded" {
		t.Fatalf("Command = %#v, want succeeded evidence", result.Command)
	}
}

// mockedValidation creates a passing command-operation validation fixture.
func mockedValidation(id string) schema.ToolValidation {
	return schema.ToolValidation{
		ID:   id,
		Mode: "mocked",
		Target: schema.ToolValidationTarget{
			Type:      "command-operation",
			Command:   "test",
			Operation: id,
		},
		Mocks: map[string]any{
			"command.execute": map[string]any{
				"status":    "succeeded",
				"exit_code": 0,
			},
		},
		Expected: map[string]any{"status": "succeeded"},
	}
}

// missingCoverage reports whether one missing coverage item is present.
func missingCoverage(items []CoverageItem, itemType string, id string) bool {
	for _, item := range items {
		if item.Type == itemType && item.ID == id {
			return true
		}
	}
	return false
}

// recordingCommandExecutor records one command execution request.
type recordingCommandExecutor struct {
	request command.ExecuteRequest
	result  command.StatusResult
}

// Execute records the request and returns the configured status.
func (e *recordingCommandExecutor) Execute(_ context.Context, req command.ExecuteRequest) (command.StatusResult, error) {
	e.request = req
	return e.result, nil
}

// fixtureCommandExecutor reads the requested fixture path from the validation cwd.
type fixtureCommandExecutor struct {
	workingDir string
	request    command.ExecuteRequest
}

// Execute returns the fixture file content as command stdout.
func (e *fixtureCommandExecutor) Execute(_ context.Context, req command.ExecuteRequest) (command.StatusResult, error) {
	e.workingDir = req.WorkingDir
	e.request = req
	content, err := os.ReadFile(filepath.Join(req.WorkingDir, req.Parameters["path"].(string)))
	if err != nil {
		return command.StatusResult{Status: "failed", ExitCode: 1, Error: err.Error()}, err
	}
	return command.StatusResult{Status: "succeeded", ExitCode: 0, StdoutTail: string(content)}, nil
}

// recordingAgentHost records one live agent validation request.
type recordingAgentHost struct {
	request  agentvalidation.Request
	response agentvalidation.Response
}

// Respond records the request and returns the configured response.
func (h *recordingAgentHost) Respond(_ context.Context, req agentvalidation.Request) (agentvalidation.Response, error) {
	h.request = req
	return h.response, nil
}

// recordingMCPExecutor records one MCP validation request.
type recordingMCPExecutor struct {
	request actions.MCPRequest
	output  map[string]any
}

// CallMCP records the request and returns the configured output.
func (e *recordingMCPExecutor) CallMCP(_ context.Context, req actions.MCPRequest) (map[string]any, error) {
	e.request = req
	return e.output, nil
}

// repoRoot returns the repository root for fixture loading.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", ".."))
}
