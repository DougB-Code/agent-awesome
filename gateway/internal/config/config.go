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
	// DefaultHarnessServiceName is the supervisor name for the assistant harness.
	DefaultHarnessServiceName = "harness"
	// DefaultMemoryServiceName is the supervisor name for memoryd.
	DefaultMemoryServiceName = "memory"
	// DefaultRunbookServiceName is the supervisor name for the runbook service.
	DefaultRunbookServiceName = "runbook"
)

// Config stores all runtime settings for one personal gateway process.
type Config struct {
	ListenAddress                    string
	GatewayBaseURL                   string
	HarnessBaseURL                   string
	ContextBaseURL                   string
	RunbookBaseURL                   string
	ContextAPIToken                  string
	MemoryMCPURL                     string
	MemoryDomains                    []MemoryDomain
	MemoryPolicy                     MemoryPolicy
	MemoryServices                   []MemoryDomainService
	AgentProfiles                    []AgentProfile
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
	LogFile                          string
	CheckConfig                      bool
	HarnessEmbeddedServices          bool
	RequestTimeout                   time.Duration
	ServiceStartTimeout              time.Duration
	HarnessService                   ServiceConfig
	MemoryService                    ServiceConfig
	RunbookService                   ServiceConfig
	Slack                            SlackConfig
}

// MemoryDomain stores one gateway-routable memory security boundary.
type MemoryDomain struct {
	ID        string `json:"id"`
	Label     string `json:"label"`
	Endpoint  string `json:"endpoint"`
	HealthURL string `json:"health_url,omitempty"`
}

// MemoryPolicy stores the active agent profile's memory access grants.
type MemoryPolicy struct {
	Actor                string             `json:"actor"`
	ReadDomains          []string           `json:"read_domains"`
	WriteDomains         []string           `json:"write_domains"`
	DefaultWriteDomain   string             `json:"default_write_domain"`
	AllowedSensitivities []string           `json:"allowed_sensitivities"`
	AllowedFlows         []MemoryDomainFlow `json:"allowed_flows,omitempty"`
}

// MemoryDomainFlow permits selected cross-domain writes after declassification.
type MemoryDomainFlow struct {
	From string `json:"from"`
	To   string `json:"to"`
}

// AgentProfile stores one server-side executable agent identity and grants.
type AgentProfile struct {
	ID                   string                `json:"id"`
	Label                string                `json:"label"`
	AppName              string                `json:"app_name"`
	UserID               string                `json:"user_id"`
	HarnessBaseURL       string                `json:"harness_base_url,omitempty"`
	ContextBaseURL       string                `json:"context_base_url,omitempty"`
	Actor                string                `json:"actor"`
	ReadDomains          []string              `json:"read_domains"`
	WriteDomains         []string              `json:"write_domains"`
	DefaultWriteDomain   string                `json:"default_write_domain"`
	AllowedSensitivities []string              `json:"allowed_sensitivities"`
	AllowedFlows         []MemoryDomainFlow    `json:"allowed_flows,omitempty"`
	SlackBindings        []SlackProfileBinding `json:"slack_bindings,omitempty"`
}

// SlackProfileBinding maps one Slack scope to an agent profile.
type SlackProfileBinding struct {
	TeamID         string   `json:"team_id"`
	ChannelID      string   `json:"channel_id"`
	AllowedUserIDs []string `json:"allowed_user_ids"`
}

