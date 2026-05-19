// This file tests command proposal and execution behavior.
package command

import (
	"context"
	"fmt"
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
			ID:          "secret",
			Description: "Run a secret-bearing command.",
			Executable:  shellPath(),
			Args:        []string{shellFlag(), "printf {{name}}"},
			Stdin:       "hidden stdin",
			Env:         map[string]string{"SECRET_TOKEN": "raw-secret"},
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
		!strings.Contains(strings.Join(got.Parameters, ","), "name") {
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
