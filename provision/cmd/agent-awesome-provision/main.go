// Package main provides Agent Awesome provisioning commands.
package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/platform"
	"agentprovision/internal/state"
	"golang.org/x/term"
)

// main parses commands and exits with an operator-friendly status.
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "agent-awesome-provision: %v\n", err)
		os.Exit(1)
	}
}

// run dispatches the requested provisioning command.
func run(args []string) error {
	if len(args) < 1 {
		return usageError()
	}
	switch args[0] {
	case "cloudflare":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision cloudflare <render|apply>")
		}
		switch args[1] {
		case "render":
			return renderCloudflare(args[2:])
		case "apply":
			return applyCloudflare(args[2:])
		default:
			return fmt.Errorf("unknown cloudflare command %q", args[1])
		}
	case "platform":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision platform <init|show>")
		}
		switch args[1] {
		case "init":
			return initPlatform(args[2:])
		case "show":
			return showPlatform(args[2:])
		default:
			return fmt.Errorf("unknown platform command %q", args[1])
		}
	case "credentials":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision credentials <set|remove>")
		}
		switch args[1] {
		case "set":
			return setCredential(args[2:])
		case "remove":
			return removeCredential(args[2:])
		default:
			return fmt.Errorf("unknown credentials command %q", args[1])
		}
	case "agent":
		if len(args) < 2 {
			return fmt.Errorf("usage: agent-awesome-provision agent <list|status|delete>")
		}
		switch args[1] {
		case "list":
			return listAgents(args[2:])
		case "status":
			return statusAgent(args[2:])
		case "delete":
			return deleteAgent(args[2:])
		default:
			return fmt.Errorf("unknown agent command %q", args[1])
		}
	default:
		return usageError()
	}
}

// usageError returns the top-level command help as an error.
func usageError() error {
	return fmt.Errorf("usage: agent-awesome-provision <platform|credentials|cloudflare|agent> <command>")
}

// initPlatform writes operator defaults used by later apply commands.
func initPlatform(args []string) error {
	fs := flag.NewFlagSet("platform init", flag.ContinueOnError)
	configPath := fs.String("config", "", "platform config path; defaults to user config dir")
	cloudflareAccountID := fs.String("cloudflare-account-id", "", "Cloudflare account id for operator reference")
	zoneName := fs.String("zone-name", "", "Cloudflare zone name, such as agent-awesome.com")
	hostnameSuffix := fs.String("agent-hostname-suffix", "", "hostname suffix for provisioned agents; defaults to zone name")
	workerSourceDir := fs.String("worker-source-dir", "", "Agent Awesome repository root; defaults to auto-detected repo root")
	defaultModelProvider := fs.String("default-model-provider", "openai", "default model provider name")
	if err := fs.Parse(args); err != nil {
		return err
	}
	sourceDir := *workerSourceDir
	if sourceDir == "" {
		root, err := repoRoot("")
		if err != nil {
			return err
		}
		sourceDir = root
	}
	store, err := platformStore(*configPath)
	if err != nil {
		return err
	}
	config, err := store.Save(platform.Config{
		CloudflareAccountID:  *cloudflareAccountID,
		ZoneName:             *zoneName,
		AgentHostnameSuffix:  *hostnameSuffix,
		WorkerSourceDir:      sourceDir,
		DefaultModelProvider: *defaultModelProvider,
	})
	if err != nil {
		return err
	}
	fmt.Printf("Saved platform config\n")
	fmt.Printf("  path:     %s\n", store.Path())
	fmt.Printf("  account:  %s\n", displayOptional(config.CloudflareAccountID))
	fmt.Printf("  zone:     %s\n", config.ZoneName)
	fmt.Printf("  suffix:   %s\n", config.AgentHostnameSuffix)
	fmt.Printf("  source:   %s\n", config.WorkerSourceDir)
	fmt.Printf("  provider: %s\n", config.DefaultModelProvider)
	return nil
}

// showPlatform prints operator defaults without secret values.
func showPlatform(args []string) error {
	fs := flag.NewFlagSet("platform show", flag.ContinueOnError)
	configPath := fs.String("config", "", "platform config path; defaults to user config dir")
	if err := fs.Parse(args); err != nil {
		return err
	}
	store, err := platformStore(*configPath)
	if err != nil {
		return err
	}
	config, err := store.Load()
	if err != nil {
		return err
	}
	fmt.Printf("Platform config\n")
	fmt.Printf("  path:      %s\n", store.Path())
	fmt.Printf("  account:   %s\n", displayOptional(config.CloudflareAccountID))
	fmt.Printf("  zone:      %s\n", config.ZoneName)
	fmt.Printf("  suffix:    %s\n", config.AgentHostnameSuffix)
	fmt.Printf("  source:    %s\n", config.WorkerSourceDir)
	fmt.Printf("  provider:  %s\n", config.DefaultModelProvider)
	return nil
}

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
	if err := fs.Parse(args); err != nil {
		return err
	}
	config, hasConfig, err := loadOptionalPlatformConfig(*configPath)
	if err != nil {
		return err
	}
	input, err := deploymentInput(*agentID, *userID, *hostname, *zoneName, *slackEnabled, config, hasConfig)
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
	input, err := deploymentInput(*agentID, *userID, *hostname, *zoneName, *slackEnabled, config, hasConfig)
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

