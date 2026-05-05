// This file decides whether configured local commands require user approval.
package localexec

import (
	"fmt"
	"strings"

	"agent-awesome.com/harnessinternal/config/schema"
	"agent-awesome.com/harnessinternal/tools/localexec/commandline"
	"agent-awesome.com/harnessinternal/tools/localexec/workdir"
)

// This file contains approval prompts and policy checks shared by local command
// tools. It decides whether a tool request may run; executor.go performs the
// actual process execution after approval.

const stdinPreviewLimit = 4096

// LocalExecConfirmationPayload is shown to the user when local_exec needs
// explicit approval.
type LocalExecConfirmationPayload struct {
	Tool        string           `json:"tool"`
	Command     string           `json:"command"`
	Description string           `json:"description"`
	Executable  string           `json:"executable"`
	Args        []string         `json:"args"`
	CommandLine string           `json:"command_line"`
	CWD         string           `json:"cwd"`
	Stdin       *StdinReview     `json:"stdin,omitempty"`
	Options     []ApprovalOption `json:"options"`
}

// ApprovalOption describes one action the user can choose during review.
type ApprovalOption struct {
	Action      string `json:"action"`
	Label       string `json:"label"`
	Description string `json:"description"`
}

// StdinReview describes stdin without forcing the UI to render unbounded input.
type StdinReview struct {
	Bytes     int    `json:"bytes"`
	Preview   string `json:"preview"`
	Truncated bool   `json:"truncated"`
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
		Stdin:       newStdinReview(input.Stdin),
		Options: []ApprovalOption{
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
	appendStdinReview(&b, input.Stdin)
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

// newStdinReview creates a bounded stdin preview for approval prompts.
func newStdinReview(stdin string) *StdinReview {
	if stdin == "" {
		return nil
	}
	review := &StdinReview{
		Bytes:   len(stdin),
		Preview: stdin,
	}
	if len(review.Preview) > stdinPreviewLimit {
		review.Preview = review.Preview[:stdinPreviewLimit]
		review.Truncated = true
	}
	return review
}

// appendStdinReview adds a bounded stdin preview to a human-readable prompt.
func appendStdinReview(b *strings.Builder, stdin string) {
	review := newStdinReview(stdin)
	if review == nil {
		return
	}
	b.WriteString("\n\nStdin")
	if review.Truncated {
		fmt.Fprintf(b, " preview (%d bytes, truncated)", review.Bytes)
	} else {
		fmt.Fprintf(b, " (%d bytes)", review.Bytes)
	}
	b.WriteString(":\n")
	b.WriteString(indentBlock(review.Preview))
	if review.Truncated {
		b.WriteString("\n  ... truncated ...")
	}
}

// indentBlock indents each line of a multi-line prompt section.
func indentBlock(value string) string {
	lines := strings.Split(value, "\n")
	for i, line := range lines {
		lines[i] = "  " + line
	}
	return strings.Join(lines, "\n")
}
