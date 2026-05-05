// This file defines local process execution data structures.
package execspec

import "time"

// Output is the command result returned to the agent.
type Output struct {
	ExitCode  int    `json:"exit_code"`
	Stdout    string `json:"stdout"`
	Stderr    string `json:"stderr"`
	TimedOut  bool   `json:"timed_out"`
	Truncated bool   `json:"truncated"`
}

// ToolCall is a fully resolved local command execution request.
type ToolCall struct {
	Executable  string
	Args        []string
	CWD         string
	Stdin       string
	Timeout     time.Duration
	OutputLimit int
}
