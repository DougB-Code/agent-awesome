//go:build windows

// This file contains Windows process controls for supervised MCP servers.
package mcp

import (
	"os"
	"os/exec"
)

// configureProcess applies platform-specific process settings.
func configureProcess(cmd *exec.Cmd) {
}

// terminateProcess asks the supervised process to exit gracefully.
func terminateProcess(cmd *exec.Cmd) {
	signalProcess(cmd, os.Interrupt)
}

// killProcess forcibly terminates the supervised process.
func killProcess(cmd *exec.Cmd) {
	signalProcess(cmd, os.Kill)
}

// signalProcess sends one signal when the child process exists.
func signalProcess(cmd *exec.Cmd, signal os.Signal) {
	if cmd == nil || cmd.Process == nil {
		return
	}
	_ = cmd.Process.Signal(signal)
}
