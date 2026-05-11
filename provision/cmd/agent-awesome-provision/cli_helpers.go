// Package main contains terminal prompts, display helpers, and repo discovery.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/state"
	"golang.org/x/term"
)

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
	required := []string{
		filepath.Join(directory, "Dockerfile.cloudflare"),
		filepath.Join(directory, "deploy", "cloudflare", "worker", "src", "index.ts"),
		filepath.Join(directory, "deploy", "cloudflare", "worker", "scripts", "smoke-test.mjs"),
	}
	for _, path := range required {
		if _, err := os.Stat(path); err != nil {
			return false
		}
	}
	return true
}
