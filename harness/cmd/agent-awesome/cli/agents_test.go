// This file tests agent configuration validation CLI commands.
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
)

// TestAgentsValidateWritesSummary verifies human-readable validation output.
func TestAgentsValidateWritesSummary(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(path string) (schema.Agent, error) {
		if path != "custom-agent.yaml" {
			t.Fatalf("agent path = %q, want custom-agent.yaml", path)
		}
		return schema.Agent{Name: "Research agent", Instruction: "Research carefully."}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "custom-agent.yaml"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Agent validations: total=1 passed=1 failed=0") ||
		!strings.Contains(got, "passed custom-agent.yaml - Research agent") {
		t.Fatalf("stdout = %q, want validation summary", got)
	}
}

// TestAgentsValidateFailsInvalidAgent verifies invalid configs fail after reporting.
func TestAgentsValidateFailsInvalidAgent(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
		return schema.Agent{}, errors.New("agent instruction must not be empty")
	})
	cmd.SetArgs([]string{"validate", "--agent", "broken-agent.yaml"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want failed validation error", err)
	}
	if got := stdout.String(); !strings.Contains(got, "failed broken-agent.yaml - agent instruction must not be empty") {
		t.Fatalf("stdout = %q, want invalid agent detail", got)
	}
}

// TestAgentsValidateDirectoryFindsNestedAgents verifies GitHub-style library trees.
func TestAgentsValidateDirectoryFindsNestedAgents(t *testing.T) {
	root := t.TempDir()
	rootAgent := writeTestAgentPackage(t, root, ".")
	nested := writeTestAgentPackage(t, root, filepath.Join("support", "research"))
	generated := writeTestAgentPackage(t, root, filepath.Join("build", "ignored"))
	hidden := writeTestAgentPackage(t, root, filepath.Join(".cache", "ignored"))

	paths, err := agentConfigPaths(root)
	if err != nil {
		t.Fatalf("agentConfigPaths() error = %v", err)
	}
	if got, want := strings.Join(paths, ","), strings.Join([]string{rootAgent, nested}, ","); got != want {
		t.Fatalf("paths = %#v, want root and nested packages without generated dirs; generated=%q hidden=%q", paths, generated, hidden)
	}
}

