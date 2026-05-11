// Package main provides Agent Awesome provisioning commands.
package main

import (
	"fmt"
	"os"
)

// main parses commands and exits with an operator-friendly status.
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "agent-awesome-provision: %v\n", err)
		os.Exit(1)
	}
}

// run dispatches the requested provisioning command.
func run(args []string) error {
	if len(args) < 1 {
		return usageError()
	}
	switch args[0] {
	case "check":
		return checkConfig(args[1:])
	case "cloudflare":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision cloudflare <render|apply>")
		}
		switch args[1] {
		case "render":
			return renderCloudflare(args[2:])
		case "apply":
			return applyCloudflare(args[2:])
		default:
			return fmt.Errorf("unknown cloudflare command %q", args[1])
		}
	case "platform":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision platform <init|show>")
		}
		switch args[1] {
		case "init":
			return initPlatform(args[2:])
		case "show":
			return showPlatform(args[2:])
		default:
			return fmt.Errorf("unknown platform command %q", args[1])
		}
	case "credentials":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision credentials <set|remove>")
		}
		switch args[1] {
		case "set":
			return setCredential(args[2:])
		case "remove":
			return removeCredential(args[2:])
		default:
			return fmt.Errorf("unknown credentials command %q", args[1])
		}
	case "agent":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision agent <list|status|delete>")
		}
		switch args[1] {
		case "list":
			return listAgents(args[2:])
		case "status":
			return statusAgent(args[2:])
		case "delete":
			return deleteAgent(args[2:])
		default:
			return fmt.Errorf("unknown agent command %q", args[1])
		}
	default:
		return usageError()
	}
}

// usageError returns the top-level command help as an error.
func usageError() error {
	return fmt.Errorf("usage: agent-awesome-provision <check|platform|credentials|cloudflare|agent> <command>")
}
