package cloudflare

import (
	"strings"
	"testing"
)

// TestNewDeploymentUsesDedicatedBucket verifies per-agent bucket isolation.
func TestNewDeploymentUsesDedicatedBucket(t *testing.T) {
	deployment, err := NewDeployment(DeploymentInput{
		AgentID:      "Sister Agent",
		UserID:       "sister",
		Hostname:     "sister.agent-awesome.com",
		SlackEnabled: false,
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}

	if deployment.AgentID != "sister-agent" {
		t.Fatalf("AgentID = %q, want sister-agent", deployment.AgentID)
	}
	if deployment.BucketName != "agent-awesome-sister-agent-memory" {
		t.Fatalf("BucketName = %q, want dedicated bucket", deployment.BucketName)
	}
	if deployment.SnapshotKey != "memory/memory/context-snapshot.tar.gz" {
		t.Fatalf("SnapshotKey = %q, want default domain snapshot key", deployment.SnapshotKey)
	}
	if contains(deployment.RequiredSecrets, "SLACK_BOT_TOKEN") {
		t.Fatalf("RequiredSecrets included Slack when disabled: %v", deployment.RequiredSecrets)
	}
}

// TestWranglerIncludesSlackSecretsWhenEnabled verifies Slack remains optional.
func TestWranglerIncludesSlackSecretsWhenEnabled(t *testing.T) {
	deployment, err := NewDeployment(DeploymentInput{
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
	wrangler := deployment.Wrangler()

	if wrangler.Vars["SLACK_ENABLED"] != "true" {
		t.Fatalf("SLACK_ENABLED = %q, want true", wrangler.Vars["SLACK_ENABLED"])
	}
	if wrangler.Vars["AGENTAWESOME_SLACK_MEMORY_TOOLS"] != "true" {
		t.Fatalf("AGENTAWESOME_SLACK_MEMORY_TOOLS = %q, want true", wrangler.Vars["AGENTAWESOME_SLACK_MEMORY_TOOLS"])
	}
	if wrangler.Vars["AGENTAWESOME_MODEL_PROVIDER_ID"] != "openai" || wrangler.Vars["AGENTAWESOME_MODEL_ID"] != "gpt-mini" {
		t.Fatalf("model status vars = %#v", wrangler.Vars)
	}
	if wrangler.Vars["AGENTAWESOME_GATEWAY_LOG_FILE"] != "/app/logs/gateway.log" {
		t.Fatalf("gateway log file = %q, want /app/logs/gateway.log", wrangler.Vars["AGENTAWESOME_GATEWAY_LOG_FILE"])
	}
	if wrangler.Vars["AGENTAWESOME_MEMORY_DOMAINS_JSON"] != `[{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"}]` {
		t.Fatalf("memory domains var = %q", wrangler.Vars["AGENTAWESOME_MEMORY_DOMAINS_JSON"])
	}
	if wrangler.Vars["AGENTAWESOME_MEMORY_POLICY_JSON"] != `{"actor":"agent:sister","read_domains":["memory"],"write_domains":["memory"],"default_write_domain":"memory","allowed_sensitivities":["public","internal","private"]}` {
		t.Fatalf("memory policy var = %q", wrangler.Vars["AGENTAWESOME_MEMORY_POLICY_JSON"])
	}
	if !containsString(wrangler.Vars["AGENTAWESOME_MEMORY_SERVICES_JSON"], `"domain_id":"memory"`) ||
		!containsString(wrangler.Vars["AGENTAWESOME_MEMORY_SERVICES_JSON"], `"--snapshot-url","https://sister.agent-awesome.com/internal/context-snapshot/memory"`) {
		t.Fatalf("memory services var = %q", wrangler.Vars["AGENTAWESOME_MEMORY_SERVICES_JSON"])
	}
	if wrangler.Vars["AGENTAWESOME_MEMORY_SNAPSHOT_PREFIX"] != "memory" {
		t.Fatalf("snapshot prefix = %q, want memory", wrangler.Vars["AGENTAWESOME_MEMORY_SNAPSHOT_PREFIX"])
	}
	if _, ok := wrangler.Vars["AGENTAWESOME_MEMORY_SNAPSHOT_KEY"]; ok {
		t.Fatalf("wrangler vars included shared snapshot key: %#v", wrangler.Vars)
	}
	if wrangler.Vars["SLACK_ALLOWED_TEAM_ID"] != "T1" || wrangler.Vars["SLACK_ALLOWED_USER_ID"] != "U1" || wrangler.Vars["SLACK_ALLOWED_CHANNEL_ID"] != "C1" {
		t.Fatalf("Slack allow-list vars = %#v", wrangler.Vars)
	}
	if !contains(wrangler.Secrets.Required, "SLACK_SIGNING_SECRET") {
		t.Fatalf("required secrets missing Slack signing secret: %v", wrangler.Secrets.Required)
	}
	if got := wrangler.R2Buckets[0].BucketName; got != "agent-awesome-sister-memory" {
		t.Fatalf("bucket = %q, want agent-awesome-sister-memory", got)
	}
}

// TestNewDeploymentRequiresSlackAllowLists verifies Slack beta deployments are scoped.
func TestNewDeploymentRequiresSlackAllowLists(t *testing.T) {
	_, err := NewDeployment(DeploymentInput{
		AgentID:      "sister",
		UserID:       "sister",
		Hostname:     "sister.agent-awesome.com",
		SlackEnabled: true,
	})
	if err == nil {
		t.Fatalf("NewDeployment() error = nil, want Slack allow-list validation error")
	}
}

// TestSlugRejectsEmptyIdentifiers verifies invalid agent ids are blocked.
func TestSlugRejectsEmptyIdentifiers(t *testing.T) {
	if _, err := Slug("___"); err == nil {
		t.Fatalf("Slug() error = nil, want invalid identifier")
	}
}

// containsString reports whether a string contains one exact substring.
func containsString(value string, target string) bool {
	return strings.Contains(value, target)
}

// contains reports whether a list contains one exact value.
func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