// TestAgentsValidateDirectoryFindsDirectCollectionFiles verifies app-managed
// agent collections are validated even when files are not named agent.yaml.
func TestAgentsValidateDirectoryFindsDirectCollectionFiles(t *testing.T) {
	root := t.TempDir()
	direct := filepath.Join(root, "agent-awesome-agent.yaml")
	nested := writeTestAgentPackage(t, root, filepath.Join("support", "research"))
	if err := os.WriteFile(direct, []byte("name: Agent Awesome\ninstruction: Help.\n"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	ignoredNested := filepath.Join(root, "support", "metadata.yaml")
	if err := os.WriteFile(ignoredNested, []byte("name: metadata\n"), 0o600); err != nil {
		t.Fatalf("WriteFile(metadata) error = %v", err)
	}

	paths, err := agentConfigPaths(root)
	if err != nil {
		t.Fatalf("agentConfigPaths() error = %v", err)
	}
	if got, want := strings.Join(paths, ","), strings.Join([]string{direct, nested}, ","); got != want {
		t.Fatalf("paths = %#v, want direct app agent and nested package; ignored=%q", paths, ignoredNested)
	}
}

// TestAgentsValidateDirectoryWritesSummary verifies library-wide validation output.
func TestAgentsValidateDirectoryWritesSummary(t *testing.T) {
	root := t.TempDir()
	alpha := writeTestAgentPackage(t, root, "alpha")
	beta := writeTestAgentPackage(t, root, "beta")
	seen := []string{}
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(path string) (schema.Agent, error) {
		seen = append(seen, path)
		return schema.Agent{Name: filepath.Base(filepath.Dir(path)), Instruction: "Do the work."}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent-dir", root})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if strings.Join(seen, ",") != strings.Join([]string{alpha, beta}, ",") {
		t.Fatalf("seen paths = %#v, want alpha then beta", seen)
	}
	if got := stdout.String(); !strings.Contains(got, "Agent validations: total=2 passed=2 failed=0") ||
		!strings.Contains(got, "passed "+alpha+" - alpha") ||
		!strings.Contains(got, "passed "+beta+" - beta") {
		t.Fatalf("stdout = %q, want library summary", got)
	}
}

// TestAgentsValidateDirectorySkipsUnmatchedSelections verifies library-wide selected reruns.
func TestAgentsValidateDirectorySkipsUnmatchedSelections(t *testing.T) {
	root := t.TempDir()
	alpha := writeTestAgentPackage(t, root, "alpha")
	beta := writeTestAgentPackage(t, root, "beta")
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(path string) (schema.Agent, error) {
		if path == alpha {
			return schema.Agent{
				Name:        "alpha",
				Instruction: "Do alpha work.",
				Validations: []schema.AgentValidation{{
					ID:     "alpha_validation",
					Prompt: "Answer.",
					Mocks: map[string]any{
						"agent.response": map[string]any{"text": "alpha"},
					},
				}},
			}, nil
		}
		if path != beta {
			t.Fatalf("path = %q, want %q or %q", path, alpha, beta)
		}
		return schema.Agent{
			Name:        "beta",
			Instruction: "Do beta work.",
			Validations: []schema.AgentValidation{{
				ID:     "beta_validation",
				Prompt: "Answer.",
				Mocks: map[string]any{
					"agent.response": map[string]any{"text": "beta"},
				},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent-dir", root, "--validation", "beta_validation"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); strings.Contains(got, alpha) ||
		!strings.Contains(got, "passed "+beta+" - beta: validations=1 passed=1 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want only matching package", got)
	}
}

// TestAgentsValidateDirectoryReportsMissingSelection verifies stale validation IDs fail clearly.
func TestAgentsValidateDirectoryReportsMissingSelection(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, root, "alpha")
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "alpha",
			Instruction: "Do alpha work.",
			Validations: []schema.AgentValidation{{
				ID:     "known_validation",
				Prompt: "Answer.",
				Mocks: map[string]any{
					"agent.response": map[string]any{"text": "known"},
				},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent-dir", root, "--validation", "missing_validation"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "missing_validation") {
		t.Fatalf("Execute() error = %v, want missing validation error", err)
	}
}

// TestAgentsValidateDirectoryMissingSelectionWritesArtifacts verifies stale IDs are reportable.
func TestAgentsValidateDirectoryMissingSelectionWritesArtifacts(t *testing.T) {
	root := t.TempDir()
	writeTestAgentPackage(t, root, "alpha")
	path := filepath.Join(t.TempDir(), "agent-validations.xml")
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "alpha",
			Instruction: "Do alpha work.",
			Validations: []schema.AgentValidation{{
				ID:     "known_validation",
				Prompt: "Answer.",
				Mocks: map[string]any{
					"agent.response": map[string]any{"text": "known"},
				},
			}},
		}, nil
	})
	cmd.SetArgs([]string{
		"validate",
		"--agent-dir", root,
		"--validation", "missing_validation",
		"--json",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "missing_validation") {
		t.Fatalf("Execute() error = %v, want missing validation error", err)
	}
	var decoded agentValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Failed != 1 || len(decoded.Agents) != 1 ||
		!strings.Contains(decoded.Agents[0].Error, "missing_validation") {
		t.Fatalf("decoded = %#v, want missing selection JSON evidence", decoded)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 ||
		!strings.Contains(report.Suites[0].TestCases[0].Failure.Text, "missing_validation") {
		t.Fatalf("report = %#v, want missing selection JUnit evidence", report)
	}
}

// TestAgentsValidateDirectorySetupErrorWritesArtifacts verifies empty trees report.
func TestAgentsValidateDirectorySetupErrorWritesArtifacts(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(t.TempDir(), "agent-validations.xml")
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, passingAgentLoader)
	cmd.SetArgs([]string{
		"validate",
		"--agent-dir", root,
		"--json",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "no agent config files found") {
		t.Fatalf("Execute() error = %v, want empty directory failure", err)
	}
	var decoded agentValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Failed != 1 || len(decoded.Agents) != 1 ||
		!strings.Contains(decoded.Agents[0].Error, "no agent config files found") {
		t.Fatalf("decoded = %#v, want setup failure JSON evidence", decoded)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 ||
		report.Suites[0].TestCases[0].Name != "agent.load" ||
		!strings.Contains(report.Suites[0].TestCases[0].Failure.Text, "no agent config files found") {
		t.Fatalf("report = %#v, want setup failure JUnit evidence", report)
	}
}

// TestAgentsValidateJSONWritesMachineReadableResult verifies JSON output.
func TestAgentsValidateJSONWritesMachineReadableResult(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
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
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	var decoded agentValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Total != 1 || decoded.Passed != 1 || decoded.ValidationTotal != 1 || decoded.ValidationPassed != 1 || len(decoded.Agents) != 1 || decoded.Agents[0].Name != "Agent" {
		t.Fatalf("decoded = %#v, want one passing agent", decoded)
	}
}

// TestAgentsValidateJSONReportsToolCallReferences verifies library metadata.
func TestAgentsValidateJSONReportsToolCallReferences(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Do the work.",
			Validations: []schema.AgentValidation{{
				ID:     "uses_search",
				Prompt: "Find TODO references.",
				Mocks: map[string]any{
					"agent.response": map[string]any{
						"tool_calls": []any{
							map[string]any{
								"id":   "command:rg.search_text",
								"name": "rg.search_text",
								"arguments": map[string]any{
									"template_id": "rg.search_text",
								},
							},
						},
					},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:   "tool-call",
					Equals: "command:rg.search_text",
				}},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	var decoded agentValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if len(decoded.ToolCallReferences) != 1 || decoded.ToolCallReferences[0] != "command:rg.search_text" {
		t.Fatalf("decoded tool refs = %#v, want command:rg.search_text", decoded.ToolCallReferences)
	}
	if got := decoded.Agents[0].Result.ToolCallReferences; len(got) != 1 || got[0] != "command:rg.search_text" {
		t.Fatalf("file tool refs = %#v, want command:rg.search_text", got)
	}
}

// TestAgentsValidateRunsBehaviorValidations verifies package behavior tests run.
func TestAgentsValidateRunsBehaviorValidations(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Do the work.",
			Validations: []schema.AgentValidation{{
				ID:     "uses_search",
				Label:  "Uses search",
				Prompt: "Find the matching file.",
				Mocks: map[string]any{
					"agent.response": map[string]any{
						"text": "Searching now.",
						"tool_calls": []any{
							map[string]any{"id": "command:rg.search_text"},
						},
					},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:   "tool-call",
					Equals: "command:rg.search_text",
				}},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--validation", "uses_search"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "cases=1 passed=1 failed=0 unsupported=0") ||
		!strings.Contains(got, "validations=1 passed=1 failed=0 unsupported=0") ||
		!strings.Contains(got, "agent tool calls: command:rg.search_text") ||
		!strings.Contains(got, "tool calls: command:rg.search_text") {
		t.Fatalf("stdout = %q, want validation case summary", got)
	}
}

// TestAgentsValidateRequireValidationsFailsEmptyPackages verifies library gates.
func TestAgentsValidateRequireValidationsFailsEmptyPackages(t *testing.T) {
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{Name: "Agent", Instruction: "Do the work."}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--require-validations"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing validation failure", err)
	}
}

// TestAgentsValidateRequireAssertionsFailsPlaceholderCases verifies CI gates.
func TestAgentsValidateRequireAssertionsFailsPlaceholderCases(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
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
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--require-assertions"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing assertion failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations without assertions: answers") ||
		!strings.Contains(got, "validations=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want missing assertion summary", got)
	}
}

// TestAgentsValidateRequireToolCallsFailsResponseOnlyCases verifies tool gates.
func TestAgentsValidateRequireToolCallsFailsResponseOnlyCases(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, passingAgentLoader)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--require-tool-calls"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing tool-call failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations without tool calls: Agent") ||
		!strings.Contains(got, "validations=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want missing tool-call summary", got)
	}
}

