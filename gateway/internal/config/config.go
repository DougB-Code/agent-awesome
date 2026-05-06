package config

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"time"
)

// Config stores all runtime settings for one personal gateway process.
type Config struct {
	ListenAddress       string
	HarnessBaseURL      string
	ContextBaseURL      string
	MemoryMCPURL        string
	AppName             string
	UserID              string
	AuthToken           string
	AllowedOrigin       string
	RequestTimeout      time.Duration
	ServiceStartTimeout time.Duration
	HarnessService      ServiceConfig
	MemoryService       ServiceConfig
	Slack               SlackConfig
}

// ServiceConfig stores local process supervision settings for one dependency.
type ServiceConfig struct {
	Name       string
	HealthURL  string
	Command    string
	Arguments  []string
	WorkingDir string
	AutoStart  bool
}

// SlackConfig stores Slack channel settings for HTTP and Socket Mode ingress.
type SlackConfig struct {
	Enabled          bool
	SocketMode       bool
	SigningSecret    string
	BotToken         string
	AppToken         string
	AllowedTeamID    string
	AllowedUserID    string
	AllowedChannelID string
}

// FromFlags parses gateway configuration from CLI flags and environment values.
func FromFlags(args []string) (Config, error) {
	cfg := Config{
		ListenAddress:       envString("AGENTAWESOME_GATEWAY_ADDR", "127.0.0.1:8070"),
		HarnessBaseURL:      envString("AGENTAWESOME_HARNESS_API_BASE_URL", "http://127.0.0.1:8080/api"),
		ContextBaseURL:      envString("AGENTAWESOME_CONTEXT_API_BASE_URL", "http://127.0.0.1:8081/api/context"),
		MemoryMCPURL:        envString("AGENTAWESOME_MEMORY_MCP_URL", "http://127.0.0.1:8090/mcp"),
		AppName:             envString("AGENTAWESOME_APP_NAME", "personal_pilot"),
		UserID:              envString("AGENTAWESOME_USER_ID", "doug"),
		AuthToken:           envString("AGENTAWESOME_GATEWAY_TOKEN", ""),
		AllowedOrigin:       envString("AGENTAWESOME_ALLOWED_ORIGIN", ""),
		RequestTimeout:      envDuration("AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT", 10*time.Minute),
		ServiceStartTimeout: envDuration("AGENTAWESOME_SERVICE_START_TIMEOUT", 30*time.Second),
	}
	cfg.Slack = SlackConfig{
		Enabled:          envBool("SLACK_ENABLED", false),
		SocketMode:       envBool("SLACK_SOCKET_MODE", false),
		SigningSecret:    envString("SLACK_SIGNING_SECRET", ""),
		BotToken:         envString("SLACK_BOT_TOKEN", ""),
		AppToken:         envString("SLACK_APP_TOKEN", ""),
		AllowedTeamID:    envString("SLACK_ALLOWED_TEAM_ID", ""),
		AllowedUserID:    envString("SLACK_ALLOWED_USER_ID", ""),
		AllowedChannelID: envString("SLACK_ALLOWED_CHANNEL_ID", ""),
	}
	cfg.HarnessService = ServiceConfig{
		Name:       "harness",
		HealthURL:  envString("AGENTAWESOME_HARNESS_HEALTH_URL", ""),
		Command:    envString("AGENTAWESOME_HARNESS_COMMAND", ""),
		Arguments:  envStringList("AGENTAWESOME_HARNESS_ARGS"),
		WorkingDir: envString("AGENTAWESOME_HARNESS_WORKDIR", ""),
		AutoStart:  envBool("AGENTAWESOME_HARNESS_AUTO_START", false),
	}
	cfg.MemoryService = ServiceConfig{
		Name:       "memory",
		HealthURL:  envString("AGENTAWESOME_MEMORY_HEALTH_URL", ""),
		Command:    envString("AGENTAWESOME_MEMORY_COMMAND", ""),
		Arguments:  envStringList("AGENTAWESOME_MEMORY_ARGS"),
		WorkingDir: envString("AGENTAWESOME_MEMORY_WORKDIR", ""),
		AutoStart:  envBool("AGENTAWESOME_MEMORY_AUTO_START", false),
	}

	harnessArgs := repeatedStrings(cfg.HarnessService.Arguments)
	memoryArgs := repeatedStrings(cfg.MemoryService.Arguments)
	fs := flag.NewFlagSet("agent-gateway", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "gateway listen address")
	fs.StringVar(&cfg.HarnessBaseURL, "harness-base-url", cfg.HarnessBaseURL, "upstream harness API base URL")
	fs.StringVar(&cfg.ContextBaseURL, "context-base-url", cfg.ContextBaseURL, "upstream harness context API base URL")
	fs.StringVar(&cfg.MemoryMCPURL, "memory-mcp-url", cfg.MemoryMCPURL, "memory MCP endpoint exposed in gateway status")
	fs.StringVar(&cfg.AppName, "app-name", cfg.AppName, "default ADK app name")
	fs.StringVar(&cfg.UserID, "user-id", cfg.UserID, "default ADK user id")
	fs.StringVar(&cfg.AuthToken, "auth-token", cfg.AuthToken, "optional bearer token required for gateway API requests")
	fs.StringVar(&cfg.AllowedOrigin, "allowed-origin", cfg.AllowedOrigin, "optional CORS origin for browser clients")
	fs.DurationVar(&cfg.RequestTimeout, "request-timeout", cfg.RequestTimeout, "maximum upstream request duration")
	fs.DurationVar(&cfg.ServiceStartTimeout, "service-start-timeout", cfg.ServiceStartTimeout, "maximum local service readiness wait")
	fs.BoolVar(&cfg.Slack.Enabled, "slack-enabled", cfg.Slack.Enabled, "enable Slack channel adapter")
	fs.BoolVar(&cfg.Slack.SocketMode, "slack-socket-mode", cfg.Slack.SocketMode, "connect to Slack with Socket Mode")
	fs.StringVar(&cfg.Slack.SigningSecret, "slack-signing-secret", cfg.Slack.SigningSecret, "Slack signing secret for HTTP Events API")
	fs.StringVar(&cfg.Slack.BotToken, "slack-bot-token", cfg.Slack.BotToken, "Slack bot token used to post replies")
	fs.StringVar(&cfg.Slack.AppToken, "slack-app-token", cfg.Slack.AppToken, "Slack app-level token used for Socket Mode")
	fs.StringVar(&cfg.Slack.AllowedTeamID, "slack-allowed-team-id", cfg.Slack.AllowedTeamID, "optional Slack team id allow-list")
	fs.StringVar(&cfg.Slack.AllowedUserID, "slack-allowed-user-id", cfg.Slack.AllowedUserID, "optional Slack user id allow-list")
	fs.StringVar(&cfg.Slack.AllowedChannelID, "slack-allowed-channel-id", cfg.Slack.AllowedChannelID, "optional Slack channel id allow-list")
	fs.StringVar(&cfg.HarnessService.HealthURL, "harness-health-url", cfg.HarnessService.HealthURL, "harness readiness URL")
	fs.StringVar(&cfg.HarnessService.Command, "harness-command", cfg.HarnessService.Command, "harness command to start when auto-start is enabled")
	fs.Var(&harnessArgs, "harness-arg", "repeatable harness command argument")
	fs.StringVar(&cfg.HarnessService.WorkingDir, "harness-workdir", cfg.HarnessService.WorkingDir, "harness command working directory")
	fs.BoolVar(&cfg.HarnessService.AutoStart, "harness-auto-start", cfg.HarnessService.AutoStart, "start the harness when it is not healthy")
	fs.StringVar(&cfg.MemoryService.HealthURL, "memory-health-url", cfg.MemoryService.HealthURL, "memory readiness URL")
	fs.StringVar(&cfg.MemoryService.Command, "memory-command", cfg.MemoryService.Command, "memory command to start when auto-start is enabled")
	fs.Var(&memoryArgs, "memory-arg", "repeatable memory command argument")
	fs.StringVar(&cfg.MemoryService.WorkingDir, "memory-workdir", cfg.MemoryService.WorkingDir, "memory command working directory")
	fs.BoolVar(&cfg.MemoryService.AutoStart, "memory-auto-start", cfg.MemoryService.AutoStart, "start memory when it is not healthy")
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}

	cfg.HarnessService.Arguments = harnessArgs
	cfg.MemoryService.Arguments = memoryArgs
	if cfg.HarnessService.HealthURL == "" {
		cfg.HarnessService.HealthURL = harnessSessionsURL(cfg.HarnessBaseURL, cfg.AppName, cfg.UserID)
	}
	if cfg.MemoryService.HealthURL == "" {
		cfg.MemoryService.HealthURL = memoryHealthURL(cfg.MemoryMCPURL)
	}
	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

