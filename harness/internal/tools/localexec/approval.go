// This file decides whether configured local commands require user approval.
package localexec

import (
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/localexec/commandline"
	"agentawesome/internal/tools/localexec/review"
	"agentawesome/internal/tools/localexec/workdir"
)

// This file contains approval prompts and policy checks shared by local command
// tools. It decides whether a tool request may run; executor.go performs the
// actual process execution after approval.

// LocalExecConfirmationPayload is shown to the user when local_exec needs
// explicit approval.
type LocalExecConfirmationPayload struct {
	Tool        string               `json:"tool"`
	Command     string               `json:"command"`
	Description string               `json:"description"`
	Executable  string               `json:"executable"`
	Args        []string             `json:"args"`
	CommandLine string               `json:"command_line"`
	CWD         string               `json:"cwd"`
	Stdin       *review.StdinPreview `json:"stdin,omitempty"`
	Options     []review.Option      `json:"options"`
}

// confirmationPayload returns the structured review payload for a configured
// command request.
func (r *runner) confirmationPayload(input Input) LocalExecConfirmationPayload {
	commandName := strings.TrimSpace(input.Command)
	command, _ := r.catalog.command(commandName)
	cwd := strings.TrimSpace(input.CWD)
	if cwd == "" {
		cwd = "."
	}
	return LocalExecConfirmationPayload{
		Tool:        ToolName,
		Command:     commandName,
		Description: strings.TrimSpace(command.Description),
		Executable:  strings.TrimSpace(command.Executable),
		Args:        append([]string(nil), command.Args...),
		CommandLine: commandline.ReviewedCommandLine(command.Executable, command.Args),
		CWD:         cwd,
		Stdin:       review.NewStdinPreview(input.Stdin),
		Options: []review.Option{
			{Action: "deny", Label: "Deny", Description: "Do not run this configured command."},
			{Action: "approve_once", Label: "Approve exact command one time", Description: "Run only this configured command now."},
		},
	}
}

// confirmationHint builds the human-readable confirmation text shown in console
// mode and other confirmation UIs.
func (r *runner) confirmationHint(input Input) string {
	payload := r.confirmationPayload(input)
	var b strings.Builder
	b.WriteString("The agent wants to run configured local tool:\n\n  ")
	b.WriteString(payload.Command)
	b.WriteString("\n\nCommand:\n  ")
	b.WriteString(payload.CommandLine)
	if payload.Description != "" {
		b.WriteString("\n\nDescription:\n  ")
		b.WriteString(payload.Description)
	}
	b.WriteString("\n\nWorking directory:\n  ")
	b.WriteString(payload.CWD)
	review.AppendStdinPromptSection(&b, input.Stdin)
	return b.String()
}

// requiresConfirmation decides whether a configured-command request can run
// immediately or must be reviewed by the user first.
func (r *runner) requiresConfirmation(input Input) bool {
	commandName := strings.TrimSpace(input.Command)
	command, ok := r.catalog.command(commandName)
	if !ok {
		return true
	}
	// Stdin is intentionally excluded from auto-approval because user-supplied
	// input can materially change what an otherwise allowed command does.
	if input.Stdin != "" {
		return true
	}

	approval := command.Approval
	if approval.AlwaysAllow {
		return false
	}

	base, err := workdir.ExecutionBase()
	if err != nil {
		return true
	}

	if approval.AlwaysAllowWithinWorkspace {
		cwd, err := workdir.ResolveCWD(base, input.CWD, r.catalog.cfg.AllowedWorkdirs)
		if err != nil {
			return true
		}
		canonicalBase, err := workdir.CanonicalPath(base)
		if err != nil {
			return true
		}
		if workdir.PathWithin(cwd, canonicalBase) {
			return false
		}
	}

	for _, prefix := range approval.AlwaysAllowCommandPrefixes {
		if strings.HasPrefix(commandLine(command), strings.TrimSpace(prefix)) {
			return false
		}
	}

	return true
}

// commandLine renders a configured command as a simple command-prefix string
// for approval checks.
func commandLine(command schema.LocalExecCommand) string {
	parts := make([]string, 0, 1+len(command.Args))
	parts = append(parts, strings.TrimSpace(command.Executable))
	parts = append(parts, command.Args...)
	return strings.Join(parts, " ")
}
