// Package main builds Cloudflare deployment state and runtime dependencies.
package main

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/platform"
	"agentprovision/internal/state"
	"agentprovision/internal/workersecrets"
)

// prepareApplyState prepares metadata and stable internal tokens for apply.
func prepareApplyState(deployment cloudflare.Deployment, stateDir string, dryRun bool) (cloudflare.SecretValues, state.AgentRecord, state.Store, error) {
	if dryRun {
		return nil, state.AgentRecord{}, state.Store{}, nil
	}
	store, err := provisionStore(stateDir)
	if err != nil {
		return nil, state.AgentRecord{}, state.Store{}, err
	}
	record, err := store.Load(deployment.AgentID)
	if err != nil && !errors.Is(err, state.ErrNotFound) {
		return nil, state.AgentRecord{}, state.Store{}, err
	}
	secretStore := state.DefaultSecretStore()
	record = updateRecord(record, deployment)
	gatewayToken, err := secretStore.EnsureGenerated(record.GatewayTokenCredential)
	if err != nil {
		return nil, state.AgentRecord{}, state.Store{}, err
	}
	persistenceToken, err := secretStore.EnsureGenerated(record.PersistenceTokenCredential)
	if err != nil {
		return nil, state.AgentRecord{}, state.Store{}, err
	}
	secrets, err := workersecrets.BuildWithTokens(deployment, credentialEnvironment{store: secretStore}, workersecrets.InternalTokens{
		GatewayToken:     gatewayToken,
		PersistenceToken: persistenceToken,
	})
	if err != nil {
		return nil, state.AgentRecord{}, state.Store{}, err
	}
	return secrets, record, store, nil
}

// directCloudflareRuntime builds direct API and Wrangler auth configuration.
func directCloudflareRuntime(config platform.Config, hasConfig bool, dryRun bool) (cloudflareRuntime, error) {
	accountID := strings.TrimSpace(config.CloudflareAccountID)
	if accountID == "" {
		accountID = strings.TrimSpace(os.Getenv("CLOUDFLARE_ACCOUNT_ID"))
	}
	if accountID == "" {
		if dryRun {
			return cloudflareRuntime{}, nil
		}
		return cloudflareRuntime{}, fmt.Errorf("Cloudflare account id is required; run `agent-awesome-provision platform init --cloudflare-account-id ACCOUNT_ID --zone-name %s`", displayOptional(config.ZoneName))
	}
	if !hasConfig && !dryRun {
		return cloudflareRuntime{}, fmt.Errorf("platform config is required for direct Cloudflare reconciliation")
	}
	token := ""
	if !dryRun {
		value, err := credentialEnvironment{store: state.DefaultSecretStore()}.Lookup("CLOUDFLARE_API_TOKEN")
		if err != nil {
			return cloudflareRuntime{}, err
		}
		token = value
	}
	api, err := cloudflare.NewAPIClient(cloudflare.APIClientOptions{
		AccountID: accountID,
		APIToken:  token,
	})
	if err != nil {
		return cloudflareRuntime{}, err
	}
	runtime := cloudflareRuntime{API: api}
	if token != "" {
		runtime.WranglerEnv = map[string]string{
			"CLOUDFLARE_ACCOUNT_ID": accountID,
			"CLOUDFLARE_API_TOKEN":  token,
		}
	}
	return runtime, nil
}

// cloudflareRuntime stores direct API and Wrangler authentication material.
type cloudflareRuntime struct {
	API         *cloudflare.APIClient
	WranglerEnv map[string]string
}

// deploymentInput merges command flags with optional platform defaults.
func deploymentInput(agentID string, userID string, hostname string, zoneName string, slackEnabled bool, slackAllowedTeamID string, slackAllowedUserID string, slackAllowedChannelID string, config platform.Config, hasConfig bool) (cloudflare.DeploymentInput, error) {
	agentID = strings.TrimSpace(agentID)
	if agentID == "" {
		return cloudflare.DeploymentInput{}, fmt.Errorf("agent id is required")
	}
	if strings.TrimSpace(userID) == "" {
		userID = agentID
	}
	if strings.TrimSpace(hostname) == "" {
		if !hasConfig || strings.TrimSpace(config.AgentHostnameSuffix) == "" {
			return cloudflare.DeploymentInput{}, fmt.Errorf("hostname is required unless platform config has agent_hostname_suffix")
		}
		slug, err := cloudflare.Slug(agentID)
		if err != nil {
			return cloudflare.DeploymentInput{}, err
		}
		hostname = slug + "." + config.AgentHostnameSuffix
	}
	if strings.TrimSpace(zoneName) == "" && hasConfig {
		zoneName = config.ZoneName
	}
	return cloudflare.DeploymentInput{
		AgentID:               agentID,
		UserID:                userID,
		Hostname:              hostname,
		ZoneName:              zoneName,
		SlackEnabled:          slackEnabled,
		SlackAllowedTeamID:    slackAllowedTeamID,
		SlackAllowedUserID:    slackAllowedUserID,
		SlackAllowedChannelID: slackAllowedChannelID,
	}, nil
}

