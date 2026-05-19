// This file parses workflowd command-line configuration.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"workflow/internal/runtime"
)

// config stores workflowd process settings.
type config struct {
	ListenAddress  string
	DefinitionsDir string
	DatabasePath   string
	ContextBaseURL string
	CheckConfig    bool
	RequestTimeout time.Duration
}

// parseConfig parses workflowd flags and environment defaults.
func parseConfig(args []string) (config, error) {
	defaultConfig := defaultConfigDir()
	defaultData := defaultDataDir()
	cfg := config{
		ListenAddress:  envString("AGENTAWESOME_WORKFLOW_ADDR", "127.0.0.1:8092"),
		DefinitionsDir: envString("AGENTAWESOME_WORKFLOW_DEFINITIONS_DIR", filepath.Join(defaultConfig, "workflows")),
		DatabasePath:   envString("AGENTAWESOME_WORKFLOW_DB", filepath.Join(defaultData, "workflow", "workflow.db")),
		ContextBaseURL: envString("AGENTAWESOME_HARNESS_CONTEXT_BASE_URL", "http://127.0.0.1:8081/api/context"),
		RequestTimeout: envDuration("AGENTAWESOME_WORKFLOW_REQUEST_TIMEOUT", 10*time.Minute),
	}
	fs := flag.NewFlagSet("workflowd", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "workflowd listen address")
	fs.StringVar(&cfg.DefinitionsDir, "definitions", cfg.DefinitionsDir, "workflow definition directory")
	fs.StringVar(&cfg.DatabasePath, "db", cfg.DatabasePath, "workflow SQLite database path")
	fs.StringVar(&cfg.ContextBaseURL, "harness-context-base-url", cfg.ContextBaseURL, "internal harness context API base URL")
	fs.DurationVar(&cfg.RequestTimeout, "request-timeout", cfg.RequestTimeout, "upstream request timeout")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit")
	if err := fs.Parse(args); err != nil {
		return config{}, err
	}
	return cfg, cfg.Validate()
}

// Validate reports unsafe or incomplete workflowd settings.
func (c config) Validate() error {
	if strings.TrimSpace(c.ListenAddress) == "" {
		return fmt.Errorf("listen address is required")
	}
	if strings.TrimSpace(c.DefinitionsDir) == "" {
		return fmt.Errorf("definitions directory is required")
	}
	if strings.TrimSpace(c.DatabasePath) == "" {
		return fmt.Errorf("database path is required")
	}
	return nil
}

// RuntimeConfig converts process config into runtime config.
func (c config) RuntimeConfig() runtime.Config {
	return runtime.Config{
		DefinitionsDir:        c.DefinitionsDir,
		DatabasePath:          c.DatabasePath,
		HarnessContextBaseURL: c.ContextBaseURL,
		RequestTimeout:        c.RequestTimeout,
	}
}

// defaultConfigDir returns the workflowd editable config root.
func defaultConfigDir() string {
	if dir := strings.TrimSpace(os.Getenv("AGENTAWESOME_CONFIG_DIR")); dir != "" {
		return dir
	}
	appDir := defaultAppConfigDir()
	return filepath.Join(appDir, "config")
}

// defaultDataDir returns the workflowd data root.
func defaultDataDir() string {
	if dir := strings.TrimSpace(os.Getenv("AGENTAWESOME_DATA_DIR")); dir != "" {
		return dir
	}
	return filepath.Join(defaultAppConfigDir(), "data")
}

// defaultAppConfigDir returns the Agent Awesome operating-system config root.
func defaultAppConfigDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return filepath.Join(".", "agent-awesome")
	}
	return filepath.Join(configDir, "agent-awesome")
}

// envString returns a string environment value or fallback.
func envString(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// envDuration returns a duration environment value or fallback.
func envDuration(name string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}
