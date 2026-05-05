package main

import (
	"context"

	"agent-awesome.com/harnesscmd/agent-awesome/cli"
)

// main starts the Agent Awesome CLI with the process context.
func main() {
	cli.Execute(context.Background())
}
