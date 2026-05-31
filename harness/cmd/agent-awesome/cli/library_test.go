// This file tests shared package-library validation CLI commands.
package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/agentvalidation"
	"agentawesome/internal/services/toolvalidation"
)

// TestLibraryValidateWritesCombinedSummary verifies one command validates agents and tools.
func TestLibraryValidateWritesCombinedSummary(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "research")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "linux")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-agent-validations", "--require-tool-coverage"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Library validations: total=2 passed=2 failed=0 unsupported=0") ||
		!strings.Contains(got, "agents "+filepath.Join(root, "agents")+": total=1 passed=1 failed=0 unsupported=0 cases=1 passed=1 failed=0 unsupported=0") ||
		!strings.Contains(got, "tools "+filepath.Join(root, "tools")+": packages=1 passed=1 failed=0 unsupported=0 total=1 passed=1 failed=0 unsupported=0 coverage=1/1 missing=0") {
		t.Fatalf("stdout = %q, want combined summary", got)
	}
}

// TestLibraryValidateJSONWritesMachineReadableResult verifies combined JSON output.
func TestLibraryValidateJSONWritesMachineReadableResult(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "network")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	var decoded libraryValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Total != 2 || decoded.Passed != 2 || decoded.Agents == nil || decoded.Tools == nil {
		t.Fatalf("decoded = %#v, want agent and tool results", decoded)
	}
}

// TestLibraryValidateIncludesMCPPackages verifies shared MCP package libraries run.
func TestLibraryValidateIncludesMCPPackages(t *testing.T) {
	root := t.TempDir()
	mcpPath := writeTestMCPPackage(t, filepath.Join(root, "mcp"), "memory")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-tool-coverage", "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	var decoded libraryValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Total != 1 || decoded.Passed != 1 || decoded.Tools == nil || decoded.MCPDir != filepath.Join(root, "mcp") {
		t.Fatalf("decoded = %#v, want one passing MCP package library", decoded)
	}
	if got := decoded.Tools.Packages[0].Path; got != mcpPath {
		t.Fatalf("MCP package path = %q, want %q", got, mcpPath)
	}
}

// TestLibraryValidateWritesJUnitReport verifies a single CI report covers both package types.
func TestLibraryValidateWritesJUnitReport(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "network")
	path := filepath.Join(t.TempDir(), "library-validations.xml")
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--junit", path})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 3 || report.Failures != 0 || len(report.Suites) != 2 {
		t.Fatalf("report = %#v, want agent load, agent validation, and tool validation", report)
	}
}

// TestLibraryValidateWritesArtifactsForSetupError verifies required sources are reported.
func TestLibraryValidateWritesArtifactsForSetupError(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(t.TempDir(), "library-validations.xml")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{
		"validate",
		"--root", root,
		"--require-tool-coverage",
		"--json",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "required tool package directory not found") {
		t.Fatalf("Execute() error = %v, want required tool directory failure", err)
	}
	var decoded libraryValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Failed != 1 || !strings.Contains(decoded.Error, "required tool package directory not found") {
		t.Fatalf("decoded = %#v, want setup failure JSON", decoded)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 || len(report.Suites) != 1 {
		t.Fatalf("report = %#v, want one setup failure", report)
	}
	if got := report.Suites[0].TestCases[0]; got.Name != "library.setup" ||
		got.Failure == nil ||
		!strings.Contains(got.Failure.Text, "required tool package directory not found") {
		t.Fatalf("setup testcase = %#v, want setup failure evidence", got)
	}
}

// TestLibraryValidateJUnitIncludesAgentToolContractFailures verifies contract evidence.
func TestLibraryValidateJUnitIncludesAgentToolContractFailures(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	path := filepath.Join(t.TempDir(), "library-validations.xml")
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		toolCallingAgentLoader("command:missing.search"),
		toolCallValidator("command:rg.search_text"),
	)
	cmd.SetArgs([]string{
		"validate",
		"--root", root,
		"--require-agent-tool-contracts",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want unknown tool-call failure", err)
	}
	report := readJUnitReport(t, path)
	if report.Failures != 1 {
		t.Fatalf("report = %#v, want one contract failure", report)
	}
	if !junitReportContainsFailure(report, "command:missing.search") ||
		!junitReportContainsFailure(report, "not declared by packaged tools") {
		t.Fatalf("report = %#v, want unknown tool-call contract evidence", report)
	}
}

// writeTestMCPPackage creates one package-shaped mcp.yaml file.
func writeTestMCPPackage(t *testing.T, root string, name string) string {
	t.Helper()
	path := filepath.Join(root, name, schema.DefaultMCPFilename)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(path, []byte("mcp:\n  enabled: false\n"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	return path
}

// TestLibraryValidateRequireToolCoverageFails verifies library coverage gates.
func TestLibraryValidateRequireToolCoverageFails(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
			return toolvalidation.SuiteResult{
				Total:  1,
				Passed: 1,
				Coverage: toolvalidation.Coverage{
					Required: 1,
					Missing: []toolvalidation.CoverageItem{{
						Type: "runbook-node",
						ID:   "rg.search_text",
					}},
				},
			}, nil
		},
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-tool-coverage"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want coverage failure", err)
	}
}

