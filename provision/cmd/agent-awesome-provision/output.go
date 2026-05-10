package main

import (
	"encoding/json"
	"fmt"
	"os"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/state"
)

// writeJSONOutput writes one structured command result to stdout.
func writeJSONOutput(value any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "\t")
	if err := encoder.Encode(value); err != nil {
		return fmt.Errorf("write JSON output: %w", err)
	}
	return nil
}

// deploymentSummary stores public deployment metadata for command output.
type deploymentSummary struct {
	AgentID               string `json:"agent_id"`
	UserID                string `json:"user_id,omitempty"`
	Hostname              string `json:"hostname"`
	ZoneName              string `json:"zone_name"`
	WorkerName            string `json:"worker_name"`
	BucketName            string `json:"bucket_name"`
	SnapshotURL           string `json:"snapshot_url,omitempty"`
	SnapshotKey           string `json:"snapshot_key,omitempty"`
	SlackEnabled          bool   `json:"slack_enabled"`
	SlackAllowedTeamID    string `json:"slack_allowed_team_id,omitempty"`
	SlackAllowedUserID    string `json:"slack_allowed_user_id,omitempty"`
	SlackAllowedChannelID string `json:"slack_allowed_channel_id,omitempty"`
}

// applyOutput stores the structured Cloudflare apply result.
type applyOutput struct {
	Action       string                       `json:"action"`
	DryRun       bool                         `json:"dry_run"`
	Deployment   deploymentSummary            `json:"deployment"`
	Files        bundleSummary                `json:"files"`
	AccountID    string                       `json:"account_id,omitempty"`
	DashboardURL string                       `json:"dashboard_url,omitempty"`
	LogsURL      string                       `json:"logs_url,omitempty"`
	Commands     []string                     `json:"commands"`
	Services     []cloudflare.ServiceStatus   `json:"services,omitempty"`
	State        *provisionedAgentJSONSummary `json:"state,omitempty"`
}

// deleteOutput stores the structured Cloudflare delete result.
type deleteOutput struct {
	Action       string            `json:"action"`
	DryRun       bool              `json:"dry_run"`
	Deployment   deploymentSummary `json:"deployment"`
	AccountID    string            `json:"account_id,omitempty"`
	DashboardURL string            `json:"dashboard_url,omitempty"`
	Commands     []string          `json:"commands"`
}

// localDeleteOutput stores structured local cleanup output.
type localDeleteOutput struct {
	Action string                      `json:"action"`
	DryRun bool                        `json:"dry_run"`
	Agent  provisionedAgentJSONSummary `json:"agent"`
}

// listOutput stores provisioned agent list output.
type listOutput struct {
	Agents []provisionedAgentJSONSummary `json:"agents"`
}

// statusOutput stores provisioned agent health output.
type statusOutput struct {
	Agent    provisionedAgentJSONSummary `json:"agent"`
	Services []cloudflare.ServiceStatus  `json:"services"`
}

// bundleSummary stores generated file paths.
type bundleSummary struct {
	Directory      string `json:"directory"`
	WranglerConfig string `json:"wrangler_config"`
	Summary        string `json:"summary"`
	Commands       string `json:"commands"`
}

// provisionedAgentJSONSummary stores non-secret saved agent metadata.
type provisionedAgentJSONSummary struct {
	AgentID               string `json:"agent_id"`
	UserID                string `json:"user_id,omitempty"`
	Hostname              string `json:"hostname"`
	ZoneName              string `json:"zone_name,omitempty"`
	WorkerName            string `json:"worker_name"`
	BucketName            string `json:"bucket_name"`
	SnapshotURL           string `json:"snapshot_url,omitempty"`
	SnapshotKey           string `json:"snapshot_key,omitempty"`
	SlackEnabled          bool   `json:"slack_enabled"`
	SlackAllowedTeamID    string `json:"slack_allowed_team_id,omitempty"`
	SlackAllowedUserID    string `json:"slack_allowed_user_id,omitempty"`
	SlackAllowedChannelID string `json:"slack_allowed_channel_id,omitempty"`
}

// deploymentJSONSummary maps deployment metadata into output.
func deploymentJSONSummary(deployment cloudflare.Deployment) deploymentSummary {
	return deploymentSummary{
		AgentID:               deployment.AgentID,
		UserID:                deployment.UserID,
		Hostname:              deployment.Hostname,
		ZoneName:              deployment.ZoneName,
		WorkerName:            deployment.WorkerName,
		BucketName:            deployment.BucketName,
		SnapshotURL:           deployment.SnapshotURL,
		SnapshotKey:           deployment.SnapshotKey,
		SlackEnabled:          deployment.SlackEnabled,
		SlackAllowedTeamID:    deployment.SlackAllowedTeamID,
		SlackAllowedUserID:    deployment.SlackAllowedUserID,
		SlackAllowedChannelID: deployment.SlackAllowedChannelID,
	}
}

// bundleJSONSummary maps generated bundle paths into output.
func bundleJSONSummary(bundle cloudflare.BundlePaths) bundleSummary {
	return bundleSummary{
		Directory:      bundle.Directory,
		WranglerConfig: bundle.WranglerConfig,
		Summary:        bundle.Summary,
		Commands:       bundle.Commands,
	}
}

// recordJSONSummary maps saved agent metadata into output.
func recordJSONSummary(record state.AgentRecord) provisionedAgentJSONSummary {
	return provisionedAgentJSONSummary{
		AgentID:               record.AgentID,
		UserID:                record.UserID,
		Hostname:              record.Hostname,
		ZoneName:              record.ZoneName,
		WorkerName:            record.WorkerName,
		BucketName:            record.BucketName,
		SnapshotURL:           record.SnapshotURL,
		SnapshotKey:           record.SnapshotKey,
		SlackEnabled:          record.SlackEnabled,
		SlackAllowedTeamID:    record.SlackAllowedTeamID,
		SlackAllowedUserID:    record.SlackAllowedUserID,
		SlackAllowedChannelID: record.SlackAllowedChannelID,
	}
}

// optionalRecordJSONSummary returns nil when no state was written.
func optionalRecordJSONSummary(record state.AgentRecord) *provisionedAgentJSONSummary {
	if record.AgentID == "" {
		return nil
	}
	summary := recordJSONSummary(record)
	return &summary
}

// progressPrinter returns nil when stdout is reserved for JSON output.
func progressPrinter(jsonOutput bool) cloudflare.ProgressFunc {
	if jsonOutput {
		return nil
	}
	return printOperationEvent
}
