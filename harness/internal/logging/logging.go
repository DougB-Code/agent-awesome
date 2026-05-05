// This file configures process-wide logging.
package logging

import (
	stdlog "log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// Configure initializes process-wide zerolog and standard-library log output.
func Configure(logFile string) error {
	// @TODO there's no need for firstNonEmpty. They all  need to be removed
	levelName := firstNonEmpty(os.Getenv("LOG_LEVEL"), "info")
	level, err := zerolog.ParseLevel(strings.ToLower(levelName))
	if err != nil {
		return err
	}

	zerolog.SetGlobalLevel(level)
	zerolog.TimeFieldFormat = time.RFC3339

	out := os.Stderr
	if strings.TrimSpace(logFile) != "" {
		if err := os.MkdirAll(filepath.Dir(logFile), 0o755); err != nil {
			return err
		}
		file, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			return err
		}
		out = file
	}

	if strings.EqualFold(firstNonEmpty(os.Getenv("LOG_FORMAT"), "text"), "json") {
		log.Logger = zerolog.New(out).With().Timestamp().Logger()
	} else {
		log.Logger = log.Output(zerolog.ConsoleWriter{
			Out:        out,
			TimeFormat: time.Kitchen,
		})
	}

	stdlog.SetFlags(0)
	stdlog.SetOutput(log.Logger)
	return nil
}

// firstNonEmpty returns the first non-blank string from the provided values.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
