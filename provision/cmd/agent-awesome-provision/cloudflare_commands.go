// Package main implements Cloudflare deployment command handlers.
package main

import (
	"context"
	"flag"
	"fmt"
	"path/filepath"
	"time"

	"agentprovision/internal/cloudflare"
)

// renderCloudflare writes one per-agent Cloudflare deployment bundle.
func renderCloudflare(args []string) error {
	fs := flag.NewFlagSet("cloudflare render", flag.ContinueOnError)
	agentID := fs.String("agent-id", "", "stable provisioned agent id")
	userID := fs.String("user-id", "", "agent owner user id")
	hostname := fs.String("hostname", "", "public HTTPS hostname for this agent")
	zoneName := fs.String("zone-name", "", "Cloudflare zone name; defaults to hostname apex")
	repoRootFlag := fs.String("repo-root", "", "Agent Awesome repository root")
	outputDir := fs.String("output-dir", "", "output directory under build/")
	configPath := fs.String("platform-config", "", "platform config path; defaults to user config dir")
	slackEnabled := fs.Bool("slack", false, "include Slack webhook secrets in the rendered deployment")
	slackAllowedTeamID := fs.String("slack-allowed-team-id", "", "Slack team id allowed to use this beta agent")
	slackAllowedUserID := fs.String("slack-allowed-user-id", "", "Slack user id allowed to use this beta agent")
	slackAllowedChannelID := fs.String("slack-allowed-channel-id", "", "Slack channel id allowed to use this beta agent")
	if err := fs.Parse(args); err != nil {
		return err
	}
	config, hasConfig, err := loadOptionalPlatformConfig(*configPath)
	if err != nil {
		return err
	}
	input, err := deploymentInput(*agentID, *userID, *hostname, *zoneName, *slackEnabled, *slackAllowedTeamID, *slackAllowedUserID, *slackAllowedChannelID, config, hasConfig)
	if err != nil {
		return err
	}
	deployment, err := cloudflare.NewDeployment(input)
	if err != nil {
		return err
	}
	directory := *outputDir
	if directory == "" {
		root, err := resolveRepoRoot(*repoRootFlag, config, hasConfig)
		if err == nil {
			directory = filepath.Join(root, "build", "provision", deployment.AgentID)
		} else {
			directory = filepath.Join("..", "build", "provision", deployment.AgentID)
		}
	}
	paths, err := cloudflare.WriteBundle(deployment, directory)
	if err != nil {
		return err
	}
	fmt.Printf("Rendered Cloudflare agent deployment\n")
	fmt.Printf("  agent:   %s\n", deployment.AgentID)
	fmt.Printf("  worker:  %s\n", deployment.WorkerName)
	fmt.Printf("  bucket:  %s\n", deployment.BucketName)
	fmt.Printf("  host:    %s\n", deployment.Hostname)
	fmt.Printf("  files:   %s\n", paths.Directory)
	return nil
}

