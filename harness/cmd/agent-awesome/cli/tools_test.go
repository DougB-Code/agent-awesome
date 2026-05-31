// This file tests tool-package validation CLI commands.
package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"encoding/xml"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/toolvalidation"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// TestToolsValidateWritesSummary verifies human-readable validation output.
func TestToolsValidateWritesSummary(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(_ context.Context, path string, validationIDs []string, mode string) (toolvalidation.SuiteResult, error) {
		if path != "custom-tool.yaml" {
			t.Fatalf("tool path = %q, want custom-tool.yaml", path)
		}
		if len(validationIDs) != 0 {
			t.Fatalf("validationIDs = %#v, want empty", validationIDs)
		}
		return toolvalidation.SuiteResult{
			Total:          1,
			Passed:         1,
			Coverage:       toolvalidation.Coverage{Required: 1, Covered: 1},
			AgentToolCalls: []string{"command:curl.http_get"},
			Results: []toolvalidation.Result{{
				ID:     "curl_http_get_mocked",
				Label:  "curl HTTP GET",
				Status: toolvalidation.StatusPassed,
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--tool", "custom-tool.yaml"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "Tool validations: total=1 passed=1 failed=0 unsupported=0 coverage=1/1 missing=0") ||
		!strings.Contains(got, "agent tool calls: command:curl.http_get") ||
		!strings.Contains(got, "passed curl_http_get_mocked - curl HTTP GET") {
		t.Fatalf("stdout = %q, want validation summary", got)
	}
}

// TestToolsValidateModePassesFilter verifies CLI mode selection reaches runners.
func TestToolsValidateModePassesFilter(t *testing.T) {
	var gotMode string
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(_ context.Context, _ string, _ []string, mode string) (toolvalidation.SuiteResult, error) {
		gotMode = mode
		return toolvalidation.SuiteResult{Total: 1, Passed: 1}, nil
	})
	cmd.SetArgs([]string{"validate", "--tool", "tool.yaml", "--mode", "mocked"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if gotMode != "mocked" {
		t.Fatalf("mode = %q, want mocked", gotMode)
	}
}

// TestToolsImportOpenAPIWritesToolPackage verifies the CLI imports REST schemas
// into loadable command-backed tool packages.
func TestToolsImportOpenAPIWritesToolPackage(t *testing.T) {
	dir := t.TempDir()
	schemaPath := filepath.Join(dir, "openapi.yaml")
	outPath := filepath.Join(dir, "tool.yaml")
	if err := os.WriteFile(schemaPath, []byte(`
openapi: 3.0.0
info:
  title: Contacts API
servers:
  - url: https://api.example.test
paths:
  /contacts/{contactId}:
    get:
      operationId: getContact
      parameters:
        - name: contactId
          in: path
          required: true
          schema:
            type: string
`), 0o600); err != nil {
		t.Fatalf("WriteFile(openapi) error = %v", err)
	}
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, nil
	})
	cmd.SetArgs([]string{"import-openapi", "--schema", schemaPath, "--out", outPath})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !strings.Contains(stdout.String(), "wrote "+outPath) {
		t.Fatalf("stdout = %q, want written path", stdout.String())
	}
	data, err := os.ReadFile(outPath)
	if err != nil {
		t.Fatalf("ReadFile(out) error = %v", err)
	}
	if !strings.Contains(string(data), "local-exec:") || !strings.Contains(string(data), "getContact") {
		t.Fatalf("generated YAML = %s, want AA tool package", data)
	}
}

// TestToolsInstallCopiesLocalPackage verifies source-control install wiring.
func TestToolsInstallCopiesLocalPackage(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source", "package")
	if err := os.MkdirAll(source, 0o700); err != nil {
		t.Fatalf("MkdirAll(source) error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(source, schema.DefaultToolFilename), []byte("name: Local\n"), 0o600); err != nil {
		t.Fatalf("WriteFile(tool) error = %v", err)
	}
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, nil
	})
	toolRoot := filepath.Join(root, "tools")
	cmd.SetArgs([]string{"install", source, "--tool-root", toolRoot, "--mcp-root", filepath.Join(root, "mcp"), "--name", "local-tool"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !strings.Contains(stdout.String(), `installed tool package "local-tool"`) {
		t.Fatalf("stdout = %q, want install summary", stdout.String())
	}
	if got, err := os.ReadFile(filepath.Join(toolRoot, "local-tool", schema.DefaultToolFilename)); err != nil || string(got) != "name: Local\n" {
		t.Fatalf("installed tool = %q, %v", got, err)
	}
}

// TestToolsInstallCopiesLocalAppPluginPackage verifies app plugin install flags.
func TestToolsInstallCopiesLocalAppPluginPackage(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source", "calendar")
	if err := os.MkdirAll(source, 0o700); err != nil {
		t.Fatalf("MkdirAll(source) error = %v", err)
	}
	if err := os.WriteFile(filepath.Join(source, schema.DefaultAppPluginFilename), []byte("name: Calendar\n"), 0o600); err != nil {
		t.Fatalf("WriteFile(app) error = %v", err)
	}
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, nil
	})
	appRoot := filepath.Join(root, "app-plugins")
	cmd.SetArgs([]string{"install", source, "--tool-root", filepath.Join(root, "tools"), "--mcp-root", filepath.Join(root, "mcp"), "--app-root", appRoot, "--name", "apple-calendar"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if !strings.Contains(stdout.String(), `installed app package "apple-calendar"`) {
		t.Fatalf("stdout = %q, want install summary", stdout.String())
	}
	if got, err := os.ReadFile(filepath.Join(appRoot, "apple-calendar", schema.DefaultAppPluginFilename)); err != nil || string(got) != "name: Calendar\n" {
		t.Fatalf("installed app = %q, %v", got, err)
	}
}

// TestToolsValidateRequireCoverageFailsMissingTargets verifies CI coverage gates.
func TestToolsValidateRequireCoverageFailsMissingTargets(t *testing.T) {
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{
			Total:  1,
			Passed: 1,
			Coverage: toolvalidation.Coverage{
				Required: 1,
				Missing: []toolvalidation.CoverageItem{{
					Type: "runbook-node",
					ID:   "rg_search",
				}},
			},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--require-coverage"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "coverage_missing=1") {
		t.Fatalf("Execute() error = %v, want coverage failure", err)
	}
}

// TestToolsValidateRequireInputSchemasFailsMissingSchemas verifies schema gates.
func TestToolsValidateRequireInputSchemasFailsMissingSchemas(t *testing.T) {
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
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
	})
	cmd.SetArgs([]string{"validate", "--require-input-schemas"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "input_schema_missing=1") {
		t.Fatalf("Execute() error = %v, want input schema failure", err)
	}
}

// TestToolsValidateRequireAssertionsFailsPlaceholderCases verifies CI gates.
func TestToolsValidateRequireAssertionsFailsPlaceholderCases(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{
			Total:  1,
			Passed: 1,
			Results: []toolvalidation.Result{{
				ID:     "rg_search_text_mocked",
				Label:  "Search text",
				Status: toolvalidation.StatusPassed,
				Assertions: []toolvalidation.AssertionResult{{
					Type:   "configured",
					Passed: true,
				}},
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--require-assertions"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "missing_assertions=1") {
		t.Fatalf("Execute() error = %v, want missing assertion failure", err)
	}
	if got := stdout.String(); !strings.Contains(got, "tool validations without assertions: rg_search_text_mocked") ||
		!strings.Contains(got, "Tool validations: total=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want missing assertion summary", got)
	}
}

// TestToolsValidatePassesSelectedValidationIDs verifies row-level reruns.
func TestToolsValidatePassesSelectedValidationIDs(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(_ context.Context, _ string, validationIDs []string, mode string) (toolvalidation.SuiteResult, error) {
		if strings.Join(validationIDs, ",") != "curl_http_get_mocked,jq_filter_mocked" {
			t.Fatalf("validationIDs = %#v, want selected IDs", validationIDs)
		}
		return toolvalidation.SuiteResult{
			Total:  2,
			Passed: 2,
			Results: []toolvalidation.Result{
				{ID: "curl_http_get_mocked", Status: toolvalidation.StatusPassed},
				{ID: "jq_filter_mocked", Status: toolvalidation.StatusPassed},
			},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--validation", "curl_http_get_mocked", "--validation", "jq_filter_mocked"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); !strings.Contains(got, "passed curl_http_get_mocked") ||
		!strings.Contains(got, "passed jq_filter_mocked") {
		t.Fatalf("stdout = %q, want selected validation summary", got)
	}
}

// TestToolsValidateDirectoryWritesAggregateSummary verifies library-wide output.
func TestToolsValidateDirectoryWritesAggregateSummary(t *testing.T) {
	root := t.TempDir()
	alpha := writeTestToolPackage(t, root, "alpha")
	beta := writeTestToolPackage(t, root, "beta")
	seen := []string{}
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(_ context.Context, path string, _ []string, mode string) (toolvalidation.SuiteResult, error) {
		seen = append(seen, path)
		return toolvalidation.SuiteResult{
			Total:          1,
			Passed:         1,
			AgentToolCalls: []string{"command:" + filepath.Base(filepath.Dir(path)) + ".run"},
			Results: []toolvalidation.Result{{
				ID:     filepath.Base(filepath.Dir(path)) + "_validation",
				Status: toolvalidation.StatusPassed,
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--tool-dir", root})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if strings.Join(seen, ",") != strings.Join([]string{alpha, beta}, ",") {
		t.Fatalf("seen paths = %#v, want alpha then beta", seen)
	}
	if got := stdout.String(); !strings.Contains(got, "Tool library validations: packages=2 passed=2 failed=0 unsupported=0 total=2 passed=2 failed=0 unsupported=0 coverage=0/0 missing=0") ||
		!strings.Contains(got, "package "+alpha+": total=1 passed=1 failed=0 unsupported=0") ||
		!strings.Contains(got, "  agent tool calls: command:alpha.run") ||
		!strings.Contains(got, "  passed alpha_validation") {
		t.Fatalf("stdout = %q, want library summary", got)
	}
}

// TestToolsValidateDirectoryFindsNestedPackages verifies GitHub-style library trees.
func TestToolsValidateDirectoryFindsNestedPackages(t *testing.T) {
	root := t.TempDir()
	rootPackage := writeTestToolPackage(t, root, ".")
	nested := writeTestToolPackage(t, root, filepath.Join("linux", "network", "curl"))
	generated := writeTestToolPackage(t, root, filepath.Join("build", "ignored"))
	hidden := writeTestToolPackage(t, root, filepath.Join(".cache", "ignored"))

	paths, err := toolPackageConfigPaths(root)
	if err != nil {
		t.Fatalf("toolPackageConfigPaths() error = %v", err)
	}
	if got, want := strings.Join(paths, ","), strings.Join([]string{nested, rootPackage}, ","); got != want {
		t.Fatalf("paths = %#v, want root and nested packages without generated dirs; generated=%q hidden=%q", paths, generated, hidden)
	}
}

// TestToolsValidateDirectorySkipsUnmatchedSelections verifies library-wide selected reruns.
func TestToolsValidateDirectorySkipsUnmatchedSelections(t *testing.T) {
	root := t.TempDir()
	alpha := writeTestToolPackage(t, root, "alpha")
	beta := writeTestToolPackage(t, root, "beta")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(_ context.Context, path string, validationIDs []string, mode string) (toolvalidation.SuiteResult, error) {
		if strings.Join(validationIDs, ",") != "beta_validation" {
			t.Fatalf("validationIDs = %#v, want beta_validation", validationIDs)
		}
		if path == alpha {
			return toolvalidation.SuiteResult{}, toolvalidation.MissingValidationError{IDs: []string{"beta_validation"}}
		}
		if path != beta {
			t.Fatalf("path = %q, want %q or %q", path, alpha, beta)
		}
		return toolvalidation.SuiteResult{
			Total:  1,
			Passed: 1,
			Results: []toolvalidation.Result{{
				ID:     "beta_validation",
				Status: toolvalidation.StatusPassed,
			}},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--tool-dir", root, "--validation", "beta_validation"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if got := stdout.String(); strings.Contains(got, "package "+alpha) ||
		!strings.Contains(got, "package "+beta+": total=1 passed=1 failed=0 unsupported=0") {
		t.Fatalf("stdout = %q, want only matching package", got)
	}
}

// TestToolsValidateDirectoryMissingSelectionWritesArtifacts verifies stale IDs.
func TestToolsValidateDirectoryMissingSelectionWritesArtifacts(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, root, "alpha")
	path := filepath.Join(t.TempDir(), "tool-validations.xml")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, toolvalidation.MissingValidationError{IDs: []string{"missing_validation"}}
	})
	cmd.SetArgs([]string{
		"validate",
		"--tool-dir", root,
		"--validation", "missing_validation",
		"--json",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "missing_validation") {
		t.Fatalf("Execute() error = %v, want missing validation error", err)
	}
	var decoded toolValidationLibraryResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.FailedPackages != 1 || len(decoded.Packages) != 1 ||
		!strings.Contains(decoded.Packages[0].Error, "missing_validation") {
		t.Fatalf("decoded = %#v, want missing selection JSON evidence", decoded)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 ||
		!strings.Contains(report.Suites[0].TestCases[0].Failure.Text, "missing_validation") {
		t.Fatalf("report = %#v, want missing selection JUnit evidence", report)
	}
}

// TestToolsValidateDirectoryJSONWritesAggregate verifies library JSON output.
func TestToolsValidateDirectoryJSONWritesAggregate(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, root, "curl")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{Total: 1, Passed: 1}, nil
	})
	cmd.SetArgs([]string{"validate", "--tool-dir", root, "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	var decoded toolValidationLibraryResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.TotalPackages != 1 || decoded.PassedPackages != 1 || decoded.Total != 1 || decoded.Passed != 1 {
		t.Fatalf("decoded = %#v, want one package pass", decoded)
	}
}

// TestToolsValidateDirectoryReportsPackageErrors verifies bad packages fail CI.
func TestToolsValidateDirectoryReportsPackageErrors(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, root, "broken")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, errors.New("bad package")
	})
	cmd.SetArgs([]string{"validate", "--tool-dir", root, "--json"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed_packages=1") {
		t.Fatalf("Execute() error = %v, want failed package error", err)
	}
	var decoded toolValidationLibraryResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Total != 1 || decoded.Failed != 1 || len(decoded.Packages) != 1 {
		t.Fatalf("decoded = %#v, want failed package counted as one validation", decoded)
	}
	result := decoded.Packages[0].Result
	if result.Failed != 1 || len(result.Results) != 1 ||
		result.Results[0].ID != "package.load" ||
		len(result.Results[0].Diagnostics) != 1 ||
		!strings.Contains(result.Results[0].Diagnostics[0].Message, "bad package") {
		t.Fatalf("package result = %#v, want expandable package.load diagnostics", result)
	}
}

// TestToolsValidateDirectorySetupErrorWritesArtifacts verifies empty trees report.
func TestToolsValidateDirectorySetupErrorWritesArtifacts(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(t.TempDir(), "tool-validations.xml")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, passingToolValidator)
	cmd.SetArgs([]string{
		"validate",
		"--tool-dir", root,
		"--json",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "no tool.yaml files found") {
		t.Fatalf("Execute() error = %v, want empty directory failure", err)
	}
	var decoded toolValidationLibraryResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.FailedPackages != 1 || len(decoded.Packages) != 1 ||
		!strings.Contains(decoded.Packages[0].Error, "no tool.yaml files found") {
		t.Fatalf("decoded = %#v, want setup failure JSON evidence", decoded)
	}
	result := decoded.Packages[0].Result
	if result.Failed != 1 || len(result.Results) != 1 ||
		result.Results[0].ID != "package.load" ||
		len(result.Results[0].Diagnostics) != 1 ||
		!strings.Contains(result.Results[0].Diagnostics[0].Message, "no tool.yaml files found") {
		t.Fatalf("package result = %#v, want expandable package.load diagnostics", result)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 ||
		report.Suites[0].TestCases[0].Name != "package.load" ||
		!strings.Contains(report.Suites[0].TestCases[0].Failure.Text, "no tool.yaml files found") {
		t.Fatalf("report = %#v, want setup failure JUnit evidence", report)
	}
}

// TestToolsValidateDirectoryRequireCoverageMarksPackageFailed verifies counts.
func TestToolsValidateDirectoryRequireCoverageMarksPackageFailed(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, root, "search")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
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
	})
	cmd.SetArgs([]string{"validate", "--tool-dir", root, "--require-coverage"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed_packages=1") {
		t.Fatalf("Execute() error = %v, want failed package count", err)
	}
	if got := stdout.String(); !strings.Contains(got, "packages=1 passed=0 failed=1 unsupported=0") {
		t.Fatalf("stdout = %q, want strict coverage to mark package failed", got)
	}
}

// TestToolsValidateRejectsToolAndDirectory verifies package inputs are exclusive.
func TestToolsValidateRejectsToolAndDirectory(t *testing.T) {
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, nil
	})
	cmd.SetArgs([]string{"validate", "--tool", "tool.yaml", "--tool-dir", t.TempDir()})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "cannot be combined") {
		t.Fatalf("Execute() error = %v, want exclusivity error", err)
	}
}

// TestToolsValidateJSONWritesMachineReadableResult verifies JSON output.
func TestToolsValidateJSONWritesMachineReadableResult(t *testing.T) {
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{Total: 1, Passed: 1}, nil
	})
	cmd.SetArgs([]string{"validate", "--json"})

	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	var decoded toolvalidation.SuiteResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Total != 1 || decoded.Passed != 1 {
		t.Fatalf("decoded = %#v, want one pass", decoded)
	}
}

