//go:build !windows

// This file contains Unix process-group controls for supervised MCP servers.
package mcp

import (
	"os/exec"
	"syscall"
)

// configureProcess isolates a supervised server into its own process group.
func configureProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}

// terminateProcess asks the supervised process group to exit gracefully.
func terminateProcess(cmd *exec.Cmd) {
	signalProcessGroup(cmd, syscall.SIGTERM)
}

// killProcess forcibly terminates a supervised process group.
func killProcess(cmd *exec.Cmd) {
	signalProcessGroup(cmd, syscall.SIGKILL)
}

// signalProcessGroup sends a signal to the process group when available.
func signalProcessGroup(cmd *exec.Cmd, signal syscall.Signal) {
	if cmd == nil || cmd.Process == nil {
		return
	}
	pgid, err := syscall.Getpgid(cmd.Process.Pid)
	if err == nil {
		_ = syscall.Kill(-pgid, signal)
		return
	}
	_ = cmd.Process.Signal(signal)
}