// TestAgentsValidateRequireToolCallsPassesToolCallingCases verifies tool gates.
func TestAgentsValidateRequireToolCallsPassesToolCallingCases(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:rg.search_text"),
	)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--require-tool-calls"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Agent validations: total=1 passed=1 failed=0") ||
		!strings.Contains(got, "agent tool calls: command:rg.search_text") {
		t.Fatalf("stdout = %q, want passing tool-call summary", got)
	}
}

// TestAgentsValidateRequireToolContractsPassesConfiguredTool verifies direct contracts.
func TestAgentsValidateRequireToolContractsPassesConfiguredTool(t *testing.T) {
	toolPath := writeTestToolContractConfig(t)
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(
		context.Background(),
		&stdout,
		toolCallingAgentLoaderWithArgs("command:rg.search_text", map[string]any{"pattern": "TODO"}),
	)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--tool", toolPath, "--require-tool-contracts"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Agent validations: total=1 passed=1 failed=0") ||
		!strings.Contains(got, "agent tool calls: command:rg.search_text") {
		t.Fatalf("stdout = %q, want passing tool contract summary", got)
	}
}

// TestAgentsValidateRequireToolContractsUsesExplicitPackage verifies package loading.
func TestAgentsValidateRequireToolContractsUsesExplicitPackage(t *testing.T) {
	root := t.TempDir()
	toolPath := filepath.Join(root, "tools", "rg", "tool.yaml")
	mcpPath := filepath.Join(root, "mcp", "sourcecontrol", "mcp.yaml")
	if err := os.MkdirAll(filepath.Dir(toolPath), 0o700); err != nil {
		t.Fatalf("MkdirAll(tool) error = %v", err)
	}
	if err := os.MkdirAll(filepath.Dir(mcpPath), 0o700); err != nil {
		t.Fatalf("MkdirAll(mcp) error = %v", err)
	}
	if err := os.WriteFile(toolPath, testToolContractConfigContent(), 0o600); err != nil {
		t.Fatalf("WriteFile(tool) error = %v", err)
	}
	if err := os.WriteFile(mcpPath, []byte(`mcp:
  enabled: true
  servers:
    - name: sourcecontrol
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - status
`), 0o600); err != nil {
		t.Fatalf("WriteFile(mcp) error = %v", err)
	}
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(
		context.Background(),
		&stdout,
		toolCallingAgentLoaderWithArgs("command:rg.search_text", map[string]any{"pattern": "TODO"}),
	)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--tool", toolPath, "--require-tool-contracts"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
}

