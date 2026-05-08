// This file owns memory-service logger initialization.
package logging

import (
	"io"
	stdlog "log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// Configure initializes zerolog and bridges standard-library logs into it.
func Configure(logFile string) (func(), error) {
	level, err := zerolog.ParseLevel(strings.ToLower(logLevelName()))
	if err != nil {
		return nil, err
	}
	zerolog.SetGlobalLevel(level)
	zerolog.TimeFieldFormat = time.RFC3339

	out := os.Stderr
	closeOutput := func() {}
	if strings.TrimSpace(logFile) != "" {
		if err := os.MkdirAll(filepath.Dir(logFile), 0o755); err != nil {
			return nil, err
		}
		file, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			return nil, err
		}
		out = file
		closeOutput = func() { _ = file.Close() }
	}

	log.Logger = zerolog.New(outputWriter(out)).With().Timestamp().Logger()
	stdlog.SetFlags(0)
	stdlog.SetOutput(standardLogWriter{logger: log.Logger})
	return closeOutput, nil
}

// standardLogWriter maps standard-library log writes to zerolog info events.
type standardLogWriter struct {
	logger zerolog.Logger
}

// Write logs one standard-library log message at info level.
func (w standardLogWriter) Write(p []byte) (int, error) {
	n := len(p)
	message := strings.TrimRight(string(p), "\r\n")
	if message != "" {
		w.logger.Info().Msg(message)
	}
	return n, nil
}

// logLevelName returns the configured minimum log level.
func logLevelName() string {
	level := strings.TrimSpace(os.Getenv("LOG_LEVEL"))
	if level == "" {
		return "info"
	}
	return level
}

// outputWriter returns a JSON or plain-text zerolog writer.
func outputWriter(out *os.File) io.Writer {
	if strings.EqualFold(strings.TrimSpace(os.Getenv("LOG_FORMAT")), "text") {
		return zerolog.ConsoleWriter{
			Out:        out,
			TimeFormat: time.RFC3339,
			NoColor:    true,
		}
	}
	return out
}
