package cloudflare

import (
	"fmt"
	"net/url"
	"strings"
)

const (
	defaultAgentAppName      = "agent_awesome"
	defaultSnapshotKey       = "context-snapshot.tar.gz"
	defaultContextAPIBaseURL = "http://127.0.0.1:8081/api/context"
	defaultRequestTimeout    = "10m"
	defaultStartTimeout      = "45s"
)

// DeploymentInput stores the user-selected values for one cloud agent.
type DeploymentInput struct {
	AgentID               string
	UserID                string
	Hostname              string
	ZoneName              string
	SlackEnabled          bool
	SlackAllowedTeamID    string
	SlackAllowedUserID    string
	SlackAllowedChannelID string
}

// Deployment stores the derived Cloudflare desired state for one cloud agent.
type Deployment struct {
	AgentID               string
	UserID                string
	Hostname              string
	ZoneName              string
	WorkerName            string
	BucketName            string
	SnapshotURL           string
	SnapshotKey           string
	SlackEnabled          bool
	SlackAllowedTeamID    string
	SlackAllowedUserID    string
	SlackAllowedChannelID string
	RequiredSecrets       []string
	GeneratedSecrets      []string
}

// NewDeployment validates input and derives one per-agent Cloudflare deployment.
func NewDeployment(input DeploymentInput) (Deployment, error) {
	agentID, err := Slug(input.AgentID)
	if err != nil {
		return Deployment{}, fmt.Errorf("agent id: %w", err)
	}
	userID := strings.TrimSpace(input.UserID)
	if userID == "" {
		return Deployment{}, fmt.Errorf("user id must not be empty")
	}
	hostname, err := normalizedHostname(input.Hostname)
	if err != nil {
		return Deployment{}, err
	}
	zone := strings.TrimSpace(input.ZoneName)
	if zone == "" {
		zone = zoneName(hostname)
	}
	workerName, err := WorkerName(agentID)
	if err != nil {
		return Deployment{}, err
	}
	bucketName, err := BucketName(agentID)
	if err != nil {
		return Deployment{}, err
	}
	slackAllowedTeamID := strings.TrimSpace(input.SlackAllowedTeamID)
	slackAllowedUserID := strings.TrimSpace(input.SlackAllowedUserID)
	slackAllowedChannelID := strings.TrimSpace(input.SlackAllowedChannelID)
	if err := validateSlackAllowLists(input.SlackEnabled, slackAllowedTeamID, slackAllowedUserID, slackAllowedChannelID); err != nil {
		return Deployment{}, err
	}
	deployment := Deployment{
		AgentID:               agentID,
		UserID:                userID,
		Hostname:              hostname,
		ZoneName:              zone,
		WorkerName:            workerName,
		BucketName:            bucketName,
		SnapshotURL:           "https://" + hostname + "/internal/context-snapshot",
		SnapshotKey:           defaultSnapshotKey,
		SlackEnabled:          input.SlackEnabled,
		SlackAllowedTeamID:    slackAllowedTeamID,
		SlackAllowedUserID:    slackAllowedUserID,
		SlackAllowedChannelID: slackAllowedChannelID,
		RequiredSecrets:       requiredSecrets(input.SlackEnabled),
		GeneratedSecrets:      generatedSecrets(),
	}
	return deployment, nil
}

// validateSlackAllowLists requires explicit Slack beta scope when Slack is enabled.
func validateSlackAllowLists(slackEnabled bool, teamID string, userID string, channelID string) error {
	if !slackEnabled {
		return nil
	}
	if teamID == "" {
		return fmt.Errorf("slack allowed team id is required when Slack is enabled")
	}
	if userID == "" {
		return fmt.Errorf("slack allowed user id is required when Slack is enabled")
	}
	if channelID == "" {
		return fmt.Errorf("slack allowed channel id is required when Slack is enabled")
	}
	return nil
}

// normalizedHostname returns a bare HTTPS hostname from a hostname or URL.
func normalizedHostname(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", fmt.Errorf("hostname must not be empty")
	}
	if !strings.Contains(trimmed, "://") {
		trimmed = "https://" + trimmed
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return "", fmt.Errorf("hostname: %w", err)
	}
	if parsed.Scheme != "https" {
		return "", fmt.Errorf("hostname must use https")
	}
	if parsed.Hostname() == "" {
		return "", fmt.Errorf("hostname must include a host")
	}
	return parsed.Hostname(), nil
}

// requiredSecrets returns secrets the operator must provide for one deployment.
func requiredSecrets(slackEnabled bool) []string {
	secrets := []string{
		"OPENAI_API_KEY",
		"AGENTAWESOME_GATEWAY_TOKEN",
		"AGENTAWESOME_PERSISTENCE_TOKEN",
	}
	if slackEnabled {
		secrets = append(secrets, "SLACK_SIGNING_SECRET", "SLACK_BOT_TOKEN")
	}
	return secrets
}

// generatedSecrets returns internal tokens that provisioners should create.
func generatedSecrets() []string {
	return []string{
		"AGENTAWESOME_GATEWAY_TOKEN",
		"AGENTAWESOME_PERSISTENCE_TOKEN",
	}
}