// TestAgentsValidateRequireToolContractsFailsUnknownTool verifies contract ids.
func TestAgentsValidateRequireToolContractsFailsUnknownTool(t *testing.T) {
	toolPath := writeTestToolContractConfig(t)
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:missing.search"),
	)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--tool", toolPath, "--require-tool-contracts"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want unknown tool contract failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations with unknown tool calls: uses_search: command:missing.search") ||
		!strings.Contains(got, "validations=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want unknown tool-call summary", got)
	}
}

// TestAgentsValidateRequireToolContractsFailsInvalidArguments verifies schemas.
func TestAgentsValidateRequireToolContractsFailsInvalidArguments(t *testing.T) {
	toolPath := writeTestToolContractConfig(t)
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(
		context.Background(),
		&stdout,
		toolCallingAgentLoaderWithArgs("command:rg.search_text", nil),
	)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--tool", toolPath, "--require-tool-contracts"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want invalid argument failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations with invalid tool arguments: uses_search: command:rg.search_text") ||
		!strings.Contains(got, "validations=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want invalid argument summary", got)
	}
}

// TestAgentsValidateRequireToolContractsSetupErrorWritesArtifacts verifies CI evidence.
func TestAgentsValidateRequireToolContractsSetupErrorWritesArtifacts(t *testing.T) {
	toolPath := filepath.Join(t.TempDir(), "missing-tool.yaml")
	reportPath := filepath.Join(t.TempDir(), "agent-validations.xml")
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(
		context.Background(),
		&stdout,
		toolCallingAgentLoader("command:rg.search_text"),
	)
	cmd.SetArgs([]string{
		"validate",
		"--agent", "agent.yaml",
		"--tool", toolPath,
		"--require-tool-contracts",
		"--json",
		"--junit", reportPath,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "missing-tool.yaml") {
		t.Fatalf("Execute() error = %v, want missing tool config failure", err)
	}
	var decoded agentValidationResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Failed != 1 || len(decoded.Agents) != 1 ||
		!strings.Contains(decoded.Agents[0].Error, "tool contract setup failed") ||
		!strings.Contains(decoded.Agents[0].Error, "missing-tool.yaml") {
		t.Fatalf("decoded = %#v, want tool contract setup failure JSON evidence", decoded)
	}
	report := readJUnitReport(t, reportPath)
	if report.Failures != 1 ||
		!junitReportContainsFailure(report, "tool contract setup failed") ||
		!junitReportContainsFailure(report, "missing-tool.yaml") {
		t.Fatalf("report = %#v, want tool contract setup failure JUnit evidence", report)
	}
}

// TestAgentsValidateRequireAssertionsIgnoresUnsupportedExpected verifies typos do not count.
func TestAgentsValidateRequireAssertionsIgnoresUnsupportedExpected(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Do the work.",
			Validations: []schema.AgentValidation{{
				ID:     "answers",
				Prompt: "Answer.",
				Expected: map[string]any{
					"respones_contains": "done",
				},
				Mocks: map[string]any{
					"agent.response": map[string]any{"text": "done"},
				},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--require-assertions"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want missing assertion failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "agent validations without assertions: answers") {
		t.Fatalf("stdout = %q, want unsupported expected ignored by assertion gate", got)
	}
}

// TestAgentsValidateFailsUnsupportedLiveValidation verifies live cases fail CI.
func TestAgentsValidateFailsUnsupportedLiveValidation(t *testing.T) {
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Do the work.",
			Validations: []schema.AgentValidation{{
				ID:     "live_check",
				Mode:   "live",
				Prompt: "Answer.",
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "unsupported=1") {
		t.Fatalf("Execute() error = %v, want unsupported validation failure", err)
	}
}

// TestAgentsValidateModeMockedSkipsLivePlaceholders verifies portable CI mode filters.
func TestAgentsValidateModeMockedSkipsLivePlaceholders(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newAgentsCommandWithLoader(context.Background(), &stdout, func(string) (schema.Agent, error) {
		return mixedModeAgent(), nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--mode", "mocked", "--require-assertions"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v output = %q", err, stdout.String())
	}
	if got := stdout.String(); !strings.Contains(got, "validations=1 passed=1 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want only mocked validation to run", got)
	}
}

// TestAgentsValidateLiveUsesConfiguredRuntimeHost verifies live runtime wiring.
func TestAgentsValidateLiveUsesConfiguredRuntimeHost(t *testing.T) {
	var stdout bytes.Buffer
	host := cliLiveAgentHost{
		response: agentvalidation.Response{Text: "live response"},
	}
	cleanupCalled := false
	cmd := newAgentsCommandWithLoaderAndRunner(
		context.Background(),
		&stdout,
		func(string) (schema.Agent, error) {
			return schema.Agent{
				Name:        "Agent",
				Instruction: "Do the work.",
				Validations: []schema.AgentValidation{{
					ID:     "live_check",
					Mode:   "live",
					Prompt: "Answer.",
					Assertions: []schema.ValidationAssertion{{
						Type:     "response-contains",
						Contains: "live response",
					}},
				}},
			}, nil
		},
		func(ctx context.Context, opts agentValidationOptions) (*agentvalidation.Runner, func(), error) {
			if ctx == nil {
				t.Fatalf("runner context = nil")
			}
			if !opts.Live {
				t.Fatalf("Live = false, want true")
			}
			if opts.Runtime.ModelConfigPath != "model.yaml" || opts.Runtime.ToolPath != "tool.yaml" || !opts.Runtime.ToolSet {
				t.Fatalf("runtime opts = %#v, want model/tool runtime config", opts.Runtime)
			}
			return agentvalidation.NewRunnerWithHost(&host), func() { cleanupCalled = true }, nil
		},
	)
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--live", "--model", "model.yaml", "--tool", "tool.yaml"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !cleanupCalled {
		t.Fatalf("cleanupCalled = false, want cleanup")
	}
	if host.request.Agent.Name != "Agent" || host.request.Prompt != "Answer." {
		t.Fatalf("host request = %#v, want loaded agent and prompt", host.request)
	}
	if got := stdout.String(); !strings.Contains(got, "validations=1 passed=1 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want live validation summary", got)
	}
}