// TestToolsValidateSingleSetupErrorWritesArtifacts verifies single-file load errors.
func TestToolsValidateSingleSetupErrorWritesArtifacts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tool-validations.xml")
	var stdout bytes.Buffer
	cmd := newToolsCommandWithValidator(context.Background(), &stdout, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, errors.New("decode tool.yaml: bad field")
	})
	cmd.SetArgs([]string{
		"validate",
		"--tool", "tool.yaml",
		"--json",
		"--junit", path,
	})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "decode tool.yaml") {
		t.Fatalf("Execute() error = %v, want setup failure", err)
	}
	var decoded toolvalidation.SuiteResult
	if err := json.Unmarshal(stdout.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v output = %q", err, stdout.String())
	}
	if decoded.Failed != 1 || len(decoded.Results) != 1 ||
		decoded.Results[0].ID != "package.load" ||
		!strings.Contains(decoded.Results[0].Diagnostics[0].Message, "decode tool.yaml") {
		t.Fatalf("decoded = %#v, want setup failure JSON evidence", decoded)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 ||
		!strings.Contains(report.Suites[0].TestCases[0].Failure.Text, "decode tool.yaml") {
		t.Fatalf("report = %#v, want setup failure JUnit evidence", report)
	}
}

// TestToolValidationsNeedLiveMCPHostDetectsPreset verifies live MCP boundary setup.
func TestToolValidationsNeedLiveMCPHostDetectsPreset(t *testing.T) {
	tools := schema.Tools{
		NodePresets: []schema.NodePreset{{
			ID:     "memory_remember",
			Action: "mcp.call",
		}},
		Validations: []schema.ToolValidation{{
			ID:   "memory_runbook_live",
			Mode: "live",
			Target: schema.ToolValidationTarget{
				Type:     "runbook-node",
				PresetID: "memory_remember",
			},
		}},
	}

	if !toolValidationsNeedLiveMCPHost(tools, []string{"memory_runbook_live"}, "") {
		t.Fatalf("toolValidationsNeedLiveMCPHost() = false, want true")
	}
	if toolValidationsNeedLiveMCPHost(tools, []string{"other"}, "") {
		t.Fatalf("toolValidationsNeedLiveMCPHost() = true for unrelated selection")
	}
}

