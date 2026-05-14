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

const logComponentEnv = "LOG_COMPONENT"

// Configure initializes process-wide zerolog and standard-library log output.
func Configure(logFile string) error {
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
		log.Logger = zerolog.New(out).With().
			Timestamp().
			Str("component", componentName(logFile, "harness")).
			Logger()
	} else {
		log.Logger = zerolog.New(zerolog.ConsoleWriter{
			Out:        out,
			TimeFormat: time.Kitchen,
			NoColor:    true,
		}).With().
			Timestamp().
			Str("component", componentName(logFile, "harness")).
			Logger()
	}

	stdlog.SetFlags(0)
	stdlog.SetOutput(standardLogWriter{logger: log.Logger})
	return nil
}

// standardLogWriter maps standard-library log writes to zerolog info events.
type standardLogWriter struct {
	logger zerolog.Logger
}

// Write logs one standard-library log message without preserving glyph levels.
func (w standardLogWriter) Write(p []byte) (int, error) {
	n := len(p)
	message := strings.TrimRight(string(p), "\r\n")
	if message != "" {
		w.logger.Info().Msg(message)
	}
	return n, nil
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

// componentName returns the stable process name attached to every log line.
func componentName(logFile string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(logComponentEnv)); value != "" {
		return value
	}
	base := strings.TrimSpace(filepath.Base(logFile))
	if base == "" || base == "." {
		return fallback
	}
	name := strings.TrimSuffix(base, filepath.Ext(base))
	if strings.TrimSpace(name) == "" {
		return fallback
	}
	return name
}
