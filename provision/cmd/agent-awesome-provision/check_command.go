// Package main implements provisioning preflight command handlers.
package main

import (
	"flag"
	"fmt"
)

// checkConfig validates local beta deployment inputs without starting services.
func checkConfig(args []string) error {
	fs := flag.NewFlagSet("check", flag.ContinueOnError)
	repoRootFlag := fs.String("repo-root", "", "Agent Awesome repository root")
	configPath := fs.String("platform-config", "", "platform config path; defaults to user config dir")
	if err := fs.Parse(args); err != nil {
		return err
	}
	config, hasConfig, err := loadOptionalPlatformConfig(*configPath)
	if err != nil {
		return err
	}
	repoRoot, err := resolveRepoRoot(*repoRootFlag, config, hasConfig)
	if err != nil {
		return err
	}
	if !hasCloudflareAssets(repoRoot) {
		return fmt.Errorf("required Cloudflare Worker assets are missing under %s", repoRoot)
	}
	fmt.Printf("Provisioning preflight ok\n")
	fmt.Printf("  repo: %s\n", repoRoot)
	return nil
}