// TestAgentsValidateWritesJUnitReport verifies CI report output.
func TestAgentsValidateWritesJUnitReport(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent-validations.xml")
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{}, errors.New("agent name must not be empty")
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--junit", path})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want validation failure", err)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 || len(report.Suites) != 1 {
		t.Fatalf("report = %#v, want one failing agent load testcase", report)
	}
	if got := report.Suites[0].TestCases[0].Name; got != "agent.load" {
		t.Fatalf("testcase name = %q, want agent.load", got)
	}
}

// TestAgentsValidateJUnitReportIncludesBehaviorEvidence verifies CI failures explain agent behavior.
func TestAgentsValidateJUnitReportIncludesBehaviorEvidence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent-validations.xml")
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Do the work.",
			Validations: []schema.AgentValidation{{
				ID:     "uses_search",
				Mode:   "mocked",
				Prompt: "Find TODO references.",
				Mocks: map[string]any{
					"agent.response": map[string]any{
						"text": "I searched the workspace.",
						"tool_calls": []any{
							map[string]any{
								"id":   "command:rg.search_text",
								"name": "rg.search_text",
								"arguments": map[string]any{
									"pattern": "TODO",
								},
							},
						},
					},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:     "response-contains",
					Contains: "missing phrase",
				}},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--junit", path})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want validation failure", err)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 2 || report.Failures != 1 || len(report.Suites) != 1 {
		t.Fatalf("report = %#v, want load pass and one failing validation", report)
	}
	failure := report.Suites[0].TestCases[1].Failure
	if failure == nil {
		t.Fatalf("failure = nil, want behavior evidence")
	}
	for _, want := range []string{
		"mode: mocked",
		"prompt: Find TODO references.",
		"response: I searched the workspace.",
		"tool-contract: command:rg.search_text",
		"tool-call: command:rg.search_text",
		`"pattern":"TODO"`,
		"assertion response-contains",
	} {
		if !strings.Contains(failure.Text, want) {
			t.Fatalf("failure text = %q, want %q", failure.Text, want)
		}
	}
}