// setCredential stores one external provider credential in the OS keyring.
func setCredential(args []string) error {
	fs := flag.NewFlagSet("credentials set", flag.ContinueOnError)
	valueFlag := fs.String("value", "", "secret value; omit to read from stdin")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: agent-awesome-provision credentials set NAME [--value VALUE]")
	}
	name, err := externalCredentialName(fs.Arg(0))
	if err != nil {
		return err
	}
	value, err := readCredentialValue(*valueFlag, os.Stdin, os.Stderr, name)
	if err != nil {
		return err
	}
	if err := state.DefaultSecretStore().Set(name, value); err != nil {
		return err
	}
	fmt.Printf("Stored credential %s in the OS keyring\n", name)
	return nil
}

// removeCredential removes one external provider credential from the OS keyring.
func removeCredential(args []string) error {
	fs := flag.NewFlagSet("credentials remove", flag.ContinueOnError)
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: agent-awesome-provision credentials remove NAME")
	}
	name, err := externalCredentialName(fs.Arg(0))
	if err != nil {
		return err
	}
	if err := state.DefaultSecretStore().Delete(name); err != nil {
		return err
	}
	fmt.Printf("Removed credential %s from the OS keyring\n", name)
	return nil
}

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
	secrets, err := cloudflare.BuildSecretsWithTokens(deployment, credentialEnvironment{store: secretStore}, cloudflare.InternalTokens{
		GatewayToken:     gatewayToken,
		PersistenceToken: persistenceToken,
	})
	if err != nil {
		return nil, state.AgentRecord{}, state.Store{}, err
	}
	return secrets, record, store, nil
}

// platformStore returns the configured platform config store.
func platformStore(path string) (platform.Store, error) {
	if path != "" {
		absolute, err := filepath.Abs(path)
		if err != nil {
			return platform.Store{}, err
		}
		return platform.NewStore(absolute), nil
	}
	return platform.DefaultStore()
}

// loadOptionalPlatformConfig loads platform config when present.
func loadOptionalPlatformConfig(path string) (platform.Config, bool, error) {
	store, err := platformStore(path)
	if err != nil {
		return platform.Config{}, false, err
	}
	config, err := store.Load()
	if errors.Is(err, platform.ErrNotFound) {
		return platform.Config{}, false, nil
	}
	if err != nil {
		return platform.Config{}, false, err
	}
	return config, true, nil
}

