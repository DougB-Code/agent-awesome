// Package main starts the legacy Agent Awesome command MCP daemon name.
package main

import (
	"os"

	"command/internal/app"
)

// main delegates to the shared command daemon app.
func main() {
	if err := app.Main("commandmcpd", os.Args[1:]); err != nil {
		panic(err)
	}
}
