// This file indexes configured local command aliases.
package localexec

import (
	"fmt"
	"strings"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/localexec/execspec"
	"agentawesome/internal/tools/localexec/workdir"
)

// commandCatalog resolves configured local_exec aliases into executable tool
// calls.
type commandCatalog struct {
	cfg      schema.LocalExec
	commands map[string]schema.LocalExecCommand
}

// newCommandCatalog normalizes configured command names and executables into a
// lookup map used while serving tool calls.
func newCommandCatalog(cfg schema.LocalExec) commandCatalog {
	commands := make(map[string]schema.LocalExecCommand, len(cfg.Commands))
	for _, command := range cfg.Commands {
		name := strings.TrimSpace(command.Name)
		command.Name = name
		command.Executable = strings.TrimSpace(command.Executable)
		commands[name] = command
	}
	return commandCatalog{
		cfg:      cfg,
		commands: commands,
	}
}

// command returns a configured command by normalized alias.
func (c commandCatalog) command(name string) (schema.LocalExecCommand, bool) {
	command, ok := c.commands[strings.TrimSpace(name)]
	return command, ok
}

// configuredToolCall validates an alias request and resolves it into a ToolCall.
func (c commandCatalog) configuredToolCall(input Input) (execspec.ToolCall, error) {
	commandName := strings.TrimSpace(input.Command)
	if commandName == "" {
		return execspec.ToolCall{}, fmt.Errorf("command is required")
	}
	command, ok := c.command(commandName)
	if !ok {
		return execspec.ToolCall{}, fmt.Errorf("command %q is not allowed", commandName)
	}
	base, err := workdir.ExecutionBase()
	if err != nil {
		return execspec.ToolCall{}, err
	}
	cwd, err := workdir.ResolveCWD(base, input.CWD, c.cfg.AllowedWorkdirs)
	if err != nil {
		return execspec.ToolCall{}, err
	}

	return execspec.ToolCall{
		Executable:  command.Executable,
		Args:        append([]string(nil), command.Args...),
		CWD:         cwd,
		Stdin:       input.Stdin,
		Timeout:     commandTimeout(c.cfg, command),
		OutputLimit: commandOutputLimit(c.cfg, command),
	}, nil
}

// commandTimeout returns the command-specific timeout or the local-exec default.
func commandTimeout(cfg schema.LocalExec, command schema.LocalExecCommand) time.Duration {
	if strings.TrimSpace(command.Timeout) == "" {
		return cfg.DefaultTimeoutDuration()
	}
	timeout, err := time.ParseDuration(strings.TrimSpace(command.Timeout))
	if err != nil {
		return cfg.DefaultTimeoutDuration()
	}
	return timeout
}

// commandOutputLimit returns the command-specific output limit or the default.
func commandOutputLimit(cfg schema.LocalExec, command schema.LocalExecCommand) int {
	if command.MaxOutputBytes == 0 {
		return cfg.DefaultOutputLimit()
	}
	return command.MaxOutputBytes
}