// applyCloudflare reconciles one per-agent Cloudflare deployment.
func applyCloudflare(args []string) error {
	fs := flag.NewFlagSet("cloudflare apply", flag.ContinueOnError)
	agentID := fs.String("agent-id", "", "stable provisioned agent id")
	userID := fs.String("user-id", "", "agent owner user id")
	hostname := fs.String("hostname", "", "public HTTPS hostname for this agent")
	zoneName := fs.String("zone-name", "", "Cloudflare zone name; defaults to hostname apex")
	repoRootFlag := fs.String("repo-root", "", "Agent Awesome repository root")
	outputDirFlag := fs.String("output-dir", "", "output directory under build/")
	stateDirFlag := fs.String("state-dir", "", "provisioning state directory; defaults to user config dir")
	configPath := fs.String("platform-config", "", "platform config path; defaults to user config dir")
	slackEnabled := fs.Bool("slack", false, "include Slack webhook secrets in the deployment")
	slackAllowedTeamID := fs.String("slack-allowed-team-id", "", "Slack team id allowed to use this beta agent")
	slackAllowedUserID := fs.String("slack-allowed-user-id", "", "Slack user id allowed to use this beta agent")
	slackAllowedChannelID := fs.String("slack-allowed-channel-id", "", "Slack channel id allowed to use this beta agent")
	dryRun := fs.Bool("dry-run", false, "render and list actions without calling Cloudflare")
	healthTimeout := fs.Duration("health-timeout", 2*time.Minute, "maximum deployed gateway health-check wait")
	jsonOutput := fs.Bool("json", false, "write structured JSON output")
	if err := fs.Parse(args); err != nil {
		return err
	}
	config, hasConfig, err := loadOptionalPlatformConfig(*configPath)
	if err != nil {
		return err
	}
	cloudflareRuntime, err := directCloudflareRuntime(config, hasConfig, *dryRun)
	if err != nil {
		return err
	}
	repoRoot, err := resolveRepoRoot(*repoRootFlag, config, hasConfig)
	if err != nil {
		return err
	}
	input, err := deploymentInput(*agentID, *userID, *hostname, *zoneName, *slackEnabled, *slackAllowedTeamID, *slackAllowedUserID, *slackAllowedChannelID, config, hasConfig)
	if err != nil {
		return err
	}
	deployment, err := cloudflare.NewDeployment(input)
	if err != nil {
		return err
	}
	outputDir := *outputDirFlag
	if outputDir == "" {
		outputDir = filepath.Join(repoRoot, "build", "provision", deployment.AgentID)
	}
	secrets, record, store, err := prepareApplyState(deployment, *stateDirFlag, *dryRun)
	if err != nil {
		return err
	}
	result, err := cloudflare.Apply(context.Background(), deployment, cloudflare.ApplyOptions{
		WorkerDirectory: filepath.Join(repoRoot, "deploy", "cloudflare", "worker"),
		OutputDirectory: outputDir,
		API:             cloudflareRuntime.API,
		WranglerEnv:     cloudflareRuntime.WranglerEnv,
		Secrets:         secrets,
		DryRun:          *dryRun,
		HealthTimeout:   *healthTimeout,
		Progress:        progressPrinter(*jsonOutput),
	})
	if err != nil {
		return err
	}
	if !*dryRun {
		record, err = store.Save(record)
		if err != nil {
			return err
		}
	}
	if *jsonOutput {
		output := applyOutput{
			Action:     "apply",
			DryRun:     *dryRun,
			Deployment: deploymentJSONSummary(deployment),
			Files:      bundleJSONSummary(result.Bundle),
			AccountID:  result.AccountID,
			Commands:   result.CommandNames,
			Services:   result.Health.Services,
			State:      optionalRecordJSONSummary(record),
		}
		if result.AccountID != "" {
			output.DashboardURL = cloudflare.WorkerDashboardURL(result.AccountID, deployment.WorkerName)
			output.LogsURL = cloudflare.WorkerLogsURL(result.AccountID, deployment.WorkerName)
		}
		return writeJSONOutput(output)
	}
	if *dryRun {
		fmt.Printf("Planned Cloudflare agent deployment\n")
	} else {
		fmt.Printf("Applied Cloudflare agent deployment\n")
	}
	fmt.Printf("  agent:    %s\n", deployment.AgentID)
	fmt.Printf("  worker:   %s\n", deployment.WorkerName)
	fmt.Printf("  bucket:   %s\n", deployment.BucketName)
	fmt.Printf("  host:     %s\n", deployment.Hostname)
	fmt.Printf("  files:    %s\n", result.Bundle.Directory)
	if record.AgentID != "" {
		fmt.Printf("  state:    %s\n", record.AgentID)
	}
	if result.AccountID != "" {
		fmt.Printf("  dashboard: %s\n", cloudflare.WorkerDashboardURL(result.AccountID, deployment.WorkerName))
		fmt.Printf("  logs:      %s\n", cloudflare.WorkerLogsURL(result.AccountID, deployment.WorkerName))
	}
	for _, command := range result.CommandNames {
		fmt.Printf("  command:  %s\n", command)
	}
	for _, service := range result.Health.Services {
		fmt.Printf("  service:  %s %s %s\n", service.Name, service.State, service.Message)
	}
	return nil
}