// TestLibraryValidateRequireToolInputSchemasFails verifies library schema gates.
func TestLibraryValidateRequireToolInputSchemasFails(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
			return toolvalidation.SuiteResult{
				Total:  1,
				Passed: 1,
				InputSchemaCoverage: toolvalidation.Coverage{
					Required: 1,
					Missing: []toolvalidation.CoverageItem{{
						Type: "command-operation-input-schema",
						ID:   "rg.search_text",
					}},
				},
			}, nil
		},
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-tool-input-schemas"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want input schema failure", err)
	}
}

// TestLibraryValidateRequireToolAssertionsFails verifies tool assertion gates.
func TestLibraryValidateRequireToolAssertionsFails(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
			return toolvalidation.SuiteResult{
				Total:  1,
				Passed: 1,
				Results: []toolvalidation.Result{{
					ID:     "rg_search_text_mocked",
					Status: toolvalidation.StatusPassed,
					Assertions: []toolvalidation.AssertionResult{{
						Type:   "configured",
						Passed: true,
					}},
				}},
			}, nil
		},
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--agent-dir", "", "--require-tool-assertions"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing assertion failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "tool validations without assertions: rg_search_text_mocked") ||
		!strings.Contains(got, "assertions_missing=1") {
		t.Fatalf("stdout = %q, want missing assertion summary", got)
	}
}

// TestLibraryValidateRequireAgentDirectoryFails verifies CI does not skip agents.
func TestLibraryValidateRequireAgentDirectoryFails(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-agent-validations"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "required agent package directory not found") {
		t.Fatalf("Execute() error = %v, want missing required agent directory", err)
	}
}

// TestLibraryValidateRequireToolDirectoryFails verifies CI does not skip tools.
func TestLibraryValidateRequireToolDirectoryFails(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-tool-coverage"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "required tool package directory not found") {
		t.Fatalf("Execute() error = %v, want missing required tool directory", err)
	}
}

// TestLibraryValidateRequireAgentAssertionsFails verifies shared library gates.
func TestLibraryValidateRequireAgentAssertionsFails(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		placeholderAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-agent-assertions"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing assertion failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations without assertions: answers") ||
		!strings.Contains(got, "cases=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want missing assertion summary", got)
	}
}

// TestLibraryValidateRequireAgentToolCallsFails verifies tool-use evidence gates.
func TestLibraryValidateRequireAgentToolCallsFails(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--tool-dir", "", "--require-agent-tool-calls"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing tool-call failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations without tool calls: Agent") ||
		!strings.Contains(got, "cases=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want missing tool-call summary", got)
	}
}

// TestLibraryValidateRequireAgentToolCallsPasses verifies proved tool use passes.
func TestLibraryValidateRequireAgentToolCallsPasses(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:rg.search_text"),
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--tool-dir", "", "--require-agent-tool-calls"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Library validations: total=1 passed=1 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want passing agent-only library summary", got)
	}
}

// TestLibraryValidateRequireAgentToolContractsFails verifies agent/tool links.
func TestLibraryValidateRequireAgentToolContractsFails(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:missing.search"),
		toolCallValidator("command:rg.search_text"),
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-agent-tool-contracts"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want unknown tool call failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations with unknown tool calls: uses_search: command:missing.search") ||
		!strings.Contains(got, "cases=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want unknown tool-call summary", got)
	}
}

// TestLibraryValidateRequireAgentToolContractsPasses verifies packaged links pass.
func TestLibraryValidateRequireAgentToolContractsPasses(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:rg.search_text"),
		toolCallValidator("command:rg.search_text"),
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-agent-tool-contracts"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Library validations: total=2 passed=2 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want passing library summary", got)
	}
}

