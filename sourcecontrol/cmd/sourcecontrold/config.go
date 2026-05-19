// This file parses sourcecontrold command-line configuration.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"sourcecontrol/internal/sourcecontrol"
)

// config stores sourcecontrold process settings.
type config struct {
	ListenAddress string
	BuildDir      string
	CheckConfig   bool
	SourceControl sourcecontrol.Config
}

// parseConfig parses sourcecontrold flags and environment defaults.
func parseConfig(args []string) (config, error) {
	cfg := config{
		ListenAddress: envString("AGENTAWESOME_SOURCECONTROL_ADDR", "127.0.0.1:8095"),
		BuildDir:      envString("AGENTAWESOME_SOURCECONTROL_BUILD_DIR", filepath.Join("build", "sourcecontrol")),
	}
	sourceCfg := sourcecontrol.Config{
		Timeout: envDuration("AGENTAWESOME_SOURCECONTROL_TIMEOUT", 2*time.Minute),
	}
	fs := flag.NewFlagSet("sourcecontrold", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "sourcecontrold listen address")
	fs.StringVar(&cfg.BuildDir, "build-dir", cfg.BuildDir, "sourcecontrol build state directory")
	fs.DurationVar(&sourceCfg.Timeout, "timeout", sourceCfg.Timeout, "Git command timeout")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit")
	if err := fs.Parse(args); err != nil {
		return config{}, err
	}
	sourceCfg.BuildDir = cfg.BuildDir
	cfg.SourceControl = sourceCfg
	return cfg, cfg.Validate()
}

// Validate reports unsafe or incomplete sourcecontrold settings.
func (c config) Validate() error {
	if strings.TrimSpace(c.ListenAddress) == "" {
		return fmt.Errorf("listen address is required")
	}
	if strings.TrimSpace(c.BuildDir) == "" {
		return fmt.Errorf("build directory is required")
	}
	return nil
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
