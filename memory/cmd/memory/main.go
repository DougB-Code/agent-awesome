// Package main keeps the historical memory command path buildable.
package main

import (
	"memory/internal/logging"

	"github.com/rs/zerolog/log"
)

// main prints guidance for the standalone memory service command.
func main() {
	closeLog, err := logging.Configure("")
	if err != nil {
		log.Fatal().Err(err).Msg("configure logging")
	}
	defer closeLog()
	log.Info().Msg("memory is a library package; run `go run ./cmd/memoryd` to start the memory service")
}
