package cloudflare

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
)

// Command stores one external command invocation.
type Command struct {
	Directory string
	Name      string
	Arguments []string
	Stdin     string
	Env       map[string]string
}

// CommandResult stores public command output.
type CommandResult struct {
	Output string
}

// CommandRunner executes external provisioning commands.
type CommandRunner interface {
	Run(ctx context.Context, command Command) (CommandResult, error)
}

// ExecRunner runs commands through os/exec.
type ExecRunner struct{}

// Run executes one command and captures combined output.
func (ExecRunner) Run(ctx context.Context, command Command) (CommandResult, error) {
	cmd := exec.CommandContext(ctx, command.Name, command.Arguments...)
	cmd.Dir = command.Directory
	if command.Stdin != "" {
		cmd.Stdin = bytes.NewBufferString(command.Stdin)
	}
	if len(command.Env) > 0 {
		cmd.Env = os.Environ()
		for key, value := range command.Env {
			cmd.Env = append(cmd.Env, key+"="+value)
		}
	}
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Run(); err != nil {
		return CommandResult{Output: output.String()}, fmt.Errorf("%s %v: %w", command.Name, command.Arguments, err)
	}
	return CommandResult{Output: output.String()}, nil
}
