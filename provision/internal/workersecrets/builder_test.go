// This file verifies Worker secret value assembly.
package workersecrets

import (
	"errors"
	"testing"

	"agentprovision/internal/cloudflare"
)

// TestBuildWithTokensRequiresSlackSecretsWhenEnabled verifies optional Slack setup gates credential lookup.
func TestBuildWithTokensRequiresSlackSecretsWhenEnabled(t *testing.T) {
	deployment, err := cloudflare.NewDeployment(cloudflare.DeploymentInput{
		AgentID:               "sister",
		UserID:                "sister",
		Hostname:              "sister.agent-awesome.com",
		SlackEnabled:          true,
		SlackAllowedTeamID:    "T1",
		SlackAllowedUserID:    "U1",
		SlackAllowedChannelID: "C1",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}

	_, err = BuildWithTokens(deployment, mapSource{"OPENAI_API_KEY": "openai"}, testTokens())
	if err == nil {
		t.Fatalf("BuildWithTokens() error = nil, want missing Slack secret")
	}
}

// TestBuildWithTokensReturnsAllRequiredSecrets verifies generated and external values are combined.
func TestBuildWithTokensReturnsAllRequiredSecrets(t *testing.T) {
	deployment, err := cloudflare.NewDeployment(cloudflare.DeploymentInput{
		AgentID:  "sister",
		UserID:   "sister",
		Hostname: "sister.agent-awesome.com",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}

	values, err := BuildWithTokens(deployment, mapSource{"OPENAI_API_KEY": "openai"}, testTokens())
	if err != nil {
		t.Fatalf("BuildWithTokens() error = %v", err)
	}
	for _, name := range deployment.RequiredSecrets {
		if values[name] == "" {
			t.Fatalf("secret %s is empty in %#v", name, values)
		}
	}
}

// TestBuildWithTokensRequiresGeneratedTokens protects internal Worker authentication.
func TestBuildWithTokensRequiresGeneratedTokens(t *testing.T) {
	deployment, err := cloudflare.NewDeployment(cloudflare.DeploymentInput{
		AgentID:  "sister",
		UserID:   "sister",
		Hostname: "sister.agent-awesome.com",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}

	_, err = BuildWithTokens(deployment, mapSource{"OPENAI_API_KEY": "openai"}, InternalTokens{})
	if err == nil {
		t.Fatalf("BuildWithTokens() error = nil, want missing generated token")
	}
}

// mapSource reads secrets from a test map.
type mapSource map[string]string

// Lookup returns one mapped secret value.
func (m mapSource) Lookup(name string) (string, error) {
	value, ok := m[name]
	if !ok {
		return "", errMissingTestSecret
	}
	return value, nil
}

// testTokens returns stable internal token values.
func testTokens() InternalTokens {
	return InternalTokens{GatewayToken: "gateway", PersistenceToken: "persistence"}
}

// errMissingTestSecret is a stable test error value.
var errMissingTestSecret = errors.New("missing test secret")
