package platform

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"agentprovision/internal/configpath"
)

// Config stores operator-level Cloudflare provisioning defaults.
type Config struct {
	CloudflareAccountID  string `json:"cloudflare_account_id,omitempty"`
	ZoneName             string `json:"zone_name"`
	AgentHostnameSuffix  string `json:"agent_hostname_suffix"`
	WorkerSourceDir      string `json:"worker_source_dir"`
	DefaultModelProvider string `json:"default_model_provider"`
}

// Store persists one operator platform config file.
type Store struct {
	path string
}

// DefaultStore returns the production platform config store.
func DefaultStore() (Store, error) {
	path, err := configpath.PlatformConfigPath()
	if err != nil {
		return Store{}, err
	}
	return NewStore(path), nil
}

// NewStore creates a platform config store for one path.
func NewStore(path string) Store {
	return Store{path: path}
}

// NewConfig validates and normalizes one platform configuration.
func NewConfig(config Config) (Config, error) {
	config.CloudflareAccountID = strings.TrimSpace(config.CloudflareAccountID)
	config.ZoneName = cleanDNSName(config.ZoneName)
	config.AgentHostnameSuffix = cleanDNSName(config.AgentHostnameSuffix)
	config.WorkerSourceDir = strings.TrimSpace(config.WorkerSourceDir)
	config.DefaultModelProvider = strings.TrimSpace(config.DefaultModelProvider)
	if config.AgentHostnameSuffix == "" {
		config.AgentHostnameSuffix = config.ZoneName
	}
	if config.DefaultModelProvider == "" {
		config.DefaultModelProvider = "openai"
	}
	if config.ZoneName == "" {
		return Config{}, fmt.Errorf("zone name is required")
	}
	if config.AgentHostnameSuffix == "" {
		return Config{}, fmt.Errorf("agent hostname suffix is required")
	}
	if config.WorkerSourceDir == "" {
		return Config{}, fmt.Errorf("worker source directory is required")
	}
	absolute, err := filepath.Abs(config.WorkerSourceDir)
	if err != nil {
		return Config{}, fmt.Errorf("worker source directory: %w", err)
	}
	config.WorkerSourceDir = absolute
	return config, nil
}

// Load reads the platform configuration file.
func (s Store) Load() (Config, error) {
	if strings.TrimSpace(s.path) == "" {
		return Config{}, fmt.Errorf("platform config path is required")
	}
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return Config{}, ErrNotFound
	}
	if err != nil {
		return Config{}, fmt.Errorf("read platform config: %w", err)
	}
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return Config{}, fmt.Errorf("decode platform config: %w", err)
	}
	return NewConfig(config)
}

// Save writes the platform configuration file.
func (s Store) Save(config Config) (Config, error) {
	config, err := NewConfig(config)
	if err != nil {
		return Config{}, err
	}
	if strings.TrimSpace(s.path) == "" {
		return Config{}, fmt.Errorf("platform config path is required")
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return Config{}, fmt.Errorf("create platform config directory: %w", err)
	}
	data, err := json.MarshalIndent(config, "", "\t")
	if err != nil {
		return Config{}, fmt.Errorf("encode platform config: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(s.path, data, 0o600); err != nil {
		return Config{}, fmt.Errorf("write platform config: %w", err)
	}
	return config, nil
}

// Path returns the platform config file path.
func (s Store) Path() string {
	return s.path
}

// ErrNotFound reports that no platform configuration file exists.
var ErrNotFound = errors.New("platform config not found")

// cleanDNSName returns a bare hostname from a DNS name or HTTPS URL.
func cleanDNSName(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	if !strings.Contains(trimmed, "://") {
		return strings.Trim(trimmed, ".")
	}
	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Hostname() == "" {
		return strings.Trim(trimmed, ".")
	}
	return strings.Trim(parsed.Hostname(), ".")
}
