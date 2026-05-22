// This file owns shared process-wide logging initialization.
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

const (
	logComponentEnv = "LOG_COMPONENT"
	logFormatEnv    = "LOG_FORMAT"
	logLevelEnv     = "LOG_LEVEL"
)

// Format identifies a supported log output encoding.
type Format string

const (
	// FormatJSON writes structured zerolog events.
	FormatJSON Format = "json"
	// FormatText writes plain console-oriented zerolog events.
	FormatText Format = "text"
)

// Options describes one service's logging defaults.
type Options struct {
	LogFile           string
	ComponentFallback string
	DefaultFormat     Format
	ConsoleTimeFormat string
}

// Configure initializes zerolog and bridges standard-library logs into it.
func Configure(opts Options) (func(), error) {
	level, err := zerolog.ParseLevel(strings.ToLower(defaultedEnv(logLevelEnv, "info")))
	if err != nil {
		return nil, err
	}
	zerolog.SetGlobalLevel(level)
	zerolog.TimeFieldFormat = time.RFC3339

	out, closeOutput, err := openOutput(opts.LogFile)
	if err != nil {
		return nil, err
	}
	log.Logger = zerolog.New(outputWriter(out, selectedFormat(opts), opts.ConsoleTimeFormat)).With().
		Timestamp().
		Str("component", componentName(opts.LogFile, opts.ComponentFallback)).
		Logger()
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

// openOutput returns stderr or an append-only log file.
func openOutput(logFile string) (*os.File, func(), error) {
	if strings.TrimSpace(logFile) == "" {
		return os.Stderr, func() {}, nil
	}
	if err := os.MkdirAll(filepath.Dir(logFile), 0o755); err != nil {
		return nil, nil, err
	}
	file, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, nil, err
	}
	return file, func() { _ = file.Close() }, nil
}

// outputWriter returns a JSON or plain-text zerolog writer.
func outputWriter(out *os.File, format Format, consoleTimeFormat string) io.Writer {
	if format != FormatText {
		return out
	}
	if strings.TrimSpace(consoleTimeFormat) == "" {
		consoleTimeFormat = time.RFC3339
	}
	return zerolog.ConsoleWriter{
		Out:        out,
		TimeFormat: consoleTimeFormat,
		NoColor:    true,
	}
}

// selectedFormat returns the requested log format or the service default.
func selectedFormat(opts Options) Format {
	format := strings.TrimSpace(os.Getenv(logFormatEnv))
	if strings.EqualFold(format, string(FormatJSON)) {
		return FormatJSON
	}
	if strings.EqualFold(format, string(FormatText)) {
		return FormatText
	}
	if opts.DefaultFormat != "" {
		return opts.DefaultFormat
	}
	return FormatJSON
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

// defaultedEnv returns the environment value or a fallback when blank.
func defaultedEnv(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