// resolveRepoRoot returns the Worker source root from flags, config, or discovery.
func resolveRepoRoot(explicit string, config platform.Config, hasConfig bool) (string, error) {
	if strings.TrimSpace(explicit) != "" {
		return repoRoot(explicit)
	}
	if hasConfig && strings.TrimSpace(config.WorkerSourceDir) != "" {
		return repoRoot(config.WorkerSourceDir)
	}
	return repoRoot("")
}

// updateRecord maps deployment metadata into one persisted agent record.
func updateRecord(record state.AgentRecord, deployment cloudflare.Deployment) state.AgentRecord {
	record.AgentID = deployment.AgentID
	record.UserID = deployment.UserID
	record.Hostname = deployment.Hostname
	record.ZoneName = deployment.ZoneName
	record.WorkerName = deployment.WorkerName
	record.BucketName = deployment.BucketName
	record.SnapshotURL = deployment.SnapshotURL
	record.SnapshotKey = deployment.SnapshotKey
	record.SlackEnabled = deployment.SlackEnabled
	record.SlackAllowedTeamID = deployment.SlackAllowedTeamID
	record.SlackAllowedUserID = deployment.SlackAllowedUserID
	record.SlackAllowedChannelID = deployment.SlackAllowedChannelID
	record.GatewayTokenCredential = state.CredentialName(deployment.AgentID, "AGENTAWESOME_GATEWAY_TOKEN")
	record.PersistenceTokenCredential = state.CredentialName(deployment.AgentID, "AGENTAWESOME_PERSISTENCE_TOKEN")
	return record
}

// deploymentFromRecord rebuilds Cloudflare desired state from a saved agent record.
func deploymentFromRecord(record state.AgentRecord) (cloudflare.Deployment, error) {
	userID := record.UserID
	if strings.TrimSpace(userID) == "" {
		userID = record.AgentID
	}
	deployment, err := cloudflare.NewDeployment(cloudflare.DeploymentInput{
		AgentID:               record.AgentID,
		UserID:                userID,
		Hostname:              record.Hostname,
		ZoneName:              record.ZoneName,
		SlackEnabled:          record.SlackEnabled,
		SlackAllowedTeamID:    record.SlackAllowedTeamID,
		SlackAllowedUserID:    record.SlackAllowedUserID,
		SlackAllowedChannelID: record.SlackAllowedChannelID,
	})
	if err != nil {
		return cloudflare.Deployment{}, err
	}
	if strings.TrimSpace(record.WorkerName) != "" {
		deployment.WorkerName = record.WorkerName
	}
	if strings.TrimSpace(record.BucketName) != "" {
		deployment.BucketName = record.BucketName
	}
	if strings.TrimSpace(record.SnapshotURL) != "" {
		deployment.SnapshotURL = record.SnapshotURL
	}
	if strings.TrimSpace(record.SnapshotKey) != "" {
		deployment.SnapshotKey = record.SnapshotKey
	}
	return deployment, nil
}

// deleteLocalAgent removes local metadata and generated per-agent credentials.
func deleteLocalAgent(store state.Store, record state.AgentRecord) error {
	secretStore := state.DefaultSecretStore()
	for _, credential := range []string{record.GatewayTokenCredential, record.PersistenceTokenCredential} {
		if strings.TrimSpace(credential) == "" {
			continue
		}
		if err := secretStore.Delete(credential); err != nil {
			return err
		}
	}
	if err := store.Delete(record.AgentID); err != nil && !errors.Is(err, state.ErrNotFound) {
		return err
	}
	return nil
}