// TestLibraryValidateAcceptsSingleConfigFiles verifies active config files can be gated.
func TestLibraryValidateAcceptsSingleConfigFiles(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "agent.yaml"), []byte("name: test\n"), 0o600); err != nil {
		t.Fatalf("write agent.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "tool.yaml"), []byte("name: tools\n"), 0o600); err != nil {
		t.Fatalf("write tool.yaml: %v", err)
	}
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:rg.search_text"),
		toolCallValidator("command:rg.search_text"),
	)
	cmd.SetArgs([]string{
		"validate",
		"--root", root,
		"--agent", "agent.yaml",
		"--tool", "tool.yaml",
		"--require-agent-validations",
		"--require-agent-assertions",
		"--require-agent-tool-calls",
		"--require-agent-tool-contracts",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Library validations: total=2 passed=2 failed=0 unsupported=0") ||
		!strings.Contains(got, filepath.Join(root, "agent.yaml")) ||
		!strings.Contains(got, filepath.Join(root, "tool.yaml")) {
		t.Fatalf("stdout = %q, want single-file library summary", got)
	}
}

// TestLibraryValidateRejectsToolAndMCPDir verifies explicit files own the tool source.
func TestLibraryValidateRejectsToolAndMCPDir(t *testing.T) {
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{
		"validate",
		"--root", t.TempDir(),
		"--tool", "tool.yaml",
		"--mcp-dir", "mcp",
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "--tool and --mcp-dir cannot be combined") {
		t.Fatalf("Execute() error = %v, want tool/mcp-dir conflict", err)
	}
}

// TestLibraryValidateLiveAgentsUsesInjectedRunner verifies library live runtime wiring.
func TestLibraryValidateLiveAgentsUsesInjectedRunner(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	host := cliLiveAgentHost{
		response: agentvalidation.Response{Text: "live done"},
	}
	var gotOpts libraryValidationOptions
	cleanupCalled := false
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidatorsAndAgentRunner(
		context.Background(),
		&stdout,
		liveAgentLoader,
		passingToolValidator,
		func(_ context.Context, opts libraryValidationOptions) (*agentvalidation.Runner, func(), error) {
			gotOpts = opts
			return agentvalidation.NewRunnerWithHost(&host), func() { cleanupCalled = true }, nil
		},
	)
	cmd.SetArgs([]string{
		"validate",
		"--root", root,
		"--live-agents",
		"--model", "model.yaml",
		"--runtime-tool", "runtime-tool.yaml",
	})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v output = %q", err, stdout.String())
	}
	if !gotOpts.LiveAgents || gotOpts.Runtime.ModelConfigPath != "model.yaml" || gotOpts.RuntimeToolPath != "runtime-tool.yaml" {
		t.Fatalf("opts = %#v, want live agent runtime flags", gotOpts)
	}
	if !cleanupCalled {
		t.Fatalf("cleanup was not called")
	}
	if host.request.Prompt != "Answer live." {
		t.Fatalf("live request = %#v, want prompt from library agent validation", host.request)
	}
	if got := stdout.String(); !strings.Contains(got, "Library validations: total=2 passed=2 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want passing live library summary", got)
	}
}

// TestLibraryValidateToolModePassesFilter verifies library tool lane selection.
func TestLibraryValidateToolModePassesFilter(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, filepath.Join(root, "tools"), "search")
	var gotMode string
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		func(_ context.Context, _ string, _ []string, mode string) (toolvalidation.SuiteResult, error) {
			gotMode = mode
			return toolvalidation.SuiteResult{Total: 1, Passed: 1}, nil
		},
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--tool-mode", "mocked"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if gotMode != "mocked" {
		t.Fatalf("tool mode = %q, want mocked", gotMode)
	}
}

// TestLibraryToolRuntimeAgentPathResolvesExplicitPath verifies live tool config.
func TestLibraryToolRuntimeAgentPathResolvesExplicitPath(t *testing.T) {
	root := t.TempDir()
	opts := libraryValidationOptions{
		Root:             root,
		AgentPath:        "agents/pkg/agent.yaml",
		RuntimeAgentPath: "runtime/agent.yaml",
	}

	path := libraryToolRuntimeAgentPath(root, opts)
	if path != filepath.Join(root, "runtime", "agent.yaml") {
		t.Fatalf("runtime agent path = %q, want explicit runtime agent path", path)
	}
}

// TestLibraryToolRuntimeAgentPathDefaultsToSingleAgent verifies package fallback.
func TestLibraryToolRuntimeAgentPathDefaultsToSingleAgent(t *testing.T) {
	root := t.TempDir()
	opts := libraryValidationOptions{
		Root:      root,
		AgentPath: "agent.yaml",
	}

	path := libraryToolRuntimeAgentPath(root, opts)
	if path != filepath.Join(root, "agent.yaml") {
		t.Fatalf("runtime agent path = %q, want single-agent source path", path)
	}
}

