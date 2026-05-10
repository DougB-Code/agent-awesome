// This file parses and validates gateway runtime configuration.
package config

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"agentgateway/internal/adk"
)

const (
	// DefaultHarnessServiceName is the supervisor name for the ADK harness.
	DefaultHarnessServiceName = "harness"
	// DefaultMemoryServiceName is the supervisor name for memoryd.
	DefaultMemoryServiceName = "memory"
)

// Config stores all runtime settings for one personal gateway process.
type Config struct {
	ListenAddress                    string
	HarnessBaseURL                   string
	ContextBaseURL                   string
	ContextAPIToken                  string
	MemoryMCPURL                     string
	AppName                          string
	UserID                           string
	AuthToken                        string
	AllowedOrigin                    string
	AllowUnauthenticatedLoopbackOnly bool
	RuntimePolicyText                string
	SnapshotStatusURL                string
	SnapshotStatusToken              string
	ModelProviderID                  string
	ModelID                          string
	CheckConfig                      bool
	RequestTimeout                   time.Duration
	ServiceStartTimeout              time.Duration
	HarnessService                   ServiceConfig
	MemoryService                    ServiceConfig
	Slack                            SlackConfig
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
		ListenAddress:                    envString("AGENTAWESOME_GATEWAY_ADDR", "127.0.0.1:8070"),
		HarnessBaseURL:                   envString("AGENTAWESOME_HARNESS_API_BASE_URL", "http://127.0.0.1:8080/api"),
		ContextBaseURL:                   envString("AGENTAWESOME_CONTEXT_API_BASE_URL", "http://127.0.0.1:8081/api/context"),
		ContextAPIToken:                  envString("AGENTAWESOME_CONTEXT_API_TOKEN", ""),
		MemoryMCPURL:                     envString("AGENTAWESOME_MEMORY_MCP_URL", "http://127.0.0.1:8090/mcp"),
		AppName:                          envString("AGENTAWESOME_APP_NAME", "agent_awesome"),
		UserID:                           envString("AGENTAWESOME_USER_ID", "doug"),
		AuthToken:                        envString("AGENTAWESOME_GATEWAY_TOKEN", ""),
		AllowedOrigin:                    envString("AGENTAWESOME_ALLOWED_ORIGIN", ""),
		AllowUnauthenticatedLoopbackOnly: envBool("AGENTAWESOME_ALLOW_UNAUTHENTICATED_LOOPBACK_ONLY", true),
		RuntimePolicyText:                envString("AGENTAWESOME_RUNTIME_POLICY_TEXT", ""),
		SnapshotStatusURL:                envString("AGENTAWESOME_MEMORY_SNAPSHOT_URL", ""),
		SnapshotStatusToken:              envString("AGENTAWESOME_PERSISTENCE_TOKEN", ""),
		ModelProviderID:                  envString("AGENTAWESOME_MODEL_PROVIDER_ID", ""),
		ModelID:                          envString("AGENTAWESOME_MODEL_ID", ""),
		RequestTimeout:                   envDuration("AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT", 10*time.Minute),
		ServiceStartTimeout:              envDuration("AGENTAWESOME_SERVICE_START_TIMEOUT", 30*time.Second),
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
	cfg.HarnessService = envServiceConfig(
		DefaultHarnessServiceName,
		"AGENTAWESOME_HARNESS_HEALTH_URL",
		"AGENTAWESOME_HARNESS_COMMAND",
		"AGENTAWESOME_HARNESS_ARGS",
		"AGENTAWESOME_HARNESS_WORKDIR",
		"AGENTAWESOME_HARNESS_AUTO_START",
	)
	cfg.MemoryService = envServiceConfig(
		DefaultMemoryServiceName,
		"AGENTAWESOME_MEMORY_HEALTH_URL",
		"AGENTAWESOME_MEMORY_COMMAND",
		"AGENTAWESOME_MEMORY_ARGS",
		"AGENTAWESOME_MEMORY_WORKDIR",
		"AGENTAWESOME_MEMORY_AUTO_START",
	)

	harnessArgs := repeatedStrings(cfg.HarnessService.Arguments)
	memoryArgs := repeatedStrings(cfg.MemoryService.Arguments)
	fs := flag.NewFlagSet("agent-gateway", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "gateway listen address")
	fs.StringVar(&cfg.HarnessBaseURL, "harness-base-url", cfg.HarnessBaseURL, "upstream harness API base URL")
	fs.StringVar(&cfg.ContextBaseURL, "context-base-url", cfg.ContextBaseURL, "upstream harness context API base URL")
	fs.StringVar(&cfg.ContextAPIToken, "context-api-token", cfg.ContextAPIToken, "optional bearer token for upstream context API requests")
	fs.StringVar(&cfg.MemoryMCPURL, "memory-mcp-url", cfg.MemoryMCPURL, "memory MCP endpoint exposed in gateway status")
	fs.StringVar(&cfg.AppName, "app-name", cfg.AppName, "default ADK app name")
	fs.StringVar(&cfg.UserID, "user-id", cfg.UserID, "default ADK user id")
	fs.StringVar(&cfg.AuthToken, "auth-token", cfg.AuthToken, "optional bearer token required for gateway API requests")
	fs.StringVar(&cfg.AllowedOrigin, "allowed-origin", cfg.AllowedOrigin, "optional CORS origin for browser clients")
	fs.BoolVar(&cfg.AllowUnauthenticatedLoopbackOnly, "allow-unauthenticated-loopback-only", cfg.AllowUnauthenticatedLoopbackOnly, "allow tokenless protected routes only when the gateway bind and CORS origin are loopback-only")
	fs.StringVar(&cfg.RuntimePolicyText, "runtime-policy-text", cfg.RuntimePolicyText, "optional operator policy text injected into ADK run requests")
	fs.StringVar(&cfg.SnapshotStatusURL, "snapshot-status-url", cfg.SnapshotStatusURL, "optional authenticated snapshot endpoint used for beta status freshness")
	fs.StringVar(&cfg.SnapshotStatusToken, "snapshot-status-token", cfg.SnapshotStatusToken, "bearer token for the beta status snapshot endpoint")
	fs.StringVar(&cfg.ModelProviderID, "model-provider-id", cfg.ModelProviderID, "current non-secret model provider identifier for beta status")
	fs.StringVar(&cfg.ModelID, "model-id", cfg.ModelID, "current non-secret model identifier for beta status")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit without starting the gateway")
	fs.DurationVar(&cfg.RequestTimeout, "request-timeout", cfg.RequestTimeout, "maximum upstream request duration")
	fs.DurationVar(&cfg.ServiceStartTimeout, "service-start-timeout", cfg.ServiceStartTimeout, "maximum local service readiness wait")
	fs.BoolVar(&cfg.Slack.Enabled, "slack-enabled", cfg.Slack.Enabled, "enable Slack channel adapter")
	fs.BoolVar(&cfg.Slack.SocketMode, "slack-socket-mode", cfg.Slack.SocketMode, "connect to Slack with Socket Mode")
	fs.StringVar(&cfg.Slack.SigningSecret, "slack-signing-secret", cfg.Slack.SigningSecret, "Slack signing secret for HTTP Events API")
	fs.StringVar(&cfg.Slack.BotToken, "slack-bot-token", cfg.Slack.BotToken, "Slack bot token used to post replies")
	fs.StringVar(&cfg.Slack.AppToken, "slack-app-token", cfg.Slack.AppToken, "Slack app-level token used for Socket Mode")
	fs.StringVar(&cfg.Slack.AllowedTeamID, "slack-allowed-team-id", cfg.Slack.AllowedTeamID, "required Slack team id allow-list when Slack is enabled")
	fs.StringVar(&cfg.Slack.AllowedUserID, "slack-allowed-user-id", cfg.Slack.AllowedUserID, "required Slack user id allow-list when Slack is enabled")
	fs.StringVar(&cfg.Slack.AllowedChannelID, "slack-allowed-channel-id", cfg.Slack.AllowedChannelID, "required Slack channel id allow-list when Slack is enabled")
	bindServiceFlags(fs, &cfg.HarnessService, &harnessArgs, DefaultHarnessServiceName)
	bindServiceFlags(fs, &cfg.MemoryService, &memoryArgs, DefaultMemoryServiceName)
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}

	cfg.HarnessService.Arguments = harnessArgs
	cfg.MemoryService.Arguments = memoryArgs
	if cfg.HarnessService.HealthURL == "" {
		cfg.HarnessService.HealthURL = adk.SessionsURL(cfg.HarnessBaseURL, cfg.AppName, cfg.UserID)
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
	if c.AllowedOrigin != "" && !isHTTPOrigin(c.AllowedOrigin) {
		return fmt.Errorf("allowed origin must be an HTTP origin")
	}
	if c.AuthToken == "" {
		if !c.AllowUnauthenticatedLoopbackOnly {
			return fmt.Errorf("auth token is required when unauthenticated loopback mode is disabled")
		}
		if !isLoopbackListenAddress(c.ListenAddress) {
			return fmt.Errorf("auth token is required when gateway listens on a non-loopback address")
		}
		if c.AllowedOrigin != "" && !isLoopbackOrigin(c.AllowedOrigin) {
			return fmt.Errorf("auth token is required when allowed origin is non-local")
		}
	}
	if err := validateRequestURL("harness base URL", c.HarnessBaseURL); err != nil {
		return err
	}
	if err := validateRequestURL("context base URL", c.ContextBaseURL); err != nil {
		return err
	}
	if err := validateRequestURL("memory MCP URL", c.MemoryMCPURL); err != nil {
		return err
	}
	if c.AppName == "" {
		return fmt.Errorf("app name is required")
	}
	if c.UserID == "" {
		return fmt.Errorf("user id is required")
	}
	if err := validateOptionalTrimmedRequestURL("snapshot status URL", c.SnapshotStatusURL); err != nil {
		return err
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
	if err := validateOptionalRequestURL("health URL", s.HealthURL); err != nil {
		return err
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
	for _, required := range []struct {
		name  string
		value string
	}{
		{name: "allowed team id", value: s.AllowedTeamID},
		{name: "allowed user id", value: s.AllowedUserID},
		{name: "allowed channel id", value: s.AllowedChannelID},
	} {
		if err := validateSlackRequired(required.name, required.value); err != nil {
			return err
		}
	}
	return nil
}

// StatusView returns a sanitized representation safe for API responses.
func (c Config) StatusView() map[string]any {
	return map[string]any{
		"listen_address":                      c.ListenAddress,
		"harness_base_url":                    c.HarnessBaseURL,
		"context_base_url":                    c.ContextBaseURL,
		"has_context_api_token":               strings.TrimSpace(c.ContextAPIToken) != "",
		"memory_mcp_url":                      c.MemoryMCPURL,
		"app_name":                            c.AppName,
		"user_id":                             c.UserID,
		"auth_required":                       c.AuthToken != "",
		"allow_unauthenticated_loopback_only": c.AllowUnauthenticatedLoopbackOnly,
		"has_runtime_policy":                  strings.TrimSpace(c.RuntimePolicyText) != "",
		"snapshot_status": map[string]any{
			"url":       c.SnapshotStatusURL,
			"has_token": strings.TrimSpace(c.SnapshotStatusToken) != "",
		},
		"model": map[string]any{
			"provider_id": c.ModelProviderID,
			"model_id":    c.ModelID,
		},
		"check_config":    c.CheckConfig,
		"harness_service": c.HarnessService.StatusView(),
		"memory_service":  c.MemoryService.StatusView(),
		"slack":           c.Slack.StatusView(),
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

// validateRequestURL reports a labeled invalid HTTP request URI.
func validateRequestURL(label string, value string) error {
	if _, err := url.ParseRequestURI(value); err != nil {
		return fmt.Errorf("%s: %w", label, err)
	}
	return nil
}

// validateOptionalRequestURL skips empty URL fields and validates configured ones.
func validateOptionalRequestURL(label string, value string) error {
	if value == "" {
		return nil
	}
	return validateRequestURL(label, value)
}

// validateOptionalTrimmedRequestURL treats blank URL fields as unset.
func validateOptionalTrimmedRequestURL(label string, value string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return validateRequestURL(label, value)
}

// validateSlackRequired reports one missing Slack setting with shared wording.
func validateSlackRequired(name string, value string) error {
	if strings.TrimSpace(value) == "" {
		return fmt.Errorf("%s is required when Slack is enabled", name)
	}
	return nil
}

// envServiceConfig builds dependency supervision settings from environment keys.
func envServiceConfig(name string, healthKey string, commandKey string, argsKey string, workingDirKey string, autoStartKey string) ServiceConfig {
	return ServiceConfig{
		Name:       name,
		HealthURL:  envString(healthKey, ""),
		Command:    envString(commandKey, ""),
		Arguments:  envStringList(argsKey),
		WorkingDir: envString(workingDirKey, ""),
		AutoStart:  envBool(autoStartKey, false),
	}
}

// bindServiceFlags registers common dependency supervision flags.
func bindServiceFlags(fs *flag.FlagSet, service *ServiceConfig, args *repeatedStrings, prefix string) {
	fs.StringVar(&service.HealthURL, prefix+"-health-url", service.HealthURL, prefix+" readiness URL")
	fs.StringVar(&service.Command, prefix+"-command", service.Command, prefix+" command to start when auto-start is enabled")
	fs.Var(args, prefix+"-arg", "repeatable "+prefix+" command argument")
	fs.StringVar(&service.WorkingDir, prefix+"-workdir", service.WorkingDir, prefix+" command working directory")
	fs.BoolVar(&service.AutoStart, prefix+"-auto-start", service.AutoStart, "start "+prefix+" when it is not healthy")
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

// isLoopbackListenAddress reports whether an HTTP bind address is loopback-only.
func isLoopbackListenAddress(address string) bool {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return false
	}
	return isLoopbackHost(host)
}

// isHTTPOrigin reports whether a CORS origin is an HTTP(S) origin without path data.
func isHTTPOrigin(origin string) bool {
	parsed, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return (parsed.Scheme == "http" || parsed.Scheme == "https") &&
		parsed.Host != "" &&
		parsed.Path == "" &&
		parsed.RawQuery == "" &&
		parsed.Fragment == ""
}

// isLoopbackOrigin reports whether a CORS origin resolves to local development.
func isLoopbackOrigin(origin string) bool {
	parsed, err := url.Parse(origin)
	if err != nil || parsed.Host == "" {
		return false
	}
	host := parsed.Hostname()
	return isLoopbackHost(host)
}

// isLoopbackHost reports whether a host name or IP address is loopback-only.
func isLoopbackHost(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