// provisionStore returns the configured local provisioning state store.
func provisionStore(stateDir string) (state.Store, error) {
	if stateDir != "" {
		absolute, err := filepath.Abs(stateDir)
		if err != nil {
			return state.Store{}, err
		}
		return state.NewStore(absolute), nil
	}
	return state.DefaultStore()
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
func deploymentInput(agentID string, userID string, hostname string, zoneName string, slackEnabled bool, config platform.Config, hasConfig bool) (cloudflare.DeploymentInput, error) {
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
		AgentID:      agentID,
		UserID:       userID,
		Hostname:     hostname,
		ZoneName:     zoneName,
		SlackEnabled: slackEnabled,
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
		AgentID:      record.AgentID,
		UserID:       userID,
		Hostname:     record.Hostname,
		ZoneName:     record.ZoneName,
		SlackEnabled: record.SlackEnabled,
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

// credentialEnvironment resolves apply-time secrets from keyring then environment.
type credentialEnvironment struct {
	store state.KeyringSecretStore
}

// Lookup returns one external credential needed by a deployment.
func (e credentialEnvironment) Lookup(name string) (string, error) {
	if value, err := e.store.Lookup(name); err == nil {
		return value, nil
	}
	value := strings.TrimSpace(os.Getenv(name))
	if value != "" {
		return value, nil
	}
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", fmt.Errorf("credential %s is required; set it with `agent-awesome-provision credentials set %s` or export %s", name, name, name)
	}
	value, err := readHiddenCredential(os.Stdin, os.Stderr, name)
	if err != nil {
		return "", err
	}
	if err := e.store.Set(name, value); err != nil {
		return "", err
	}
	return value, nil
}

// externalCredentialName validates a user-managed provider credential name.
func externalCredentialName(name string) (string, error) {
	name = strings.ToUpper(strings.TrimSpace(name))
	if name == "" {
		return "", fmt.Errorf("credential name is required")
	}
	if name == "AGENTAWESOME_GATEWAY_TOKEN" || name == "AGENTAWESOME_PERSISTENCE_TOKEN" {
		return "", fmt.Errorf("%s is generated per agent by cloudflare apply", name)
	}
	for _, current := range name {
		if (current >= 'A' && current <= 'Z') || (current >= '0' && current <= '9') || current == '_' {
			continue
		}
		return "", fmt.Errorf("credential name %q must use uppercase letters, numbers, and underscores", name)
	}
	return name, nil
}

// readCredentialValue reads one secret value from a flag, terminal line, or pipe.
func readCredentialValue(explicit string, input *os.File, output io.Writer, name string) (string, error) {
	if strings.TrimSpace(explicit) != "" {
		return strings.TrimSpace(explicit), nil
	}
	if term.IsTerminal(int(input.Fd())) {
		return readHiddenCredential(input, output, name)
	}
	data, err := io.ReadAll(input)
	if err != nil {
		return "", fmt.Errorf("read credential: %w", err)
	}
	return nonEmptyCredentialValue(name, string(data))
}

// readHiddenCredential reads one secret from a terminal without echoing it.
func readHiddenCredential(input *os.File, output io.Writer, name string) (string, error) {
	fmt.Fprintf(output, "Enter %s: ", name)
	data, err := term.ReadPassword(int(input.Fd()))
	fmt.Fprintln(output)
	if err != nil {
		return "", fmt.Errorf("read credential: %w", err)
	}
	return nonEmptyCredentialValue(name, string(data))
}

// nonEmptyCredentialValue trims and validates one secret value.
func nonEmptyCredentialValue(name string, value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", fmt.Errorf("credential %s value is required", name)
	}
	return value, nil
}

// confirmAgentDelete requires exact typed confirmation for destructive cleanup.
func confirmAgentDelete(record state.AgentRecord, force bool, remote bool, input *os.File, output io.Writer) error {
	if force {
		return nil
	}
	if !term.IsTerminal(int(input.Fd())) {
		return fmt.Errorf("agent delete requires --force when stdin is not a terminal")
	}
	if remote {
		fmt.Fprintf(output, "This will delete Worker %s and R2 bucket %s.\n", record.WorkerName, record.BucketName)
	} else {
		fmt.Fprintf(output, "This will delete local provisioning state and generated tokens for %s.\n", record.AgentID)
	}
	fmt.Fprintf(output, "Type %q to continue: ", record.AgentID)
	value, err := bufio.NewReader(input).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return fmt.Errorf("read confirmation: %w", err)
	}
	if strings.TrimSpace(value) != record.AgentID {
		return fmt.Errorf("delete canceled")
	}
	return nil
}

// printOperationEvent prints one display-safe provisioning progress event.
func printOperationEvent(event cloudflare.OperationEvent) {
	message := ""
	if strings.TrimSpace(event.Message) != "" {
		message = " - " + event.Message
	}
	fmt.Printf("  %-9s %s%s\n", event.Status, event.Command, message)
}

// displayOptional returns a placeholder for optional unset display fields.
func displayOptional(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "(unset)"
	}
	return value
}

// repoRoot finds the repository root containing Cloudflare deployment assets.
func repoRoot(explicit string) (string, error) {
	if explicit != "" {
		absolute, err := filepath.Abs(explicit)
		if err != nil {
			return "", err
		}
		if !hasCloudflareAssets(absolute) {
			return "", fmt.Errorf("%s does not look like the Agent Awesome repo root", absolute)
		}
		return absolute, nil
	}
	workingDir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for current := workingDir; ; current = filepath.Dir(current) {
		if hasCloudflareAssets(current) {
			return current, nil
		}
		parent := filepath.Dir(current)
		if parent == current {
			return "", fmt.Errorf("could not find Agent Awesome repo root; use --repo-root")
		}
	}
}

// hasCloudflareAssets reports whether a directory looks like the repo root.
func hasCloudflareAssets(directory string) bool {
	dockerfile := filepath.Join(directory, "Dockerfile.cloudflare")
	worker := filepath.Join(directory, "deploy", "cloudflare", "worker", "src", "index.ts")
	if _, err := os.Stat(dockerfile); err != nil {
		return false
	}
	if _, err := os.Stat(worker); err != nil {
		return false
	}
	return true
}
