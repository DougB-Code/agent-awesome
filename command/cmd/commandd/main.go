// Package main starts the Agent Awesome command daemon.
package main

import (
	"os"

	"command/internal/app"
)

// main delegates to the shared command daemon app.
func main() {
	if err := app.Main("commandd", os.Args[1:]); err != nil {
		panic(err)
	}
}