// TestMCPToolValidationOutputPreservesStructuredFields verifies assertion paths.
func TestMCPToolValidationOutputPreservesStructuredFields(t *testing.T) {
	output := mcpToolValidationOutput(&mcp.CallToolResult{
		StructuredContent: map[string]any{"tool": "remember"},
		Content: []mcp.Content{
			&mcp.TextContent{Text: "saved"},
		},
	})

	if output["tool"] != "remember" || output["text"] != "saved" || output["is_error"] != false {
		t.Fatalf("output = %#v, want structured fields plus text evidence", output)
	}
}

// TestToolsValidateWritesJUnitReport verifies CI report output for one package.
func TestToolsValidateWritesJUnitReport(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tool-validations.xml")
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{
			Total:       2,
			Failed:      1,
			Unsupported: 1,
			Coverage: toolvalidation.Coverage{
				Required: 1,
				Missing: []toolvalidation.CoverageItem{{
					Type: "runbook-node",
					ID:   "rg.search_text",
				}},
			},
			Results: []toolvalidation.Result{
				{
					ID:     "failed_validation",
					Status: toolvalidation.StatusFailed,
					Assertions: []toolvalidation.AssertionResult{{
						Type:     "stdout-contains",
						Passed:   false,
						Expected: "needle",
						Actual:   "haystack",
					}},
				},
				{ID: "unsupported_validation", Status: toolvalidation.StatusUnsupported},
			},
		}, nil
	})
	cmd.SetArgs([]string{"validate", "--junit", path, "--require-coverage"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "coverage_missing=1") {
		t.Fatalf("Execute() error = %v, want validation failure", err)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 3 || report.Failures != 2 || report.Skipped != 1 {
		t.Fatalf("report = %#v, want failed validation, missing coverage, and unsupported skip", report)
	}
	if len(report.Suites) != 1 || report.Suites[0].Name == "" {
		t.Fatalf("report suites = %#v, want one named suite", report.Suites)
	}
}

// TestToolsValidateDirectoryWritesJUnitReport verifies CI output includes package errors.
func TestToolsValidateDirectoryWritesJUnitReport(t *testing.T) {
	root := t.TempDir()
	writeTestToolPackage(t, root, "broken")
	path := filepath.Join(t.TempDir(), "tool-library.xml")
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, errors.New("bad package")
	})
	cmd.SetArgs([]string{"validate", "--tool-dir", root, "--junit", path})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed_packages=1") {
		t.Fatalf("Execute() error = %v, want failed package error", err)
	}
	report := readJUnitReport(t, path)
	if report.Tests != 1 || report.Failures != 1 || len(report.Suites) != 1 {
		t.Fatalf("report = %#v, want one failing package load testcase", report)
	}
	if got := report.Suites[0].TestCases[0].Name; got != "package.load" {
		t.Fatalf("testcase name = %q, want package.load", got)
	}
}

