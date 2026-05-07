package main

import (
	"errors"
	"testing"

	"agentprovision/internal/cloudflare"
	"agentprovision/internal/platform"
	"agentprovision/internal/state"
	"github.com/zalando/go-keyring"
)

// TestDeploymentInputUsesPlatformDefaults verifies one-click apply flag reduction.
func TestDeploymentInputUsesPlatformDefaults(t *testing.T) {
	input, err := deploymentInput("Sister Agent", "", "", "", false, platform.Config{
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
