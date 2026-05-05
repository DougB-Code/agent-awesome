package main

import (
	"context"

	"agentawesome/cmd/agent-awesome/cli"
)

// main starts the Agent Awesome CLI with the process context.
func main() {
	cli.Execute(context.Background())
}