// TestAgentsValidateJUnitReportNormalizesCommandExecuteEvidence verifies reports.
func TestAgentsValidateJUnitReportNormalizesCommandExecuteEvidence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "agent-validations.xml")
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{
			Name:        "Agent",
			Instruction: "Do the work.",
			Validations: []schema.AgentValidation{{
				ID:     "uses_command_execute",
				Mode:   "mocked",
				Prompt: "Find TODO references.",
				Mocks: map[string]any{
					"agent.response": map[string]any{
						"tool_calls": []any{
							map[string]any{
								"name": "command_execute",
								"arguments": map[string]any{
									"template_id": "rg.search_text",
									"parameters": map[string]any{
										"pattern": "TODO",
									},
								},
							},
						},
					},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:     "response-contains",
					Contains: "missing phrase",
				}},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--junit", path})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want validation failure", err)
	}
	report := readJUnitReport(t, path)
	failure := report.Suites[0].TestCases[1].Failure
	if failure == nil {
		t.Fatalf("failure = nil, want behavior evidence")
	}
	for _, want := range []string{
		"tool-contract: command:rg.search_text",
		"tool-call: command_execute",
		`"template_id":"rg.search_text"`,
	} {
		if !strings.Contains(failure.Text, want) {
			t.Fatalf("failure text = %q, want %q", failure.Text, want)
		}
	}
}

