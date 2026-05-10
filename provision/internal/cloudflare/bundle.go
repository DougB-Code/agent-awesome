package cloudflare

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// BundlePaths stores paths written for one provisioned deployment bundle.
type BundlePaths struct {
	Directory      string
	WranglerConfig string
	Summary        string
	Commands       string
}

// WriteBundle writes operator-verifiable Cloudflare deployment artifacts.
func WriteBundle(deployment Deployment, directory string) (BundlePaths, error) {
	if strings.TrimSpace(directory) == "" {
		return BundlePaths{}, fmt.Errorf("directory must not be empty")
	}
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return BundlePaths{}, fmt.Errorf("create bundle directory: %w", err)
	}
	paths := BundlePaths{
		Directory:      directory,
		WranglerConfig: filepath.Join(directory, "wrangler.jsonc"),
		Summary:        filepath.Join(directory, "provisioning.json"),
		Commands:       filepath.Join(directory, "commands.txt"),
	}
	if err := writeJSON(paths.WranglerConfig, deployment.Wrangler()); err != nil {
		return BundlePaths{}, err
	}
	if err := writeJSON(paths.Summary, deployment); err != nil {
		return BundlePaths{}, err
	}
	if err := os.WriteFile(paths.Commands, []byte(commandsText(deployment)), 0o600); err != nil {
		return BundlePaths{}, fmt.Errorf("write commands: %w", err)
	}
	return paths, nil
}

// writeJSON writes an indented JSON document to disk.
func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "\t")
	if err != nil {
		return fmt.Errorf("marshal %s: %w", filepath.Base(path), err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write %s: %w", filepath.Base(path), err)
	}
	return nil
}

// commandsText returns safe commands for the operator to run.
func commandsText(deployment Deployment) string {
	var builder strings.Builder
	builder.WriteString("# Source of truth: run the provisioner instead of replaying generated internals.\n")
	builder.WriteString("# Secret values are intentionally not written to disk.\n\n")
	builder.WriteString("agent-awesome-provision cloudflare apply --agent-id ")
	builder.WriteString(deployment.AgentID)
	builder.WriteString(" --hostname ")
	builder.WriteString(deployment.Hostname)
	builder.WriteString(" --zone-name ")
	builder.WriteString(deployment.ZoneName)
	if deployment.SlackEnabled {
		builder.WriteString(" --slack")
		builder.WriteString(" --slack-allowed-team-id ")
		builder.WriteString(deployment.SlackAllowedTeamID)
		builder.WriteString(" --slack-allowed-user-id ")
		builder.WriteString(deployment.SlackAllowedUserID)
		builder.WriteString(" --slack-allowed-channel-id ")
		builder.WriteString(deployment.SlackAllowedChannelID)
	}
	builder.WriteString("\n")
	return builder.String()
}