// TestLibraryToolValidationNeedsRuntimeForSingleAgent verifies live fallback wiring.
func TestLibraryToolValidationNeedsRuntimeForSingleAgent(t *testing.T) {
	cmd := newLibraryValidateCommand(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
		defaultLibraryAgentValidationRunner,
	)
	opts := libraryValidationOptions{
		ToolMode:  "live",
		AgentPath: "agent.yaml",
	}

	if !libraryToolValidationNeedsRuntime(cmd, opts) {
		t.Fatalf("libraryToolValidationNeedsRuntime() = false, want true for live single-agent source")
	}
	opts.ToolMode = "mocked"
	if libraryToolValidationNeedsRuntime(cmd, opts) {
		t.Fatalf("libraryToolValidationNeedsRuntime() = true, want false for mocked lane")
	}
}

// TestLibraryValidateAgentModeMockedSkipsLivePlaceholders verifies CI lane filters.
func TestLibraryValidateAgentModeMockedSkipsLivePlaceholders(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		func(string) (schema.Agent, error) {
			return mixedModeAgent(), nil
		},
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--agent-mode", "mocked", "--require-agent-assertions"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v output = %q", err, stdout.String())
	}
	if got := stdout.String(); !strings.Contains(got, "cases=1 passed=1 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want only mocked agent validation to run", got)
	}
}

// TestLibraryValidateRequireAgentToolContractsFailsInvalidArguments verifies schemas.
func TestLibraryValidateRequireAgentToolContractsFailsInvalidArguments(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, filepath.Join(root, "agents"), "support")
	writeTestToolPackage(t, filepath.Join(root, "tools"), "archive")
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		toolCallingAgentLoaderWithArgs("command:tar.create_archive", map[string]any{
			"archive_path": "bundle.tar",
		}),
		toolCallValidatorWithSchema("command:tar.create_archive", map[string]any{
			"type":     "object",
			"required": []any{"archive_path", "sources"},
			"properties": map[string]any{
				"archive_path": map[string]any{"type": "string"},
				"sources":      map[string]any{"type": "array"},
			},
		}),
	)
	cmd.SetArgs([]string{"validate", "--root", root, "--require-agent-tool-contracts"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want invalid arguments failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations with invalid tool arguments: uses_search: command:tar.create_archive") ||
		!strings.Contains(got, "cases=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want invalid tool argument summary", got)
	}
}

// TestLibraryValidateSingleToolPackageErrorsIncludeExpandableResult verifies UI evidence.
func TestLibraryValidateSingleToolPackageErrorsIncludeExpandableResult(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "tool.yaml"), []byte("name: tools\n"), 0o600); err != nil {
		t.Fatalf("write tool.yaml: %v", err)
	}
	var stdout bytes.Buffer
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&stdout,
		passingAgentLoader,
		func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
			return toolvalidation.SuiteResult{}, errors.New("bad package")
		},
	)
	cmd.SetArgs([]string{
		"validate",
		"--root", root,
		"--agent-dir", "",
		"--tool", "tool.yaml",
		"--json",
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want failed package error", err)
	}
	var decoded libraryValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Tools == nil || decoded.Tools.Total != 1 || decoded.Tools.Failed != 1 || len(decoded.Tools.Packages) != 1 {
		t.Fatalf("decoded = %#v, want failed tool package counted as one validation", decoded)
	}
	result := decoded.Tools.Packages[0].Result
	if result.Failed != 1 || len(result.Results) != 1 ||
		result.Results[0].ID != "package.load" ||
		len(result.Results[0].Diagnostics) != 1 ||
		!strings.Contains(result.Results[0].Diagnostics[0].Message, "bad package") {
		t.Fatalf("package result = %#v, want expandable package.load diagnostics", result)
	}
}

// TestLibraryValidateRequireAgentToolContractsNeedsBothDirs verifies setup.
func TestLibraryValidateRequireAgentToolContractsNeedsBothDirs(t *testing.T) {
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", t.TempDir(), "--agent-dir", "", "--require-agent-tool-contracts"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "requires both agent and tool package sources") {
		t.Fatalf("Execute() error = %v, want directory requirement error", err)
	}
}

// TestLibraryValidateNoPackageDirsFails verifies empty library roots fail clearly.
func TestLibraryValidateNoPackageDirsFails(t *testing.T) {
	cmd := newLibraryCommandWithValidators(
		context.Background(),
		&bytes.Buffer{},
		passingAgentLoader,
		passingToolValidator,
	)
	cmd.SetArgs([]string{"validate", "--root", t.TempDir()})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "no agent or tool package sources") {
		t.Fatalf("Execute() error = %v, want missing package directories error", err)
	}
}

