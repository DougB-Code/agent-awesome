// This file tests configured command template execution behavior.
package command

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// TestTemplateCommandExecutes verifies named templates use the generic path.
func TestTemplateCommandExecutes(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		Templates: []Template{{
			ID:         "echo",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "printf hello-{{name}}"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{
		TemplateID: "echo",
		Parameters: map[string]any{"name": "world"},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if status.Status != statusSucceeded || status.StdoutTail != "hello-world" {
		t.Fatalf("Execute() = %#v, want succeeded hello-world", status)
	}
}

// TestTemplateExecutableCanUseParameters verifies executable paths remain generic template data.
func TestTemplateExecutableCanUseParameters(t *testing.T) {
	workdir := t.TempDir()
	script := filepath.Join(workdir, "tool.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf executable:%s \"$1\"\n"), 0o700); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{workdir},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		AllowedEnv:       []string{"PATH"},
		Templates: []Template{{
			ID:          "dynamic_exec",
			Description: "Run a configured executable path.",
			Executable:  "{{executable_path}}",
			Args:        []string{"{{value}}"},
			Env:         map[string]string{"DYNAMIC_HOME": "{{home_path}}"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{
		TemplateID: "dynamic_exec",
		WorkingDir: workdir,
		Parameters: map[string]any{"executable_path": script, "home_path": workdir, "value": "ok"},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if strings.TrimSpace(status.StdoutTail) != "executable:ok" {
		t.Fatalf("StdoutTail = %q, want executable:ok", status.StdoutTail)
	}
	if !containsString(service.Templates()[0].Parameters, "executable_path") {
		t.Fatalf("template parameters = %#v, want executable_path", service.Templates()[0].Parameters)
	}
	if !containsString(service.Templates()[0].Parameters, "home_path") {
		t.Fatalf("template parameters = %#v, want home_path", service.Templates()[0].Parameters)
	}
}

// TestExecuteReturnsStructuredJSONValidationAndArtifacts verifies workflow-friendly execution contracts.
func TestExecuteReturnsStructuredJSONValidationAndArtifacts(t *testing.T) {
	workdir := t.TempDir()
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{workdir},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 4096,
		Templates: []Template{{
			ID:             "json",
			Executable:     shellPath(),
			Args:           []string{shellFlag(), `printf '{"status":"ok","count":2}'; printf artifact > out.txt`},
			WorkingDir:     workdir,
			OutputContract: OutputContract{Format: "json", Source: "stdout"},
			ArtifactGlobs:  []string{"out.txt"},
			ValidationSchema: map[string]any{
				"type":     "object",
				"required": []any{"status", "count"},
				"properties": map[string]any{
					"status": map[string]any{"type": "string"},
					"count":  map[string]any{"type": "integer"},
				},
			},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{TemplateID: "json"})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	output, _ := status.Output.(map[string]any)
	if status.Status != statusSucceeded || output["status"] != "ok" || !status.Validation.Valid {
		t.Fatalf("Execute() = %#v, want succeeded structured output", status)
	}
	if len(status.Artifacts) != 1 || status.Artifacts[0].Path != "out.txt" {
		t.Fatalf("artifacts = %#v, want out.txt", status.Artifacts)
	}
}

// TestExecuteReturnsErrorForFailedCommand verifies workflow calls fail on CLI failure.
func TestExecuteReturnsErrorForFailedCommand(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		Templates: []Template{{
			ID:         "fail",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "exit 7"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{TemplateID: "fail"})
	if err == nil || !strings.Contains(err.Error(), "command.execute job") {
		t.Fatalf("Execute() error = %v, want command failure", err)
	}
	if status.Status != statusFailed || status.ExitCode != 7 {
		t.Fatalf("Execute() status = %#v, want failed exit 7", status)
	}
}

// TestExecuteReturnsErrorForInvalidJSONContract verifies unparsable output fails execution.
func TestExecuteReturnsErrorForInvalidJSONContract(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		Templates: []Template{{
			ID:             "bad-json",
			Executable:     shellPath(),
			Args:           []string{shellFlag(), "printf not-json"},
			OutputContract: OutputContract{Format: "json", Source: "stdout"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{TemplateID: "bad-json"})
	if err == nil || !strings.Contains(err.Error(), "output contract failed") {
		t.Fatalf("Execute() error = %v, want output contract failure", err)
	}
	if status.Status != statusSucceeded || len(status.Diagnostics) == 0 {
		t.Fatalf("Execute() status = %#v, want saved diagnostic on succeeded process", status)
	}
}

// TestExecuteReturnsErrorForValidationFailure verifies declared output schemas are enforced.
func TestExecuteReturnsErrorForValidationFailure(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		Templates: []Template{{
			ID:             "invalid-output",
			Executable:     shellPath(),
			Args:           []string{shellFlag(), `printf '{"status":2}'`},
			OutputContract: OutputContract{Format: "json", Source: "stdout"},
			ValidationSchema: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"status": map[string]any{"type": "string"},
				},
			},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{TemplateID: "invalid-output"})
	if err == nil || !strings.Contains(err.Error(), "output validation failed") {
		t.Fatalf("Execute() error = %v, want validation failure", err)
	}
	if status.Validation.Valid {
		t.Fatalf("validation = %#v, want invalid", status.Validation)
	}
}

// TestTemplateExecuteValidatesParameterSchema verifies template inputs use configured schemas.
func TestTemplateExecuteValidatesParameterSchema(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		Templates: []Template{{
			ID:              "typed",
			Executable:      shellPath(),
			Args:            []string{shellFlag(), "printf {{name}}"},
			ParameterSchema: map[string]any{"type": "object", "required": []any{"name"}},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.Execute(context.Background(), ExecuteRequest{
		TemplateID: "typed",
		Parameters: map[string]any{},
	})
	if err == nil || !strings.Contains(err.Error(), "template parameters invalid") {
		t.Fatalf("Execute() error = %v, want parameter validation", err)
	}
}

// TestTemplateRenderingAllowsSpacedPlaceholders verifies discovery and rendering agree.
func TestTemplateRenderingAllowsSpacedPlaceholders(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		Templates: []Template{{
			ID:         "spaced",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "printf {{ name }}"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{
		TemplateID: "spaced",
		Parameters: map[string]any{"name": "rendered"},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if status.StdoutTail != "rendered" {
		t.Fatalf("StdoutTail = %q, want rendered", status.StdoutTail)
	}
}

// TestExecuteRunsConfiguredStarlarkParser verifies parser output is stored on jobs.
func TestExecuteRunsConfiguredStarlarkParser(t *testing.T) {
	parserDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(parserDir, "lines.star"), []byte(`
def parse(stdout, stderr, exit_code, status):
    return {
        "output": {"line": stdout, "status": status},
        "diagnostics": [{"severity": "info", "message": "parsed"}],
    }
`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 4096,
		ParserDir:        parserDir,
		Templates: []Template{{
			ID:         "parse",
			Executable: shellPath(),
			Args:       []string{shellFlag(), `printf parsed-line`},
			ParserID:   "lines",
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	status, err := service.Execute(context.Background(), ExecuteRequest{TemplateID: "parse"})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	output, _ := status.Output.(map[string]any)
	if output["line"] != "parsed-line" || len(status.Diagnostics) != 1 {
		t.Fatalf("Execute() = %#v, want parser output and diagnostics", status)
	}
}

// TestTemplateListDoesNotExposeCommandSecrets verifies template discovery is sanitized.
func TestTemplateListDoesNotExposeCommandSecrets(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		AllowedEnv:       []string{"PATH", "SECRET_TOKEN"},
		Templates: []Template{{
			ID:                     "secret",
			Description:            "Run a secret-bearing command.",
			Executable:             shellPath(),
			Args:                   []string{shellFlag(), "printf {{name}}"},
			Stdin:                  "hidden stdin",
			Env:                    map[string]string{"SECRET_TOKEN": "raw-secret"},
			ParameterSchema:        map[string]any{"type": "object"},
			EnvironmentPolicy:      map[string]any{"network": "disabled"},
			WorkingDirectoryPolicy: "template",
			ValidationSchema:       map[string]any{"type": "object"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	templates := service.Templates()
	if len(templates) != 1 {
		t.Fatalf("Templates() length = %d, want 1", len(templates))
	}
	got := templates[0]
	if got.ID != "secret" ||
		!strings.Contains(strings.Join(got.Parameters, ","), "name") ||
		got.ParameterSchema["type"] != "object" ||
		got.EnvironmentPolicy["network"] != "disabled" ||
		got.WorkingDirectoryPolicy != "template" {
		t.Fatalf("template summary = %#v, want sanitized metadata", got)
	}
	serialized := fmt.Sprint(got)
	if strings.Contains(serialized, "raw-secret") ||
		strings.Contains(serialized, "printf") ||
		strings.Contains(serialized, "SECRET_TOKEN") ||
		strings.Contains(serialized, "hidden stdin") {
		t.Fatalf("template summary leaked command detail: %#v", got)
	}
}

// TestTemplateCommandRequiresAllowedWorkdir verifies cwd policy is enforced.
func TestTemplateCommandRequiresAllowedWorkdir(t *testing.T) {
	service, err := Open(Config{
		DataDir:         t.TempDir(),
		AllowedWorkdirs: []string{t.TempDir()},
		Templates: []Template{{
			ID:         "cwd",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "true"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	_, err = service.Execute(context.Background(), ExecuteRequest{
		TemplateID: "cwd",
		WorkingDir: "/",
	})
	if err == nil || !strings.Contains(err.Error(), "outside allowed roots") {
		t.Fatalf("Execute() error = %v, want workdir rejection", err)
	}
}

// TestTemplateCommandRejectsSymlinkEscapedWorkdir verifies cwd policy uses canonical paths.
func TestTemplateCommandRejectsSymlinkEscapedWorkdir(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	link := filepath.Join(root, "outside")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	service, err := Open(Config{
		DataDir:         t.TempDir(),
		AllowedWorkdirs: []string{root},
		Templates: []Template{{
			ID:         "cwd",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "true"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.Execute(context.Background(), ExecuteRequest{
		TemplateID: "cwd",
		WorkingDir: link,
	})
	if err == nil || !strings.Contains(err.Error(), "outside allowed roots") {
		t.Fatalf("Execute() error = %v, want symlink workdir rejection", err)
	}
}

// TestCommandRecordIDsRejectTraversal verifies public ids cannot escape data roots.
func TestCommandRecordIDsRejectTraversal(t *testing.T) {
	service, err := Open(Config{
		DataDir:         t.TempDir(),
		AllowedWorkdirs: []string{t.TempDir()},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	if _, err := service.Status(context.Background(), "../outside"); err == nil || !strings.Contains(err.Error(), "job id") {
		t.Fatalf("Status() error = %v, want invalid job id", err)
	}
}

// shellPath returns a platform shell for command tests.
func shellPath() string {
	if runtime.GOOS == "windows" {
		return "cmd"
	}
	return "sh"
}

// shellFlag returns the shell execute flag for command tests.
func shellFlag() string {
	if runtime.GOOS == "windows" {
		return "/C"
	}
	return "-c"
}
