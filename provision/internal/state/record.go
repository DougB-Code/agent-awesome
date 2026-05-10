package state

import "time"

// AgentRecord stores non-secret provisioning metadata for one cloud agent.
type AgentRecord struct {
	AgentID                    string    `json:"agent_id"`
	UserID                     string    `json:"user_id"`
	Hostname                   string    `json:"hostname"`
	ZoneName                   string    `json:"zone_name"`
	WorkerName                 string    `json:"worker_name"`
	BucketName                 string    `json:"bucket_name"`
	SnapshotURL                string    `json:"snapshot_url"`
	SnapshotKey                string    `json:"snapshot_key"`
	SlackEnabled               bool      `json:"slack_enabled"`
	SlackAllowedTeamID         string    `json:"slack_allowed_team_id,omitempty"`
	SlackAllowedUserID         string    `json:"slack_allowed_user_id,omitempty"`
	SlackAllowedChannelID      string    `json:"slack_allowed_channel_id,omitempty"`
	GatewayTokenCredential     string    `json:"gateway_token_credential"`
	PersistenceTokenCredential string    `json:"persistence_token_credential"`
	CreatedAt                  time.Time `json:"created_at"`
	UpdatedAt                  time.Time `json:"updated_at"`
}