// TestRunToolValidationSuiteRunsLiveCommandWithFixtures verifies real CLI execution.
func TestRunToolValidationSuiteRunsLiveCommandWithFixtures(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tool.yaml")
	if err := os.WriteFile(path, []byte(`
local-exec:
  enabled: true
  commands:
    - name: cat
      executable: cat
      description: Read fixture files.
      operations:
        - name: read
          description: Read one relative fixture file.
          args:
            - "{{path}}"
validations:
  - id: cat_fixture_live
    label: Cat fixture
    mode: live
    target:
      type: command-operation
      command: cat
      operation: read
    input:
      path: input.txt
    fixtures:
      files:
        - path: input.txt
          content: fixture text
    assertions:
      - type: stdout-contains
        contains: fixture text
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	result, err := runToolValidationSuite(context.Background(), path, []string{"cat_fixture_live"}, "")
	if err != nil {
		t.Fatalf("runToolValidationSuite() error = %v", err)
	}
	if result.Total != 1 || result.Passed != 1 {
		t.Fatalf("runToolValidationSuite() = %#v, want one live pass", result)
	}
}

// TestRunToolValidationSuiteRunsLiveRunbookNode verifies preset validation.
func TestRunToolValidationSuiteRunsLiveRunbookNode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tool.yaml")
	if err := os.WriteFile(path, []byte(`
local-exec:
  enabled: true
  commands:
    - name: cat
      executable: cat
      description: Read fixture files.
      operations:
        - name: read
          description: Read one relative fixture file.
          args:
            - "{{path}}"
node-presets:
  - id: cat_read
    label: Cat read
    action: command.execute
    arguments:
      template_id: cat.read
      parameters:
        path: '${path}'
validations:
  - id: cat_runbook_live
    label: Cat runbook
    mode: live
    target:
      type: runbook-node
      preset-id: cat_read
    input:
      path: input.txt
    fixtures:
      files:
        - path: input.txt
          content: runbook fixture text
    assertions:
      - type: stdout-contains
        contains: runbook fixture text
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	result, err := runToolValidationSuite(context.Background(), path, []string{"cat_runbook_live"}, "")
	if err != nil {
		t.Fatalf("runToolValidationSuite() error = %v", err)
	}
	if result.Total != 1 || result.Passed != 1 {
		t.Fatalf("runToolValidationSuite() = %#v, want one live runbook pass", result)
	}
}

// TestRunToolValidationSuiteKeepsPackagesIsolated verifies package validation
// does not inherit sibling MCP packages from an installed library root.
func TestRunToolValidationSuiteKeepsPackagesIsolated(t *testing.T) {
	root := t.TempDir()
	toolPath := filepath.Join(root, "tools", "curl", "tool.yaml")
	mcpPath := filepath.Join(root, "mcp", "memory", "mcp.yaml")
	if err := os.MkdirAll(filepath.Dir(toolPath), 0o700); err != nil {
		t.Fatalf("MkdirAll(tool package) error = %v", err)
	}
	if err := os.MkdirAll(filepath.Dir(mcpPath), 0o700); err != nil {
		t.Fatalf("MkdirAll(mcp package) error = %v", err)
	}
	if err := os.WriteFile(toolPath, []byte(`
local-exec:
  enabled: true
  commands:
    - name: curl
      executable: curl
      description: Fetch URLs.
      operations:
        - name: http_get
          description: Fetch one URL.
          args:
            - "{{url}}"
          input-schema:
            type: object
            required:
              - url
            properties:
              url:
                type: string
`), 0o600); err != nil {
		t.Fatalf("WriteFile(tool) error = %v", err)
	}
	if err := os.WriteFile(mcpPath, []byte(`
mcp:
  enabled: true
  servers:
    - name: memory
      transport: streamable-http
      endpoint: http://127.0.0.1:8090/mcp
      tools:
        allow:
          - remember
`), 0o600); err != nil {
		t.Fatalf("WriteFile(mcp) error = %v", err)
	}

	result, err := runToolValidationSuite(context.Background(), toolPath, nil, "")
	if err != nil {
		t.Fatalf("runToolValidationSuite() error = %v", err)
	}
	if got, want := result.Coverage.Required, 2; got != want {
		t.Fatalf("Coverage.Required = %d, want command-only package coverage %d; missing=%#v", got, want, result.Coverage.Missing)
	}
	for _, missing := range result.Coverage.Missing {
		if missing.Type == "mcp-tool" {
			t.Fatalf("missing coverage includes sibling MCP package: %#v", missing)
		}
	}
}

// TestToolsValidateFailsWhenAnyValidationFails verifies CI-friendly exit behavior.
func TestToolsValidateFailsWhenAnyValidationFails(t *testing.T) {
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{Total: 1, Failed: 1}, nil
	})
	cmd.SetArgs([]string{"validate"})

	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "failed=1") {
		t.Fatalf("Execute() error = %v, want failed validation error", err)
	}
}

// TestToolsValidateReturnsLoadError verifies loader errors are surfaced.
func TestToolsValidateReturnsLoadError(t *testing.T) {
	expected := errors.New("load failed")
	cmd := newToolsCommandWithValidator(context.Background(), &bytes.Buffer{}, func(context.Context, string, []string, string) (toolvalidation.SuiteResult, error) {
		return toolvalidation.SuiteResult{}, expected
	})
	cmd.SetArgs([]string{"validate"})

	if err := cmd.Execute(); !errors.Is(err, expected) {
		t.Fatalf("Execute() error = %v, want %v", err, expected)
	}
}

// writeTestToolPackage creates one package-shaped test file.
func writeTestToolPackage(t *testing.T, root string, name string) string {
	t.Helper()
	path := filepath.Join(root, name, "tool.yaml")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(path, []byte("mcp:\n  enabled: false\n"), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	return path
}

// readJUnitReport decodes one generated JUnit XML report.
func readJUnitReport(t *testing.T, path string) junitSuites {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	var report junitSuites
	if err := xml.Unmarshal(data, &report); err != nil {
		t.Fatalf("xml.Unmarshal() error = %v output = %q", err, string(data))
	}
	return report
}
