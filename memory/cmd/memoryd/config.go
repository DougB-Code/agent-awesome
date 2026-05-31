// This file loads and validates standalone memory daemon configuration.
package main

import (
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"
)

// Config stores memoryd runtime settings parsed from command flags.
type Config struct {
	ListenAddress   string
	DBPath          string
	DataRoot        string
	LogFile         string
	DomainPolicy    string
	WorkerCount     int
	SnapshotURL     string
	SnapshotToken   string
	SnapshotTimeout time.Duration
	AllowPublicBind bool
	CheckConfig     bool
}

// parseConfig loads memoryd settings from CLI arguments.
func parseConfig(args []string) (Config, error) {
	cfg := Config{
		ListenAddress:   "127.0.0.1:8090",
		DBPath:          "memory.db",
		DataRoot:        "data",
		WorkerCount:     2,
		SnapshotToken:   envString("AGENTAWESOME_PERSISTENCE_TOKEN", ""),
		SnapshotTimeout: 30 * time.Second,
	}
	fs := flag.NewFlagSet("memoryd", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "HTTP listen address")
	fs.StringVar(&cfg.DBPath, "db", cfg.DBPath, "SQLite database path")
	fs.StringVar(&cfg.DataRoot, "data", cfg.DataRoot, "filesystem artifact root")
	fs.StringVar(&cfg.LogFile, "log-file", cfg.LogFile, "log file path")
	fs.StringVar(&cfg.DomainPolicy, "domain-policy", cfg.DomainPolicy, "optional JSON memory domain policy path")
	fs.IntVar(&cfg.WorkerCount, "workers", cfg.WorkerCount, "background worker count")
	fs.StringVar(&cfg.SnapshotURL, "snapshot-url", cfg.SnapshotURL, "optional authenticated HTTP snapshot endpoint")
	fs.StringVar(&cfg.SnapshotToken, "snapshot-token", cfg.SnapshotToken, "bearer token for the snapshot endpoint")
	fs.DurationVar(&cfg.SnapshotTimeout, "snapshot-timeout", cfg.SnapshotTimeout, "snapshot restore and save timeout")
	fs.BoolVar(&cfg.AllowPublicBind, "allow-public-bind", cfg.AllowPublicBind, "allow memoryd to listen on a non-loopback address")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit without starting memoryd")
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}
	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

// Validate reports settings that would expose memoryd unsafely.
func (c Config) Validate() error {
	if c.ListenAddress == "" {
		return fmt.Errorf("listen address is required")
	}
	if !c.AllowPublicBind && !isLoopbackListenAddress(c.ListenAddress) {
		return fmt.Errorf("memoryd public bind requires --allow-public-bind")
	}
	if strings.TrimSpace(c.SnapshotURL) == "" && strings.TrimSpace(c.SnapshotToken) != "" {
		return fmt.Errorf("snapshot-url is required when snapshot-token is set")
	}
	if strings.TrimSpace(c.SnapshotURL) != "" && strings.TrimSpace(c.SnapshotToken) == "" {
		return fmt.Errorf("snapshot-token is required when snapshot-url is set")
	}
	return nil
}

// envString returns an environment string or fallback value.
func envString(key string, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// isLoopbackListenAddress reports whether an HTTP bind address is loopback-only.
func isLoopbackListenAddress(address string) bool {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return false
	}
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