// Validate reports configuration values that would make the gateway unsafe.
func (c Config) Validate() error {
	if c.ListenAddress == "" {
		return fmt.Errorf("listen address is required")
	}
	if _, err := url.ParseRequestURI(c.HarnessBaseURL); err != nil {
		return fmt.Errorf("harness base URL: %w", err)
	}
	if _, err := url.ParseRequestURI(c.ContextBaseURL); err != nil {
		return fmt.Errorf("context base URL: %w", err)
	}
	if _, err := url.ParseRequestURI(c.MemoryMCPURL); err != nil {
		return fmt.Errorf("memory MCP URL: %w", err)
	}
	if c.AppName == "" {
		return fmt.Errorf("app name is required")
	}
	if c.UserID == "" {
		return fmt.Errorf("user id is required")
	}
	if err := c.Slack.Validate(); err != nil {
		return fmt.Errorf("slack: %w", err)
	}
	if err := c.HarnessService.Validate(); err != nil {
		return fmt.Errorf("harness service: %w", err)
	}
	if err := c.MemoryService.Validate(); err != nil {
		return fmt.Errorf("memory service: %w", err)
	}
	return nil
}

// Validate reports invalid local process supervision settings.
func (s ServiceConfig) Validate() error {
	if s.Name == "" {
		return fmt.Errorf("name is required")
	}
	if s.HealthURL != "" {
		if _, err := url.ParseRequestURI(s.HealthURL); err != nil {
			return fmt.Errorf("health URL: %w", err)
		}
	}
	if s.AutoStart && s.Command == "" {
		return fmt.Errorf("command is required when auto-start is enabled")
	}
	return nil
}