// MemoryDomainService stores process supervision for one memory domain.
type MemoryDomainService struct {
	DomainID   string   `json:"domain_id"`
	Name       string   `json:"name,omitempty"`
	HealthURL  string   `json:"health_url,omitempty"`
	Command    string   `json:"command,omitempty"`
	Arguments  []string `json:"arguments,omitempty"`
	WorkingDir string   `json:"working_directory,omitempty"`
	AutoStart  bool     `json:"auto_start,omitempty"`
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
	memoryDomainsJSON := envString("AGENTAWESOME_MEMORY_DOMAINS_JSON", "")
	memoryPolicyJSON := envString("AGENTAWESOME_MEMORY_POLICY_JSON", "")
	memoryServicesJSON := envString("AGENTAWESOME_MEMORY_SERVICES_JSON", "")
	agentProfilesJSON := envString("AGENTAWESOME_AGENT_PROFILES_JSON", "")
	cfg := Config{
		ListenAddress:                    envString("AGENTAWESOME_GATEWAY_ADDR", "127.0.0.1:8070"),
		GatewayBaseURL:                   envString("AGENTAWESOME_GATEWAY_API_BASE_URL", ""),
		HarnessBaseURL:                   envString("AGENTAWESOME_HARNESS_API_BASE_URL", "http://127.0.0.1:8080/api"),
		ContextBaseURL:                   envString("AGENTAWESOME_CONTEXT_API_BASE_URL", "http://127.0.0.1:8081/api/context"),
		RunbookBaseURL:                   envString("AGENTAWESOME_RUNBOOK_BASE_URL", "http://127.0.0.1:8092/api/runbooks"),
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
		LogFile:                          envString("AGENTAWESOME_GATEWAY_LOG_FILE", ""),
		HarnessEmbeddedServices:          envBool("AGENTAWESOME_HARNESS_EMBEDDED_SERVICES", false),
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
	cfg.RunbookService = envServiceConfig(
		DefaultRunbookServiceName,
		"AGENTAWESOME_RUNBOOK_HEALTH_URL",
		"AGENTAWESOME_RUNBOOK_COMMAND",
		"AGENTAWESOME_RUNBOOK_ARGS",
		"AGENTAWESOME_RUNBOOK_WORKDIR",
		"AGENTAWESOME_RUNBOOK_AUTO_START",
	)
	harnessArgs := repeatedStrings(cfg.HarnessService.Arguments)
	memoryArgs := repeatedStrings(cfg.MemoryService.Arguments)
	runbookArgs := repeatedStrings(cfg.RunbookService.Arguments)
	fs := flag.NewFlagSet("agent-gateway", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddress, "addr", cfg.ListenAddress, "gateway listen address")
	fs.StringVar(&cfg.GatewayBaseURL, "gateway-base-url", cfg.GatewayBaseURL, "gateway API base URL used by channel adapters")
	fs.StringVar(&cfg.HarnessBaseURL, "harness-base-url", cfg.HarnessBaseURL, "upstream harness API base URL")
	fs.StringVar(&cfg.ContextBaseURL, "context-base-url", cfg.ContextBaseURL, "upstream harness context API base URL")
	fs.StringVar(&cfg.RunbookBaseURL, "runbook-base-url", cfg.RunbookBaseURL, "upstream runbook API base URL")
	fs.StringVar(&cfg.ContextAPIToken, "context-api-token", cfg.ContextAPIToken, "optional bearer token for upstream context API requests")
	fs.StringVar(&cfg.MemoryMCPURL, "memory-mcp-url", cfg.MemoryMCPURL, "memory MCP endpoint exposed in gateway status")
	fs.StringVar(&memoryDomainsJSON, "memory-domains-json", memoryDomainsJSON, "JSON memory domain list for gateway routing")
	fs.StringVar(&memoryPolicyJSON, "memory-policy-json", memoryPolicyJSON, "JSON memory access policy for the active agent profile")
	fs.StringVar(&memoryServicesJSON, "memory-services-json", memoryServicesJSON, "JSON memory service list for per-domain supervision")
	fs.StringVar(&agentProfilesJSON, "agent-profiles-json", agentProfilesJSON, "JSON agent profile list for gateway request policy")
	fs.StringVar(&cfg.AppName, "app-name", cfg.AppName, "default assistant app name")
	fs.StringVar(&cfg.UserID, "user-id", cfg.UserID, "default assistant user id")
	fs.StringVar(&cfg.AuthToken, "auth-token", cfg.AuthToken, "optional bearer token required for gateway API requests")
	fs.StringVar(&cfg.AllowedOrigin, "allowed-origin", cfg.AllowedOrigin, "optional CORS origin for browser clients")
	fs.BoolVar(&cfg.AllowUnauthenticatedLoopbackOnly, "allow-unauthenticated-loopback-only", cfg.AllowUnauthenticatedLoopbackOnly, "allow tokenless protected routes only when the gateway bind and CORS origin are loopback-only")
	fs.StringVar(&cfg.RuntimePolicyText, "runtime-policy-text", cfg.RuntimePolicyText, "optional operator policy text injected into assistant run requests")
	fs.StringVar(&cfg.SnapshotStatusURL, "snapshot-status-url", cfg.SnapshotStatusURL, "optional authenticated snapshot endpoint used for beta status freshness")
	fs.StringVar(&cfg.SnapshotStatusToken, "snapshot-status-token", cfg.SnapshotStatusToken, "bearer token for the beta status snapshot endpoint")
	fs.StringVar(&cfg.ModelProviderID, "model-provider-id", cfg.ModelProviderID, "current non-secret model provider identifier for beta status")
	fs.StringVar(&cfg.ModelID, "model-id", cfg.ModelID, "current non-secret model identifier for beta status")
	fs.StringVar(&cfg.LogFile, "log-file", cfg.LogFile, "optional gateway log file path")
	fs.BoolVar(&cfg.CheckConfig, "check-config", cfg.CheckConfig, "validate configuration and exit without starting the gateway")
	fs.BoolVar(&cfg.HarnessEmbeddedServices, "harness-embedded-services", cfg.HarnessEmbeddedServices, "start runbook services inside the harness process")
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
	bindServiceFlags(fs, &cfg.RunbookService, &runbookArgs, DefaultRunbookServiceName)
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}

	cfg.HarnessService.Arguments = harnessArgs
	cfg.MemoryService.Arguments = memoryArgs
	cfg.RunbookService.Arguments = runbookArgs
	if err := cfg.applyMemoryTopology(memoryDomainsJSON, memoryPolicyJSON); err != nil {
		return Config{}, err
	}
	if err := cfg.applyAgentProfiles(agentProfilesJSON); err != nil {
		return Config{}, err
	}
	if strings.TrimSpace(cfg.GatewayBaseURL) == "" {
		cfg.GatewayBaseURL = gatewayAPIBaseURL(cfg.ListenAddress)
	}
	if cfg.HarnessService.HealthURL == "" {
		cfg.HarnessService.HealthURL = adk.SessionsURL(cfg.HarnessBaseURL, cfg.AppName, cfg.UserID)
	}
	if cfg.MemoryService.HealthURL == "" {
		cfg.MemoryService.HealthURL = defaultMemoryServiceHealthURL(cfg.MemoryDomains, cfg.MemoryMCPURL)
	}
	if cfg.RunbookService.HealthURL == "" {
		cfg.RunbookService.HealthURL = runbookHealthURL(cfg.RunbookBaseURL)
	}
	if err := cfg.applyHarnessEmbeddedServices(); err != nil {
		return Config{}, err
	}
	if err := cfg.applyMemoryServices(memoryServicesJSON); err != nil {
		return Config{}, err
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
	if err := validateRequestURL("gateway base URL", c.GatewayBaseURL); err != nil {
		return err
	}
	if err := validateRequestURL("context base URL", c.ContextBaseURL); err != nil {
		return err
	}
	if err := validateRequestURL("runbook base URL", c.RunbookBaseURL); err != nil {
		return err
	}
	if err := validateRequestURL("memory MCP URL", c.MemoryMCPURL); err != nil {
		return err
	}
	if err := c.validateMemoryTopology(); err != nil {
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
	if err := c.RunbookService.Validate(); err != nil {
		return fmt.Errorf("runbook service: %w", err)
	}
	if err := c.validateMemoryServices(); err != nil {
		return err
	}
	if err := c.validateAgentProfiles(); err != nil {
		return err
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
	if !s.hasLegacyAllowList() {
		return nil
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
		"gateway_base_url":                    c.GatewayBaseURL,
		"harness_base_url":                    c.HarnessBaseURL,
		"context_base_url":                    c.ContextBaseURL,
		"runbook_base_url":                    c.RunbookBaseURL,
		"has_context_api_token":               strings.TrimSpace(c.ContextAPIToken) != "",
		"memory_mcp_url":                      c.MemoryMCPURL,
		"memory_domains":                      statusViews(c.MemoryDomains),
		"memory_policy":                       c.MemoryPolicy.StatusView(),
		"memory_services":                     statusViews(c.MemoryServices),
		"agent_profiles":                      statusViews(c.AgentProfiles),
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
		"has_log_file":              strings.TrimSpace(c.LogFile) != "",
		"check_config":              c.CheckConfig,
		"harness_embedded_services": c.HarnessEmbeddedServices,
		"harness_service":           c.HarnessService.StatusView(),
		"memory_service":            c.MemoryService.StatusView(),
		"runbook_service":           c.RunbookService.StatusView(),
		"slack":                     c.Slack.StatusView(),
	}
}

// StatusView returns sanitized memory domain routing settings.
func (d MemoryDomain) StatusView() map[string]any {
	return map[string]any{
		"id":         d.ID,
		"label":      d.Label,
		"endpoint":   d.Endpoint,
		"health_url": d.HealthURL,
	}
}

// MemoryPolicy returns this profile's memory grants in gateway policy shape.
func (p AgentProfile) MemoryPolicy() MemoryPolicy {
	return MemoryPolicy{
		Actor:                p.Actor,
		ReadDomains:          append([]string(nil), p.ReadDomains...),
		WriteDomains:         append([]string(nil), p.WriteDomains...),
		DefaultWriteDomain:   p.DefaultWriteDomain,
		AllowedSensitivities: append([]string(nil), p.AllowedSensitivities...),
		AllowedFlows:         append([]MemoryDomainFlow(nil), p.AllowedFlows...),
	}
}

// StatusView returns sanitized agent profile settings.
func (p AgentProfile) StatusView() map[string]any {
	return map[string]any{
		"id":               p.ID,
		"label":            p.Label,
		"app_name":         p.AppName,
		"user_id":          p.UserID,
		"harness_base_url": p.HarnessBaseURL,
		"context_base_url": p.ContextBaseURL,
		"memory_policy":    p.MemoryPolicy().StatusView(),
		"slack_bindings":   slackBindingStatusViews(p.SlackBindings),
		"slack_configured": len(p.SlackBindings) > 0,
	}
}

// ProfileByID returns one configured agent profile by id.
func (c Config) ProfileByID(profileID string) (AgentProfile, bool) {
	profileID = strings.TrimSpace(profileID)
	for _, profile := range c.AgentProfiles {
		if strings.TrimSpace(profile.ID) == profileID {
			return profile, true
		}
	}
	return AgentProfile{}, false
}

// DefaultProfile returns the first configured agent profile.
func (c Config) DefaultProfile() (AgentProfile, bool) {
	if len(c.AgentProfiles) == 0 {
		return AgentProfile{}, false
	}
	return c.AgentProfiles[0], true
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

// ServiceConfig returns the supervisor service shape for this memory domain.
func (s MemoryDomainService) ServiceConfig() ServiceConfig {
	return ServiceConfig{
		Name:       s.Name,
		HealthURL:  s.HealthURL,
		Command:    s.Command,
		Arguments:  append([]string(nil), s.Arguments...),
		WorkingDir: s.WorkingDir,
		AutoStart:  s.AutoStart,
	}
}

// StatusView returns sanitized per-domain memory service settings.
func (s MemoryDomainService) StatusView() map[string]any {
	return map[string]any{
		"domain_id":   s.DomainID,
		"name":        s.Name,
		"health_url":  s.HealthURL,
		"command":     s.Command,
		"working_dir": s.WorkingDir,
		"auto_start":  s.AutoStart,
	}
}

// MemoryServiceForDomain returns the configured supervisor service for a domain.
func (c Config) MemoryServiceForDomain(domainID string) (MemoryDomainService, bool) {
	domainID = strings.TrimSpace(domainID)
	for _, service := range c.MemoryServices {
		if strings.TrimSpace(service.DomainID) == domainID {
			return service, true
		}
	}
	return MemoryDomainService{}, false
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

// StatusView returns sanitized memory policy settings.
func (p MemoryPolicy) StatusView() map[string]any {
	return map[string]any{
		"actor":                 p.Actor,
		"read_domains":          append([]string(nil), p.ReadDomains...),
		"write_domains":         append([]string(nil), p.WriteDomains...),
		"default_write_domain":  p.DefaultWriteDomain,
		"allowed_sensitivities": append([]string(nil), p.AllowedSensitivities...),
		"allowed_flows":         memoryFlowStatusViews(p.AllowedFlows),
	}
}

// applyMemoryTopology loads target-state memory domains and policy from JSON flags.
func (c *Config) applyMemoryTopology(domainsJSON string, policyJSON string) error {
	if strings.TrimSpace(domainsJSON) != "" {
		var domains []MemoryDomain
		if err := json.Unmarshal([]byte(domainsJSON), &domains); err != nil {
			return fmt.Errorf("memory domains JSON: %w", err)
		}
		c.MemoryDomains = domains
	}
	if len(c.MemoryDomains) == 0 {
		c.MemoryDomains = []MemoryDomain{defaultMemoryDomain(c.MemoryMCPURL)}
	}
	if strings.TrimSpace(policyJSON) != "" {
		var policy MemoryPolicy
		if err := json.Unmarshal([]byte(policyJSON), &policy); err != nil {
			return fmt.Errorf("memory policy JSON: %w", err)
		}
		c.MemoryPolicy = policy
	}
	if c.MemoryPolicy.Actor == "" &&
		len(c.MemoryPolicy.ReadDomains) == 0 &&
		len(c.MemoryPolicy.WriteDomains) == 0 &&
		c.MemoryPolicy.DefaultWriteDomain == "" {
		c.MemoryPolicy = defaultMemoryPolicy(c.AppName, c.MemoryDomains)
	}
	return nil
}

// applyAgentProfiles loads request-scoped agent profiles from JSON flags.
func (c *Config) applyAgentProfiles(profilesJSON string) error {
	if strings.TrimSpace(profilesJSON) != "" {
		var profiles []AgentProfile
		if err := json.Unmarshal([]byte(profilesJSON), &profiles); err != nil {
			return fmt.Errorf("agent profiles JSON: %w", err)
		}
		c.AgentProfiles = profiles
	}
	if len(c.AgentProfiles) == 0 {
		c.AgentProfiles = []AgentProfile{defaultAgentProfile(c.AppName, c.UserID, c.MemoryPolicy)}
	}
	c.MemoryPolicy = c.AgentProfiles[0].MemoryPolicy()
	return nil
}

// applyMemoryServices loads per-domain memory service supervision from JSON.
func (c *Config) applyMemoryServices(servicesJSON string) error {
	if strings.TrimSpace(servicesJSON) != "" {
		var services []MemoryDomainService
		if err := json.Unmarshal([]byte(servicesJSON), &services); err != nil {
			return fmt.Errorf("memory services JSON: %w", err)
		}
		c.MemoryServices = services
	}
	if len(c.MemoryServices) == 0 {
		if len(c.MemoryDomains) == 1 {
			c.MemoryServices = []MemoryDomainService{
				memoryDomainServiceFromServiceConfig(c.MemoryDomains[0].ID, c.MemoryService),
			}
		} else if memoryServiceFlagConfigured(c.MemoryService) {
			return fmt.Errorf("memory-services-json is required when supervising multiple memory domains")
		}
	}
	for index := range c.MemoryServices {
		c.MemoryServices[index] = c.normalizedMemoryService(c.MemoryServices[index])
	}
	return nil
}

// normalizedMemoryService fills derived names and health URLs for one service.
func (c Config) normalizedMemoryService(service MemoryDomainService) MemoryDomainService {
	service.DomainID = strings.TrimSpace(service.DomainID)
	if strings.TrimSpace(service.Name) == "" {
		service.Name = MemoryServiceNameForDomain(service.DomainID)
	}
	if strings.TrimSpace(service.HealthURL) == "" {
		if domain, ok := c.memoryDomainByID(service.DomainID); ok {
			service.HealthURL = domain.HealthURL
		}
	}
	return service
}

// validateMemoryTopology rejects unsafe memory domains and invalid grants.
func (c Config) validateMemoryTopology() error {
	if len(c.MemoryDomains) == 0 {
		return fmt.Errorf("at least one memory domain is required")
	}
	domainIDs := make(map[string]struct{}, len(c.MemoryDomains))
	for _, domain := range c.MemoryDomains {
		id := strings.TrimSpace(domain.ID)
		if !isSafeID(id) {
			return fmt.Errorf("memory domain id %q is not a safe id", domain.ID)
		}
		if _, exists := domainIDs[id]; exists {
			return fmt.Errorf("duplicate memory domain id %q", id)
		}
		domainIDs[id] = struct{}{}
		if strings.TrimSpace(domain.Label) == "" {
			return fmt.Errorf("memory domain %q label is required", id)
		}
		if err := validateRequestURL("memory domain "+id+" endpoint", domain.Endpoint); err != nil {
			return err
		}
		if err := validateOptionalRequestURL("memory domain "+id+" health URL", domain.HealthURL); err != nil {
			return err
		}
	}
	if err := validateMemoryPolicy(c.MemoryPolicy, domainIDs); err != nil {
		return err
	}
	return nil
}

// validateMemoryServices rejects invalid per-domain supervision settings.
func (c Config) validateMemoryServices() error {
	domainIDs := make(map[string]struct{}, len(c.MemoryDomains))
	for _, domain := range c.MemoryDomains {
		domainIDs[strings.TrimSpace(domain.ID)] = struct{}{}
	}
	seen := map[string]struct{}{}
	for _, service := range c.MemoryServices {
		domainID := strings.TrimSpace(service.DomainID)
		if !isSafeID(domainID) {
			return fmt.Errorf("memory service domain id %q is not a safe id", service.DomainID)
		}
		if _, ok := domainIDs[domainID]; !ok {
			return fmt.Errorf("memory service grants unknown domain %q", domainID)
		}
		if _, exists := seen[domainID]; exists {
			return fmt.Errorf("duplicate memory service for domain %q", domainID)
		}
		seen[domainID] = struct{}{}
		if service.AutoStart && strings.TrimSpace(service.HealthURL) == "" {
			return fmt.Errorf("memory service %s health_url is required when auto_start is enabled", domainID)
		}
		if err := service.ServiceConfig().Validate(); err != nil {
			return fmt.Errorf("memory service %s: %w", domainID, err)
		}
	}
	return nil
}

// validateAgentProfiles rejects unsafe profile ids and unknown memory grants.
func (c Config) validateAgentProfiles() error {
	if len(c.AgentProfiles) == 0 {
		return fmt.Errorf("at least one agent profile is required")
	}
	domainIDs := make(map[string]struct{}, len(c.MemoryDomains))
	for _, domain := range c.MemoryDomains {
		domainIDs[strings.TrimSpace(domain.ID)] = struct{}{}
	}
	seen := map[string]struct{}{}
	for _, profile := range c.AgentProfiles {
		id := strings.TrimSpace(profile.ID)
		if !isSafeID(id) {
			return fmt.Errorf("agent profile id %q is not a safe id", profile.ID)
		}
		if _, exists := seen[id]; exists {
			return fmt.Errorf("duplicate agent profile id %q", id)
		}
		seen[id] = struct{}{}
		if strings.TrimSpace(profile.Label) == "" {
			return fmt.Errorf("agent profile %q label is required", id)
		}
		if strings.TrimSpace(profile.AppName) == "" {
			return fmt.Errorf("agent profile %q app_name is required", id)
		}
		if strings.TrimSpace(profile.UserID) == "" {
			return fmt.Errorf("agent profile %q user_id is required", id)
		}
		if err := validateOptionalTrimmedRequestURL("agent profile "+id+" harness_base_url", profile.HarnessBaseURL); err != nil {
			return err
		}
		if err := validateOptionalTrimmedRequestURL("agent profile "+id+" context_base_url", profile.ContextBaseURL); err != nil {
			return err
		}
		if err := validateMemoryPolicy(profile.MemoryPolicy(), domainIDs); err != nil {
			return fmt.Errorf("agent profile %q: %w", id, err)
		}
		if err := validateSlackBindings(profile.ID, profile.SlackBindings); err != nil {
			return err
		}
	}
	return nil
}

// validateSlackBindings rejects incomplete Slack profile scopes.
func validateSlackBindings(profileID string, bindings []SlackProfileBinding) error {
	for index, binding := range bindings {
		label := fmt.Sprintf("agent profile %q slack binding %d", strings.TrimSpace(profileID), index)
		if strings.TrimSpace(binding.TeamID) == "" {
			return fmt.Errorf("%s team_id is required", label)
		}
		if strings.TrimSpace(binding.ChannelID) == "" {
			return fmt.Errorf("%s channel_id is required", label)
		}
		if len(binding.AllowedUserIDs) == 0 {
			return fmt.Errorf("%s allowed_user_ids must not be empty", label)
		}
		seen := map[string]struct{}{}
		for _, userID := range binding.AllowedUserIDs {
			userID = strings.TrimSpace(userID)
			if userID == "" {
				return fmt.Errorf("%s allowed_user_ids must not contain blank values", label)
			}
			if _, exists := seen[userID]; exists {
				return fmt.Errorf("%s contains duplicate user id %q", label, userID)
			}
			seen[userID] = struct{}{}
		}
	}
	return nil
}

// validateMemoryPolicy rejects incomplete or over-broad active profile grants.
func validateMemoryPolicy(policy MemoryPolicy, domainIDs map[string]struct{}) error {
	if strings.TrimSpace(policy.Actor) == "" {
		return fmt.Errorf("memory policy actor is required")
	}
	if !isSafeID(strings.ReplaceAll(policy.Actor, ":", "-")) {
		return fmt.Errorf("memory policy actor %q is not a safe principal", policy.Actor)
	}
	if len(policy.ReadDomains) == 0 {
		return fmt.Errorf("memory policy read_domains must not be empty")
	}
	if len(policy.WriteDomains) == 0 {
		return fmt.Errorf("memory policy write_domains must not be empty")
	}
	if strings.TrimSpace(policy.DefaultWriteDomain) == "" {
		return fmt.Errorf("memory policy default_write_domain is required")
	}
	if len(policy.AllowedSensitivities) == 0 {
		return fmt.Errorf("memory policy allowed_sensitivities must not be empty")
	}
	for _, sensitivity := range policy.AllowedSensitivities {
		if strings.TrimSpace(sensitivity) == "" {
			return fmt.Errorf("memory policy allowed_sensitivities contains a blank value")
		}
	}
	if err := validateDomainGrants("read_domains", policy.ReadDomains, domainIDs); err != nil {
		return err
	}
	if err := validateDomainGrants("write_domains", policy.WriteDomains, domainIDs); err != nil {
		return err
	}
	if !containsTrimmed(policy.WriteDomains, policy.DefaultWriteDomain) {
		return fmt.Errorf("memory policy default_write_domain %q is not writable", policy.DefaultWriteDomain)
	}
	for _, flow := range policy.AllowedFlows {
		if _, ok := domainIDs[strings.TrimSpace(flow.From)]; !ok || !containsTrimmed(policy.ReadDomains, flow.From) {
			return fmt.Errorf("memory policy flow source %q is not readable", flow.From)
		}
		if _, ok := domainIDs[strings.TrimSpace(flow.To)]; !ok || !containsTrimmed(policy.WriteDomains, flow.To) {
			return fmt.Errorf("memory policy flow target %q is not writable", flow.To)
		}
	}
	return nil
}

// validateDomainGrants rejects unsafe, duplicate, or unknown domain grants.
func validateDomainGrants(label string, values []string, domainIDs map[string]struct{}) error {
	seen := map[string]struct{}{}
	for _, value := range values {
		id := strings.TrimSpace(value)
		if !isSafeID(id) {
			return fmt.Errorf("memory policy %s value %q is not a safe id", label, value)
		}
		if _, ok := domainIDs[id]; !ok {
			return fmt.Errorf("memory policy %s grants unknown domain %q", label, id)
		}
		if _, exists := seen[id]; exists {
			return fmt.Errorf("memory policy %s contains duplicate domain %q", label, id)
		}
		seen[id] = struct{}{}
	}
	return nil
}

// defaultMemoryDomain returns the target-state single-domain install topology.
func defaultMemoryDomain(mcpURL string) MemoryDomain {
	return MemoryDomain{
		ID:        "memory",
		Label:     "Memory",
		Endpoint:  mcpURL,
		HealthURL: memoryHealthURL(mcpURL),
	}
}

// defaultMemoryPolicy returns grants for the shipped one-domain agent profile.
func defaultMemoryPolicy(appName string, domains []MemoryDomain) MemoryPolicy {
	defaultDomain := "memory"
	if len(domains) > 0 && strings.TrimSpace(domains[0].ID) != "" {
		defaultDomain = strings.TrimSpace(domains[0].ID)
	}
	return MemoryPolicy{
		Actor:                defaultActor(appName),
		ReadDomains:          []string{defaultDomain},
		WriteDomains:         []string{defaultDomain},
		DefaultWriteDomain:   defaultDomain,
		AllowedSensitivities: []string{"public", "internal", "private"},
	}
}

// defaultAgentProfile returns the shipped one-profile gateway identity.
func defaultAgentProfile(appName string, userID string, policy MemoryPolicy) AgentProfile {
	return AgentProfile{
		ID:                   defaultProfileID(appName),
		Label:                defaultProfileLabel(appName),
		AppName:              strings.TrimSpace(appName),
		UserID:               strings.TrimSpace(userID),
		Actor:                policy.Actor,
		ReadDomains:          append([]string(nil), policy.ReadDomains...),
		WriteDomains:         append([]string(nil), policy.WriteDomains...),
		DefaultWriteDomain:   policy.DefaultWriteDomain,
		AllowedSensitivities: append([]string(nil), policy.AllowedSensitivities...),
		AllowedFlows:         append([]MemoryDomainFlow(nil), policy.AllowedFlows...),
	}
}

// defaultProfileID derives a safe profile id from the app name.
func defaultProfileID(appName string) string {
	normalized := strings.Trim(strings.NewReplacer("_", "-", ".", "-", " ", "-").Replace(strings.ToLower(appName)), "-")
	if normalized == "" {
		return "agent-awesome"
	}
	if !isSafeID(normalized) {
		return "agent-awesome"
	}
	return normalized
}

// defaultProfileLabel derives a readable label from the app name.
func defaultProfileLabel(appName string) string {
	id := defaultProfileID(appName)
	parts := strings.FieldsFunc(id, func(r rune) bool {
		return r == '-' || r == '_'
	})
	for index, part := range parts {
		if part == "" {
			continue
		}
		parts[index] = strings.ToUpper(part[:1]) + part[1:]
	}
	label := strings.Join(parts, " ")
	if strings.TrimSpace(label) == "" {
		return "Agent Awesome"
	}
	return label
}

// MemoryServiceNameForDomain returns the deterministic service name for a domain.
func MemoryServiceNameForDomain(domainID string) string {
	domainID = strings.TrimSpace(domainID)
	if domainID == "" || domainID == "memory" {
		return DefaultMemoryServiceName
	}
	return DefaultMemoryServiceName + "-" + domainID
}

// memoryDomainServiceFromServiceConfig maps single-domain flags to target config.
func memoryDomainServiceFromServiceConfig(domainID string, service ServiceConfig) MemoryDomainService {
	return MemoryDomainService{
		DomainID:   strings.TrimSpace(domainID),
		Name:       service.Name,
		HealthURL:  service.HealthURL,
		Command:    service.Command,
		Arguments:  append([]string(nil), service.Arguments...),
		WorkingDir: service.WorkingDir,
		AutoStart:  service.AutoStart,
	}
}

// memoryServiceFlagConfigured reports whether single-service process flags are set.
func memoryServiceFlagConfigured(service ServiceConfig) bool {
	return service.AutoStart ||
		strings.TrimSpace(service.Command) != "" ||
		strings.TrimSpace(service.WorkingDir) != "" ||
		len(service.Arguments) > 0
}

// applyHarnessEmbeddedServices configures harness to own local control services.
func (c *Config) applyHarnessEmbeddedServices() error {
	if !c.HarnessEmbeddedServices {
		return nil
	}
	if serviceProcessConfigured(c.RunbookService) {
		return fmt.Errorf("runbook service process flags cannot be used with harness-embedded-services")
	}
	if !c.HarnessService.AutoStart {
		return nil
	}
	args := append([]string(nil), c.HarnessService.Arguments...)
	contextAddr, err := listenAddressFromRequestURL(c.ContextBaseURL)
	if err != nil {
		return fmt.Errorf("context base URL for harness embedded services: %w", err)
	}
	runbookAddr, err := listenAddressFromRequestURL(c.RunbookBaseURL)
	if err != nil {
		return fmt.Errorf("runbook base URL for harness embedded services: %w", err)
	}
	args = insertHarnessFlagValue(args, "--context-api-addr", contextAddr)
	args = insertHarnessFlagValue(args, "--runbook-api-addr", runbookAddr)
	c.HarnessService.Arguments = args
	return nil
}

// serviceProcessConfigured reports whether a service would start separately.
func serviceProcessConfigured(service ServiceConfig) bool {
	return service.AutoStart ||
		strings.TrimSpace(service.Command) != "" ||
		strings.TrimSpace(service.WorkingDir) != "" ||
		len(service.Arguments) > 0
}

// insertHarnessFlagValue inserts one harness run flag before runtime args.
func insertHarnessFlagValue(args []string, flag string, value string) []string {
	if strings.TrimSpace(value) == "" || hasFlag(args, flag) {
		return args
	}
	insertAt := len(args)
	for index, arg := range args {
		if arg == "--" {
			insertAt = index
			break
		}
	}
	next := make([]string, 0, len(args)+2)
	next = append(next, args[:insertAt]...)
	next = append(next, flag, value)
	next = append(next, args[insertAt:]...)
	return next
}

// hasFlag reports whether args already include a flag or flag=value.
func hasFlag(args []string, flag string) bool {
	for _, arg := range args {
		if arg == flag || strings.HasPrefix(arg, flag+"=") {
			return true
		}
	}
	return false
}

// listenAddressFromRequestURL returns the host:port bind value beside a URL.
func listenAddressFromRequestURL(value string) (string, error) {
	parsed, err := url.ParseRequestURI(value)
	if err != nil {
		return "", err
	}
	host := strings.TrimSpace(parsed.Hostname())
	if host == "" {
		return "", fmt.Errorf("host is required")
	}
	if !isLoopbackHost(host) {
		return "", fmt.Errorf("host %q must be loopback", host)
	}
	port := strings.TrimSpace(parsed.Port())
	if port == "" {
		switch parsed.Scheme {
		case "http":
			port = "80"
		case "https":
			port = "443"
		default:
			return "", fmt.Errorf("port is required")
		}
	}
	return net.JoinHostPort(host, port), nil
}

// memoryDomainByID returns one configured memory domain by id.
func (c Config) memoryDomainByID(domainID string) (MemoryDomain, bool) {
	domainID = strings.TrimSpace(domainID)
	for _, domain := range c.MemoryDomains {
		if strings.TrimSpace(domain.ID) == domainID {
			return domain, true
		}
	}
	return MemoryDomain{}, false
}

// defaultActor derives the default agent principal from the app name.
func defaultActor(appName string) string {
	normalized := strings.Trim(strings.NewReplacer("_", "-", ".", "-", " ", "-").Replace(strings.ToLower(appName)), "-")
	if normalized == "" {
		normalized = "agent-awesome"
	}
	return "agent:" + normalized
}

// slackBindingStatusViews renders Slack scopes without token fields.
func slackBindingStatusViews(bindings []SlackProfileBinding) []map[string]any {
	views := make([]map[string]any, 0, len(bindings))
	for _, binding := range bindings {
		views = append(views, map[string]any{
			"team_id":          binding.TeamID,
			"channel_id":       binding.ChannelID,
			"allowed_user_ids": append([]string(nil), binding.AllowedUserIDs...),
		})
	}
	return views
}

// memoryFlowStatusViews renders sanitized information-flow grants.
func memoryFlowStatusViews(flows []MemoryDomainFlow) []map[string]string {
	views := make([]map[string]string, 0, len(flows))
	for _, flow := range flows {
		views = append(views, map[string]string{"from": flow.From, "to": flow.To})
	}
	return views
}

// statusViews renders sanitized rows for config models with StatusView methods.
func statusViews[T interface{ StatusView() map[string]any }](values []T) []map[string]any {
	views := make([]map[string]any, 0, len(values))
	for _, value := range values {
		views = append(views, value.StatusView())
	}
	return views
}

// defaultMemoryServiceHealthURL returns the health URL for the default memory service.
func defaultMemoryServiceHealthURL(domains []MemoryDomain, mcpURL string) string {
	if len(domains) > 0 && strings.TrimSpace(domains[0].HealthURL) != "" {
		return strings.TrimSpace(domains[0].HealthURL)
	}
	return memoryHealthURL(mcpURL)
}

// containsTrimmed reports whether a list contains a trimmed target value.
func containsTrimmed(values []string, target string) bool {
	target = strings.TrimSpace(target)
	for _, value := range values {
		if strings.TrimSpace(value) == target {
			return true
		}
	}
	return false
}

// isSafeID reports whether a user-owned id is safe for config and routing.
func isSafeID(value string) bool {
	value = strings.TrimSpace(value)
	if len(value) == 0 || len(value) > 64 {
		return false
	}
	for index, char := range value {
		switch {
		case char >= 'a' && char <= 'z':
		case char >= '0' && char <= '9':
		case char == '_' || char == '-':
			if index == 0 {
				return false
			}
		default:
			return false
		}
	}
	return true
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

// hasCompleteLegacyAllowList reports whether old single-profile Slack scope is set.
func (s SlackConfig) hasCompleteLegacyAllowList() bool {
	return strings.TrimSpace(s.AllowedTeamID) != "" &&
		strings.TrimSpace(s.AllowedUserID) != "" &&
		strings.TrimSpace(s.AllowedChannelID) != ""
}

// hasLegacyAllowList reports whether any old single-profile Slack field is set.
func (s SlackConfig) hasLegacyAllowList() bool {
	return strings.TrimSpace(s.AllowedTeamID) != "" ||
		strings.TrimSpace(s.AllowedUserID) != "" ||
		strings.TrimSpace(s.AllowedChannelID) != ""
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

// runbookHealthURL derives the runbook process health endpoint from its API URL.
func runbookHealthURL(apiBaseURL string) string {
	parsed, err := url.Parse(apiBaseURL)
	if err != nil {
		return ""
	}
	parsed.Path = "/healthz"
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String()
}

// gatewayAPIBaseURL derives a loopback gateway API URL for in-process channels.
func gatewayAPIBaseURL(listenAddress string) string {
	host, port, err := net.SplitHostPort(listenAddress)
	if err != nil || strings.TrimSpace(port) == "" {
		return "http://127.0.0.1:8070/api"
	}
	host = strings.Trim(host, "[]")
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	return (&url.URL{
		Scheme: "http",
		Host:   net.JoinHostPort(host, port),
		Path:   "/api",
	}).String()
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
