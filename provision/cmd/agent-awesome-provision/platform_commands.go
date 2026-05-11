// Package main implements platform configuration command handlers.
package main

import (
	"flag"
	"fmt"

	"agentprovision/internal/platform"
)

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