// TestRootCommandIncludesLibraryValidate verifies the public CLI exposes library validation.
func TestRootCommandIncludesLibraryValidate(t *testing.T) {
	root := NewRootCommand(context.Background())
	library, _, err := root.Find([]string{"library", "validate"})
	if err != nil {
		t.Fatalf("Find() error = %v", err)
	}
	if library == nil || library.Name() != "validate" {
		t.Fatalf("library validate command = %#v, want validate command", library)
	}
}

// passingAgentLoader returns one agent package with a mocked behavior validation.
func passingAgentLoader(string) (schema.Agent, error) {
	return schema.Agent{
		Name:        "Agent",
		Instruction: "Do the work.",
		Validations: []schema.AgentValidation{{
			ID:     "answers",
			Prompt: "Answer.",
			Mocks: map[string]any{
				"agent.response": map[string]any{"text": "done"},
			},
			Assertions: []schema.ValidationAssertion{{
				Type:     "response-contains",
				Contains: "done",
			}},
		}},
	}, nil
}

// placeholderAgentLoader returns one agent package with no real assertions.
func placeholderAgentLoader(string) (schema.Agent, error) {
	return schema.Agent{
		Name:        "Agent",
		Instruction: "Do the work.",
		Validations: []schema.AgentValidation{{
			ID:     "answers",
			Prompt: "Answer.",
			Mocks: map[string]any{
				"agent.response": map[string]any{"text": "done"},
			},
		}},
	}, nil
}

// liveAgentLoader returns one agent package with a live behavior validation.
func liveAgentLoader(string) (schema.Agent, error) {
	return schema.Agent{
		Name:        "Agent",
		Instruction: "Do the live work.",
		Validations: []schema.AgentValidation{{
			ID:     "answers_live",
			Mode:   "live",
			Prompt: "Answer live.",
			Assertions: []schema.ValidationAssertion{{
				Type:     "response-contains",
				Contains: "live done",
			}},
		}},
	}, nil
}

// toolCallingAgentLoader returns an agent package that asserts one tool call.
func toolCallingAgentLoader(toolID string) agentValidationLoader {
	return toolCallingAgentLoaderWithArgs(toolID, nil)
}

// toolCallingAgentLoaderWithArgs returns an agent package with one tool call.
func toolCallingAgentLoaderWithArgs(toolID string, arguments map[string]any) agentValidationLoader {
	return func(string) (schema.Agent, error) {
		call := map[string]any{"id": toolID}
		if len(arguments) > 0 {
			call["arguments"] = arguments
		}
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Use tools when useful.",
			Validations: []schema.AgentValidation{{
				ID:     "uses_search",
				Prompt: "Search the workspace.",
				Mocks: map[string]any{
					"agent.response": map[string]any{
						"text": "searched",
						"tool_calls": []any{
							call,
						},
					},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:   "tool-call",
					Equals: toolID,
				}},
			}},
		}, nil
	}
}

// passingToolValidator returns one passing tool validation with full coverage.
func passingToolValidator(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
	return toolvalidation.SuiteResult{
		Total:    1,
		Passed:   1,
		Coverage: toolvalidation.Coverage{Required: 1, Covered: 1},
		Results: []toolvalidation.Result{{
			ID:     "tool_check",
			Status: toolvalidation.StatusPassed,
		}},
	}, nil
}

// toolCallValidator returns one package exposing one agent-call contract.
func toolCallValidator(toolID string) toolValidationRunner {
	return toolCallValidatorWithSchema(toolID, nil)
}

// toolCallValidatorWithSchema returns one package exposing one input contract.
func toolCallValidatorWithSchema(toolID string, inputSchema map[string]any) toolValidationRunner {
	return func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{
			Total:          1,
			Passed:         1,
			Coverage:       toolvalidation.Coverage{Required: 1, Covered: 1},
			AgentToolCalls: []string{toolID},
			AgentToolContracts: map[string]toolvalidation.AgentToolContract{
				toolID: {ID: toolID, InputSchema: inputSchema},
			},
			Results: []toolvalidation.Result{{
				ID:     "tool_check",
				Status: toolvalidation.StatusPassed,
			}},
		}, nil
	}
}

// junitReportContainsFailure reports whether any failure contains text.
func junitReportContainsFailure(report junitSuites, text string) bool {
	for _, suite := range report.Suites {
		for _, testCase := range suite.TestCases {
			if testCase.Failure == nil {
				continue
			}
			if strings.Contains(testCase.Failure.Text, text) ||
				strings.Contains(testCase.Failure.Message, text) {
				return true
			}
		}
	}
	return false
}
