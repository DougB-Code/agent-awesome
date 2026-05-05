// This file tests configured local command execution.
package localexec

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"agentawesome/internal/config/schema"
	"google.golang.org/adk/tool/toolconfirmation"
)

func TestExecuteAllowedCommand(t *testing.T) {
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "hello",
		Executable:  "printf",
		Description: "Print hello.",
		Args:        []string{"hello"},
	})

	got, err := r.execute(context.Background(), Input{Command: "hello"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if got.ExitCode != 0 || got.Stdout != "hello" || got.Stderr != "" {
		t.Fatalf("execute() = %#v, want successful hello output", got)
	}
}

func TestRequiresConfirmationAllowsGlobal(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{"."},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "hello",
				Executable:  "printf",
				Description: "Print hello.",
				Args:        []string{"hello"},
				Approval: schema.LocalExecApproval{
					AlwaysAllow: true,
				},
			},
		},
	})

	if r.requiresConfirmation(Input{Command: "hello"}) {
		t.Fatalf("requiresConfirmation() = true, want false for global allow")
	}
}

func TestRequiresConfirmationRequiresReviewForStdin(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{"."},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "cat",
				Executable:  "cat",
				Description: "Echo stdin.",
				Approval: schema.LocalExecApproval{
					AlwaysAllow: true,
				},
			},
		},
	})

	if !r.requiresConfirmation(Input{Command: "cat", Stdin: "input text"}) {
		t.Fatalf("requiresConfirmation() = false, want true when stdin is present")
	}
}

func TestRunConfirmationIncludesStdin(t *testing.T) {
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "cat",
		Executable:  "cat",
		Description: "Echo stdin.",
	})
	ctx := newFakeToolContext(nil)

	if _, err := r.runWithConfirmation(ctx, Input{Command: "cat", Stdin: "input text"}); err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if ctx.requestCount != 1 {
		t.Fatalf("RequestConfirmation count = %d, want 1", ctx.requestCount)
	}
	if !strings.Contains(ctx.hint, "Stdin") || !strings.Contains(ctx.hint, "input text") {
		t.Fatalf("confirmation hint = %q, want stdin preview", ctx.hint)
	}
	payload, ok := ctx.payload.(LocalExecConfirmationPayload)
	if !ok {
		t.Fatalf("confirmation payload = %T, want LocalExecConfirmationPayload", ctx.payload)
	}
	if payload.Stdin == nil || payload.Stdin.Preview != "input text" || payload.Stdin.Bytes != len("input text") {
		t.Fatalf("payload stdin = %#v, want stdin preview", payload.Stdin)
	}
}

func TestRequiresConfirmationAllowsCommandPrefix(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{"."},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "status",
				Executable:  "git",
				Description: "Show status.",
				Args:        []string{"status", "--short"},
				Approval: schema.LocalExecApproval{
					AlwaysAllowCommandPrefixes: []string{"git status"},
				},
			},
		},
	})

	if r.requiresConfirmation(Input{Command: "status"}) {
		t.Fatalf("requiresConfirmation() = true, want false for command prefix")
	}
}

func TestRequiresConfirmationAllowsWorkspaceOnly(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	t.Chdir(root)
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{root, outside},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "pwd",
				Executable:  "pwd",
				Description: "Print cwd.",
				Approval: schema.LocalExecApproval{
					AlwaysAllowWithinWorkspace: true,
				},
			},
		},
	})

	if r.requiresConfirmation(Input{Command: "pwd", CWD: root}) {
		t.Fatalf("requiresConfirmation() = true, want false inside workspace")
	}
	if !r.requiresConfirmation(Input{Command: "pwd", CWD: outside}) {
		t.Fatalf("requiresConfirmation() = false, want true outside workspace")
	}
}

func TestRequiresConfirmationChecksWorkspaceBeforeCommandPrefix(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	t.Chdir(root)
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{root, outside},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "status",
				Executable:  "git",
				Description: "Show status.",
				Args:        []string{"status", "--short"},
				Approval: schema.LocalExecApproval{
					AlwaysAllowWithinWorkspace: true,
					AlwaysAllowCommandPrefixes: []string{"git status"},
				},
			},
		},
	})

	if r.requiresConfirmation(Input{Command: "status", CWD: root}) {
		t.Fatalf("requiresConfirmation() = true, want workspace approval")
	}
	if r.requiresConfirmation(Input{Command: "status", CWD: outside}) {
		t.Fatalf("requiresConfirmation() = true, want command prefix approval after workspace check")
	}
}

func TestExecuteRejectsUnknownCommand(t *testing.T) {
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "hello",
		Executable:  "printf",
		Description: "Print hello.",
		Args:        []string{"hello"},
	})

	if _, err := r.execute(context.Background(), Input{Command: "missing"}); err == nil {
		t.Fatalf("execute() error = nil, want unknown command error")
	}
}

func TestExecuteRejectsCWDEscape(t *testing.T) {
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "pwd",
		Executable:  "pwd",
		Description: "Print cwd.",
	})

	if _, err := r.execute(context.Background(), Input{Command: "pwd", CWD: ".."}); err == nil {
		t.Fatalf("execute() error = nil, want cwd escape error")
	}
}