// TestAgentsValidateRejectsAgentAndDirectory verifies package inputs are exclusive.
func TestAgentsValidateRejectsAgentAndDirectory(t *testing.T) {
	cmd := newAgentsCommandWithLoader(context.Background(), &bytes.Buffer{}, func(string) (schema.Agent, error) {
		return schema.Agent{}, nil
	})
	cmd.SetArgs([]string{"validate", "--agent", "agent.yaml", "--agent-dir", t.TempDir()})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "cannot be combined") {
		t.Fatalf("Execute() error = %v, want exclusivity error", err)
	}
}

// TestRootCommandIncludesAgentsValidate verifies the public CLI exposes agent validation.
func TestRootCommandIncludesAgentsValidate(t *testing.T) {
	root := NewRootCommand(context.Background())
	agents, _, err := root.Find([]string{"agents", "validate"})
	if err != nil {
		t.Fatalf("Find() error = %v", err)
	}
	if agents == nil || agents.Name() != "validate" {
		t.Fatalf("agents validate command = %#v, want validate command", agents)
	}
}

// mixedModeAgent returns one mocked case and one live placeholder case.
func mixedModeAgent() schema.Agent {
	return schema.Agent{
		Name:        "Agent",
		Instruction: "Do the work.",
		Validations: []schema.AgentValidation{
			{
				ID:     "mocked_check",
				Mode:   "mocked",
				Prompt: "Answer.",
				Mocks: map[string]any{
					"agent.response": map[string]any{"text": "done"},
				},
				Assertions: []schema.ValidationAssertion{{
					Type:     "response-contains",
					Contains: "done",
				}},
			},
			{
				ID:     "live_placeholder",
				Mode:   "live",
				Prompt: "Answer live.",
			},
		},
	}
}

// writeTestAgentPackage creates one package-shaped agent config.
func writeTestAgentPackage(t *testing.T, root string, name string) string {
	t.Helper()
	path := filepath.Join(root, name, schema.DefaultAgentFilename)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(path, []byte("name: Test agent\ninstruction: Do the work.\n"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	return path
}

// writeTestToolContractConfig creates one active tool config with an input schema.
func writeTestToolContractConfig(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "tool.yaml")
	if err := os.WriteFile(path, testToolContractConfigContent(), 0o600); err != nil {
		t.Fatalf("WriteFile(tool) error = %v", err)
	}
	return path
}

// testToolContractConfigContent returns a package config with one command schema.
func testToolContractConfigContent() []byte {
	return []byte(`name: linux-tools
local-exec:
  enabled: true
  default-timeout: 10s
  default-max-output-bytes: 65536
  commands:
    - name: rg
      executable: rg
      description: Search workspace text.
      operations:
        - name: search_text
          description: Search text by pattern.
          input-schema:
            type: object
            required:
              - pattern
            properties:
              pattern:
                type: string
mcp:
  enabled: true
  servers:
    - name: sourcecontrol
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - status
`)
}

// cliLiveAgentHost records live validation requests for CLI tests.
type cliLiveAgentHost struct {
	request  agentvalidation.Request
	response agentvalidation.Response
	err      error
}

// Respond records a live validation request and returns configured evidence.
func (h *cliLiveAgentHost) Respond(_ context.Context, req agentvalidation.Request) (agentvalidation.Response, error) {
	h.request = req
	return h.response, h.err
}
