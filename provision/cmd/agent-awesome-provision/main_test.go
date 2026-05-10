package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/platform"
	"agentprovision/internal/state"
	"github.com/zalando/go-keyring"
)

// TestDeploymentInputUsesPlatformDefaults verifies one-click apply flag reduction.
func TestDeploymentInputUsesPlatformDefaults(t *testing.T) {
	input, err := deploymentInput("Sister Agent", "", "", "", false, "", "", "", platform.Config{
		ZoneName:            "agent-awesome.com",
		AgentHostnameSuffix: "agent-awesome.com",
	}, true)
	if err != nil {
		t.Fatalf("deploymentInput() error = %v", err)
	}
	if input.UserID != "Sister Agent" {
		t.Fatalf("UserID = %q, want agent id default", input.UserID)
	}
	if input.Hostname != "sister-agent.agent-awesome.com" {
		t.Fatalf("Hostname = %q, want slugged platform hostname", input.Hostname)
	}
	if input.ZoneName != "agent-awesome.com" {
		t.Fatalf("ZoneName = %q, want platform zone", input.ZoneName)
	}
}

// TestHasCloudflareAssetsRequiresWorkerSmokeTest verifies repo discovery catches deploy gaps.
func TestHasCloudflareAssetsRequiresWorkerSmokeTest(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "Dockerfile.cloudflare"), "FROM scratch\n")
	writeTestFile(t, filepath.Join(root, "deploy", "cloudflare", "worker", "src", "index.ts"), "// worker\n")
	if hasCloudflareAssets(root) {
		t.Fatalf("hasCloudflareAssets() = true without smoke test")
	}

	writeTestFile(t, filepath.Join(root, "deploy", "cloudflare", "worker", "scripts", "smoke-test.mjs"), "// smoke\n")
	if !hasCloudflareAssets(root) {
		t.Fatalf("hasCloudflareAssets() = false with required assets")
	}
}

// TestRunCheckValidatesCloudflareAssets verifies preflight mode avoids credentials.
func TestRunCheckValidatesCloudflareAssets(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, filepath.Join(root, "Dockerfile.cloudflare"), "FROM scratch\n")
	writeTestFile(t, filepath.Join(root, "deploy", "cloudflare", "worker", "src", "index.ts"), "// worker\n")
	if err := run([]string{"check", "--repo-root", root}); err == nil {
		t.Fatalf("run(check) error = nil, want missing smoke test error")
	}
	writeTestFile(t, filepath.Join(root, "deploy", "cloudflare", "worker", "scripts", "smoke-test.mjs"), "// smoke\n")
	if err := run([]string{"check", "--repo-root", root}); err != nil {
		t.Fatalf("run(check) error = %v", err)
	}
}

// writeTestFile creates one test fixture file and its parent directories.
func writeTestFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
}

// TestExternalCredentialNameRejectsManagedTokens protects generated internal secrets.
func TestExternalCredentialNameRejectsManagedTokens(t *testing.T) {
	if _, err := externalCredentialName("AGENTAWESOME_GATEWAY_TOKEN"); err == nil {
		t.Fatalf("externalCredentialName() error = nil, want managed token rejection")
	}
}

// TestPrepareApplyStateDoesNotSaveRecord verifies failed remote applies cannot create local agents.
func TestPrepareApplyStateDoesNotSaveRecord(t *testing.T) {
	keyring.MockInit()
	t.Setenv("OPENAI_API_KEY", "openai")
	deployment, err := cloudflare.NewDeployment(cloudflare.DeploymentInput{
		AgentID:  "sister",
		UserID:   "sister",
		Hostname: "sister.agent-awesome.com",
		ZoneName: "agent-awesome.com",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}
	stateDir := t.TempDir()

	_, record, store, err := prepareApplyState(deployment, stateDir, false)
	if err != nil {
		t.Fatalf("prepareApplyState() error = %v", err)
	}
	if record.AgentID != "sister" {
		t.Fatalf("record.AgentID = %q, want sister", record.AgentID)
	}
	if _, err := store.Load("sister"); !errors.Is(err, state.ErrNotFound) {
		t.Fatalf("Load() error = %v, want unsaved record", err)
	}
}