// Validate reports invalid Slack channel settings.
func (s SlackConfig) Validate() error {
	if !s.Enabled {
		return nil
	}
	if s.BotToken == "" {
		return fmt.Errorf("bot token is required when Slack is enabled")
	}
	if s.SocketMode && s.AppToken == "" {
		return fmt.Errorf("app token is required when Slack Socket Mode is enabled")
	}
	if !s.SocketMode && s.SigningSecret == "" {
		return fmt.Errorf("signing secret is required when Slack HTTP Events API is enabled")
	}
	return nil
}

// StatusView returns a sanitized representation safe for API responses.
func (c Config) StatusView() map[string]any {
	return map[string]any{
		"listen_address":   c.ListenAddress,
		"harness_base_url": c.HarnessBaseURL,
		"context_base_url": c.ContextBaseURL,
		"memory_mcp_url":   c.MemoryMCPURL,
		"app_name":         c.AppName,
		"user_id":          c.UserID,
		"auth_required":    c.AuthToken != "",
		"harness_service":  c.HarnessService.StatusView(),
		"memory_service":   c.MemoryService.StatusView(),
		"slack":            c.Slack.StatusView(),
	}
}

// StatusView returns sanitized service supervision settings.
func (s ServiceConfig) StatusView() map[string]any {
	return map[string]any{
		"name":        s.Name,
		"health_url":  s.HealthURL,
		"command":     s.Command,
		"working_dir": s.WorkingDir,
		"auto_start":  s.AutoStart,
	}
}

// StatusView returns sanitized Slack channel settings.
func (s SlackConfig) StatusView() map[string]any {
	return map[string]any{
		"enabled":            s.Enabled,
		"socket_mode":        s.SocketMode,
		"has_signing_secret": s.SigningSecret != "",
		"has_bot_token":      s.BotToken != "",
		"has_app_token":      s.AppToken != "",
		"allowed_team_id":    s.AllowedTeamID,
		"allowed_user_id":    s.AllowedUserID,
		"allowed_channel_id": s.AllowedChannelID,
	}
}

// repeatedStrings accumulates repeated string flag values.
type repeatedStrings []string

// String formats the repeated values for flag help output.
func (r repeatedStrings) String() string {
	bytes, _ := json.Marshal([]string(r))
	return string(bytes)
}

// Set appends one repeated flag value.
func (r *repeatedStrings) Set(value string) error {
	*r = append(*r, value)
	return nil
}

// envString returns an environment string or fallback value.
func envString(key string, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// envBool returns a parsed boolean environment value or fallback value.
func envBool(key string, fallback bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

// envDuration returns a parsed duration environment value or fallback value.
func envDuration(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}

// envStringList returns a JSON string array from an environment variable.
func envStringList(key string) []string {
	value := os.Getenv(key)
	if value == "" {
		return nil
	}
	var values []string
	if err := json.Unmarshal([]byte(value), &values); err != nil {
		return nil
	}
	return values
}

// harnessSessionsURL derives the ADK sessions endpoint used for readiness.
func harnessSessionsURL(baseURL string, appName string, userID string) string {
	return trimTrailingSlash(baseURL) + "/apps/" + url.PathEscape(appName) + "/users/" + url.PathEscape(userID) + "/sessions"
}

// memoryHealthURL derives the memory process health endpoint from the MCP URL.
func memoryHealthURL(mcpURL string) string {
	parsed, err := url.Parse(mcpURL)
	if err != nil {
		return ""
	}
	parsed.Path = "/healthz"
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String()
}

// trimTrailingSlash removes one trailing slash from a URL string.
func trimTrailingSlash(value string) string {
	for len(value) > 0 && value[len(value)-1] == '/' {
		value = value[:len(value)-1]
	}
	return value
}
