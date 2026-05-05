// This file executes reviewed local processes.
package localexec

import (
	"context"
	"errors"
	"os/exec"
	"strings"

	"agent-awesome.com/harnessinternal/tools/localexec/execspec"
)

type processExecutor struct{}

// Execute runs a reviewed local process and captures bounded output.
func (processExecutor) Execute(ctx context.Context, call execspec.ToolCall) (execspec.Output, error) {
	execCtx, cancel := context.WithTimeout(ctx, call.Timeout)
	defer cancel()

	cmd := exec.CommandContext(execCtx, call.Executable, call.Args...)
	cmd.Dir = call.CWD
	if call.Stdin != "" {
		cmd.Stdin = strings.NewReader(call.Stdin)
	}

	var stdout, stderr limitedBuffer
	stdout.limit = call.OutputLimit
	stderr.limit = call.OutputLimit
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	timedOut := errors.Is(execCtx.Err(), context.DeadlineExceeded)

	// Non-zero process exits are returned as command output, not Go errors, so
	// the agent can inspect stderr and the exit code.
	out := execspec.Output{
		ExitCode:  exitCode(err, timedOut),
		Stdout:    stdout.String(),
		Stderr:    stderr.String(),
		TimedOut:  timedOut,
		Truncated: stdout.truncated || stderr.truncated,
	}
	if err != nil && !isExitError(err) && !timedOut {
		return out, err
	}
	return out, nil
}

// exitCode converts command execution errors into the numeric exit code exposed
// to the agent.
func exitCode(err error, timedOut bool) int {
	if err == nil {
		return 0
	}
	if timedOut {
		return -1
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

// isExitError reports whether an error is a normal process exit failure.
func isExitError(err error) bool {
	var exitErr *exec.ExitError
	return errors.As(err, &exitErr)
}
