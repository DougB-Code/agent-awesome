// Package main implements provisioned-agent lifecycle command handlers.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/state"
)

// listAgents prints locally known provisioned agents.
func listAgents(args []string) error {
	fs := flag.NewFlagSet("agent list", flag.ContinueOnError)
	stateDirFlag := fs.String("state-dir", "", "provisioning state directory; defaults to user config dir")
	jsonOutput := fs.Bool("json", false, "write structured JSON output")
	if err := fs.Parse(args); err != nil {
		return err
	}
	store, err := provisionStore(*stateDirFlag)
	if err != nil {
		return err
	}
	records, err := store.List()
	if err != nil {
		return err
	}
	if *jsonOutput {
		output := listOutput{Agents: []provisionedAgentJSONSummary{}}
		for _, record := range records {
			output.Agents = append(output.Agents, recordJSONSummary(record))
		}
		return writeJSONOutput(output)
	}
	if len(records) == 0 {
		fmt.Printf("No provisioned agents found\n")
		return nil
	}
	fmt.Printf("Provisioned agents\n")
	for _, record := range records {
		fmt.Printf("  %s  %s  %s\n", record.AgentID, record.Hostname, record.WorkerName)
	}
	return nil
}

// statusAgent health-checks one provisioned agent through its gateway.
func statusAgent(args []string) error {
	fs := flag.NewFlagSet("agent status", flag.ContinueOnError)
	stateDirFlag := fs.String("state-dir", "", "provisioning state directory; defaults to user config dir")
	healthTimeout := fs.Duration("health-timeout", 30*time.Second, "maximum deployed gateway health-check wait")
	jsonOutput := fs.Bool("json", false, "write structured JSON output")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: agent-awesome-provision agent status AGENT_ID")
	}
	store, err := provisionStore(*stateDirFlag)
	if err != nil {
		return err
	}
	agentID, err := cloudflare.Slug(fs.Arg(0))
	if err != nil {
		return err
	}
	record, err := store.Load(agentID)
	if err != nil {
		return err
	}
	gatewayToken, err := state.DefaultSecretStore().Lookup(record.GatewayTokenCredential)
	if err != nil {
		return fmt.Errorf("gateway token for %s is unavailable; rerun cloudflare apply: %w", record.AgentID, err)
	}
	health, err := cloudflare.WaitForHealth(context.Background(), cloudflare.Deployment{Hostname: record.Hostname}, gatewayToken, *healthTimeout)
	if err != nil {
		return err
	}
	if *jsonOutput {
		return writeJSONOutput(statusOutput{
			Agent:    recordJSONSummary(record),
			Services: health.Services,
		})
	}
	fmt.Printf("Agent %s\n", record.AgentID)
	fmt.Printf("  host:    %s\n", record.Hostname)
	fmt.Printf("  worker:  %s\n", record.WorkerName)
	fmt.Printf("  bucket:  %s\n", record.BucketName)
	for _, service := range health.Services {
		fmt.Printf("  service: %s %s %s\n", service.Name, service.State, service.Message)
	}
	return nil
}

// deleteAgent removes Cloudflare resources and local state for one provisioned agent.
func deleteAgent(args []string) error {
	fs := flag.NewFlagSet("agent delete", flag.ContinueOnError)
	stateDirFlag := fs.String("state-dir", "", "provisioning state directory; defaults to user config dir")
	repoRootFlag := fs.String("repo-root", "", "Agent Awesome repository root")
	configPath := fs.String("platform-config", "", "platform config path; defaults to user config dir")
	dryRun := fs.Bool("dry-run", false, "render and list destructive actions without calling Cloudflare or deleting local state")
	force := fs.Bool("force", false, "skip confirmation prompt")
	localOnly := fs.Bool("local-only", false, "delete only the local record and generated tokens")
	jsonOutput := fs.Bool("json", false, "write structured JSON output")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: agent-awesome-provision agent delete AGENT_ID")
	}
	store, err := provisionStore(*stateDirFlag)
	if err != nil {
		return err
	}
	agentID, err := cloudflare.Slug(fs.Arg(0))
	if err != nil {
		return err
	}
	record, err := store.Load(agentID)
	if err != nil {
		return err
	}
	if !*dryRun {
		if err := confirmAgentDelete(record, *force, !*localOnly, os.Stdin, os.Stderr); err != nil {
			return err
		}
	}
	if *localOnly {
		if *dryRun {
			if *jsonOutput {
				return writeJSONOutput(localDeleteOutput{
					Action: "delete-local",
					DryRun: true,
					Agent:  recordJSONSummary(record),
				})
			}
			fmt.Printf("Planned local deletion for agent %s\n", record.AgentID)
			return nil
		}
		if err := deleteLocalAgent(store, record); err != nil {
			return err
		}
		if *jsonOutput {
			return writeJSONOutput(localDeleteOutput{
				Action: "delete-local",
				DryRun: false,
				Agent:  recordJSONSummary(record),
			})
		}
		fmt.Printf("Deleted local provisioning state for agent %s\n", record.AgentID)
		return nil
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
	deployment, err := deploymentFromRecord(record)
	if err != nil {
		return err
	}
	result, err := cloudflare.Delete(context.Background(), deployment, cloudflare.DeleteOptions{
		WorkerDirectory: filepath.Join(repoRoot, "deploy", "cloudflare", "worker"),
		API:             cloudflareRuntime.API,
		WranglerEnv:     cloudflareRuntime.WranglerEnv,
		DryRun:          *dryRun,
		Progress:        progressPrinter(*jsonOutput),
	})
	if err != nil {
		return err
	}
	if *dryRun {
		if !*jsonOutput {
			fmt.Printf("Planned Cloudflare agent deletion\n")
		}
	} else {
		if err := deleteLocalAgent(store, record); err != nil {
			return err
		}
		if !*jsonOutput {
			fmt.Printf("Deleted Cloudflare agent deployment\n")
		}
	}
	if *jsonOutput {
		output := deleteOutput{
			Action:     "delete",
			DryRun:     *dryRun,
			Deployment: deploymentJSONSummary(deployment),
			AccountID:  result.AccountID,
			Commands:   result.CommandNames,
		}
		if result.AccountID != "" {
			output.DashboardURL = cloudflare.WorkerDashboardURL(result.AccountID, deployment.WorkerName)
		}
		return writeJSONOutput(output)
	}
	fmt.Printf("  agent:   %s\n", record.AgentID)
	fmt.Printf("  worker:  %s\n", deployment.WorkerName)
	fmt.Printf("  bucket:  %s\n", deployment.BucketName)
	if result.AccountID != "" {
		fmt.Printf("  dashboard: %s\n", cloudflare.WorkerDashboardURL(result.AccountID, deployment.WorkerName))
	}
	for _, command := range result.CommandNames {
		fmt.Printf("  command: %s\n", command)
	}
	return nil
}
