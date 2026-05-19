// This file tests command proposal and execution behavior.
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

// TestTemplateCommandRunsAfterApproval verifies named templates use the generic path.
func TestTemplateCommandRunsAfterApproval(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		ApprovalTTL:      time.Minute,
		RequireApproval:  true,
		Templates: []Template{{
			ID:         "echo",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "printf hello-{{name}}"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	ctx := context.Background()
	request, err := service.Request(ctx, Request{
		TemplateID: "echo",
		Parameters: map[string]any{"name": "world"},
	})
	if err != nil {
		t.Fatalf("Request() error = %v", err)
	}
	if !request.ApprovalRequired {
		t.Fatalf("ApprovalRequired = false, want true")
	}
	if _, err := service.Run(ctx, RunRequest{ApprovalID: request.ApprovalID}); err == nil {
		t.Fatalf("Run() error = nil, want explicit approval requirement")
	}
	approved, err := service.Approve(ctx, request.ApprovalID)
	if err != nil {
		t.Fatalf("Approve() error = %v", err)
	}
	if approved.Status != statusApproved {
		t.Fatalf("Approve() status = %q, want approved", approved.Status)
	}
	run, err := service.Run(ctx, RunRequest{ApprovalID: request.ApprovalID})
	if err != nil {
		t.Fatalf("Run() after approval error = %v", err)
	}
	status := waitCommandJob(t, service, run.JobID)
	if status.Status != statusSucceeded || status.StdoutTail != "hello-world" {
		t.Fatalf("Status() = %#v, want succeeded hello-world", status)
	}
	if _, err := service.Run(ctx, RunRequest{ApprovalID: request.ApprovalID}); err == nil {
		t.Fatalf("Run() reused approval without error")
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
		ApprovalTTL:      time.Minute,
		RequireApproval:  false,
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
		ApprovalTTL:      time.Minute,
		RequireApproval:  false,
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
		ApprovalTTL:      time.Minute,
		RequireApproval:  false,
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
		ApprovalTTL:      time.Minute,
		RequireApproval:  false,
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

// TestTemplateRequestValidatesParameterSchema verifies template inputs use configured schemas.
func TestTemplateRequestValidatesParameterSchema(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		ApprovalTTL:      time.Minute,
		RequireApproval:  false,
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

	_, err = service.Request(context.Background(), Request{TemplateID: "typed", Parameters: map[string]any{}})
	if err == nil || !strings.Contains(err.Error(), "template parameters invalid") {
		t.Fatalf("Request() error = %v, want parameter validation", err)
	}
}

// TestTemplateRequestPersistsContractMetadata verifies approvals keep the full template contract.
func TestTemplateRequestPersistsContractMetadata(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		ApprovalTTL:      time.Minute,
		RequireApproval:  true,
		Templates: []Template{{
			ID:                     "contracted",
			Executable:             shellPath(),
			Args:                   []string{shellFlag(), "printf {{name}}"},
			ParameterSchema:        map[string]any{"type": "object", "required": []any{"name"}},
			EnvironmentPolicy:      map[string]any{"network": "disabled"},
			WorkingDirectoryPolicy: "template",
			ValidationSchema:       map[string]any{"type": "object"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	request, err := service.Request(context.Background(), Request{
		TemplateID: "contracted",
		Parameters: map[string]any{"name": "record"},
	})
	if err != nil {
		t.Fatalf("Request() error = %v", err)
	}
	record, err := service.loadApproval(context.Background(), request.ApprovalID)
	if err != nil {
		t.Fatalf("loadApproval() error = %v", err)
	}
	if record.ParameterSchema["type"] != "object" ||
		record.EnvironmentPolicy["network"] != "disabled" ||
		record.WorkingDirectoryPolicy != "template" ||
		record.ValidationSchema["type"] != "object" {
		t.Fatalf("approval record = %#v, want persisted contract metadata", record)
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
		ApprovalTTL:      time.Minute,
		RequireApproval:  false,
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

// TestExecuteRejectsApprovalRequiredCommand verifies workflow calls cannot bypass review.
func TestExecuteRejectsApprovalRequiredCommand(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		ApprovalTTL:      time.Minute,
		RequireApproval:  true,
		Templates: []Template{{
			ID:         "reviewed",
			Executable: shellPath(),
			Args:       []string{shellFlag(), "true"},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.Execute(context.Background(), ExecuteRequest{TemplateID: "reviewed"})
	if err == nil || !strings.Contains(err.Error(), "approval-required") {
		t.Fatalf("Execute() error = %v, want approval rejection", err)
	}
}

// TestTemplateListDoesNotExposeCommandSecrets verifies template discovery is sanitized.
func TestTemplateListDoesNotExposeCommandSecrets(t *testing.T) {
	service, err := Open(Config{
		DataDir:          t.TempDir(),
		AllowedWorkdirs:  []string{t.TempDir()},
		DefaultTimeout:   time.Second,
		DefaultMaxOutput: 1024,
		ApprovalTTL:      time.Minute,
		AllowedEnv:       []string{"PATH", "SECRET_TOKEN"},
		Templates: []Template{{
			ID:                     "secret",
			Description:            "Run a secret-bearing command.",
			Executable:             shellPath(),
			Args:                   []string{shellFlag(), "printf {{name}}"},
			Stdin:                  "hidden stdin",
			Env:                    map[string]string{"SECRET_TOKEN": "raw-secret"},
			EnvironmentPolicy:      map[string]any{"network": "disabled"},
			WorkingDirectoryPolicy: "template",
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

	request, err := service.Request(context.Background(), Request{
		TemplateID: "secret",
		Parameters: map[string]any{"name": "review"},
		WorkingDir: service.cfg.AllowedWorkdirs[0],
		Executable: "",
	})
	if err != nil {
		t.Fatalf("Request() error = %v", err)
	}
	if !request.HasStdin {
		t.Fatalf("Request() HasStdin = false, want true")
	}
	if strings.Contains(fmt.Sprint(request), "hidden stdin") ||
		strings.Contains(fmt.Sprint(request), "raw-secret") {
		t.Fatalf("request result leaked secret-bearing fields: %#v", request)
	}
}

// TestArbitraryCommandRequiresAllowedWorkdir verifies cwd policy is enforced.
func TestArbitraryCommandRequiresAllowedWorkdir(t *testing.T) {
	service, err := Open(Config{
		DataDir:         t.TempDir(),
		AllowedWorkdirs: []string{t.TempDir()},
		AllowArbitrary:  true,
		ApprovalTTL:     time.Minute,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	_, err = service.Request(context.Background(), Request{
		Executable: shellPath(),
		Args:       []string{shellFlag(), "true"},
		WorkingDir: "/",
	})
	if err == nil || !strings.Contains(err.Error(), "outside allowed roots") {
		t.Fatalf("Request() error = %v, want workdir rejection", err)
	}
}

// TestCommandRecordIDsRejectTraversal verifies public ids cannot escape data roots.
func TestCommandRecordIDsRejectTraversal(t *testing.T) {
	service, err := Open(Config{
		DataDir:         t.TempDir(),
		AllowedWorkdirs: []string{t.TempDir()},
		ApprovalTTL:     time.Minute,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	if _, err := service.Run(context.Background(), RunRequest{ApprovalID: "../outside"}); err == nil || !strings.Contains(err.Error(), "approval id") {
		t.Fatalf("Run() error = %v, want invalid approval id", err)
	}
	if _, err := service.Status(context.Background(), "../outside"); err == nil || !strings.Contains(err.Error(), "job id") {
		t.Fatalf("Status() error = %v, want invalid job id", err)
	}
}

// waitCommandJob waits for one command job to reach a terminal state.
func waitCommandJob(t *testing.T, service *Service, jobID string) StatusResult {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		status, err := service.Status(context.Background(), jobID)
		if err != nil {
			t.Fatalf("Status() error = %v", err)
		}
		if status.Status != statusRunning {
			return status
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("command job %s did not finish", jobID)
	return StatusResult{}
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