func TestExecuteRejectsSymlinkCWDEscape(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	t.Chdir(root)
	if err := os.Symlink(outside, filepath.Join(root, "outside")); err != nil {
		t.Skipf("Symlink() unavailable: %v", err)
	}
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "pwd",
		Executable:  "pwd",
		Description: "Print cwd.",
	})

	if _, err := r.execute(context.Background(), Input{Command: "pwd", CWD: "outside"}); err == nil {
		t.Fatalf("execute() error = nil, want symlink cwd escape error")
	}
}

func TestExecuteUsesAllowedCWD(t *testing.T) {
	dir := t.TempDir()
	subdir := filepath.Join(dir, "sub")
	t.Chdir(dir)
	if err := mkdir(subdir); err != nil {
		t.Fatal(err)
	}
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "pwd",
		Executable:  "pwd",
		Description: "Print cwd.",
	})

	got, err := r.execute(context.Background(), Input{Command: "pwd", CWD: "sub"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if strings.TrimSpace(got.Stdout) != subdir {
		t.Fatalf("stdout = %q, want %q", got.Stdout, subdir)
	}
}

func TestExecuteTimesOut(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "20ms",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs: []string{
			".",
		},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "sleep",
				Executable:  "sh",
				Description: "Sleep.",
				Args:        []string{"-c", "sleep 1"},
			},
		},
	})

	got, err := r.execute(context.Background(), Input{Command: "sleep"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if !got.TimedOut || got.ExitCode != -1 {
		t.Fatalf("execute() = %#v, want timeout", got)
	}
}

func TestExecuteUsesCommandTimeoutOverride(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{"."},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "sleep",
				Executable:  "sh",
				Description: "Sleep.",
				Args:        []string{"-c", "sleep 1"},
				Timeout:     "20ms",
			},
		},
	})

	got, err := r.execute(context.Background(), Input{Command: "sleep"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if !got.TimedOut || got.ExitCode != -1 {
		t.Fatalf("execute() = %#v, want command timeout override", got)
	}
}

func TestExecuteTruncatesOutput(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 4,
		AllowedWorkdirs: []string{
			".",
		},
		Commands: []schema.LocalExecCommand{
			{
				Name:        "long",
				Executable:  "printf",
				Description: "Print long output.",
				Args:        []string{"abcdef"},
			},
		},
	})

	got, err := r.execute(context.Background(), Input{Command: "long"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if !got.Truncated || got.Stdout != "abcd" {
		t.Fatalf("execute() = %#v, want truncated output", got)
	}
}

func TestExecuteUsesCommandOutputLimitOverride(t *testing.T) {
	r := newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs:       []string{"."},
		Commands: []schema.LocalExecCommand{
			{
				Name:           "long",
				Executable:     "printf",
				Description:    "Print long output.",
				Args:           []string{"abcdef"},
				MaxOutputBytes: 4,
			},
		},
	})

	got, err := r.execute(context.Background(), Input{Command: "long"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if !got.Truncated || got.Stdout != "abcd" {
		t.Fatalf("execute() = %#v, want command output limit override", got)
	}
}

func TestExecutePassesStdin(t *testing.T) {
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "cat",
		Executable:  "cat",
		Description: "Echo stdin.",
	})

	got, err := r.execute(context.Background(), Input{Command: "cat", Stdin: "input text"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if got.Stdout != "input text" {
		t.Fatalf("stdout = %q, want stdin echoed", got.Stdout)
	}
}

func TestExecuteReturnsNonzeroExit(t *testing.T) {
	r := newTestRunner(t, schema.LocalExecCommand{
		Name:        "fail",
		Executable:  "sh",
		Description: "Fail.",
		Args:        []string{"-c", "echo bad >&2; exit 7"},
	})

	got, err := r.execute(context.Background(), Input{Command: "fail"})
	if err != nil {
		t.Fatalf("execute() error = %v", err)
	}
	if got.ExitCode != 7 || strings.TrimSpace(got.Stderr) != "bad" {
		t.Fatalf("execute() = %#v, want exit 7 with stderr", got)
	}
}

func newTestRunner(t *testing.T, command schema.LocalExecCommand) *runner {
	t.Helper()
	return newTestRunnerWithConfig(t, schema.LocalExec{
		Enabled:               true,
		DefaultTimeout:        "1s",
		DefaultMaxOutputBytes: 1024,
		AllowedWorkdirs: []string{
			".",
		},
		Commands: []schema.LocalExecCommand{command},
	})
}

func newTestRunnerWithConfig(t *testing.T, cfg schema.LocalExec) *runner {
	t.Helper()
	r, err := newRunner(cfg)
	if err != nil {
		t.Fatalf("newRunner() error = %v", err)
	}
	return r
}

func mkdir(path string) error {
	return os.Mkdir(path, 0o700)
}

type fakeToolContext struct {
	context.Context

	confirmation *toolconfirmation.ToolConfirmation
	hint         string
	payload      any
	requestCount int
}

func newFakeToolContext(confirmation *toolconfirmation.ToolConfirmation) *fakeToolContext {
	return &fakeToolContext{
		Context:      context.Background(),
		confirmation: confirmation,
	}
}

func (c *fakeToolContext) ToolConfirmation() *toolconfirmation.ToolConfirmation {
	return c.confirmation
}

func (c *fakeToolContext) RequestConfirmation(hint string, payload any) error {
	c.hint = hint
	c.payload = payload
	c.requestCount++
	return nil
}
