package cloudflare

import "testing"

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
	if deployment.SnapshotKey != "context-snapshot.tar.gz" {
		t.Fatalf("SnapshotKey = %q, want dedicated-bucket snapshot key", deployment.SnapshotKey)
	}
	if contains(deployment.RequiredSecrets, "SLACK_BOT_TOKEN") {
		t.Fatalf("RequiredSecrets included Slack when disabled: %v", deployment.RequiredSecrets)
	}
}

// TestWranglerIncludesSlackSecretsWhenEnabled verifies Slack remains optional.
func TestWranglerIncludesSlackSecretsWhenEnabled(t *testing.T) {
	deployment, err := NewDeployment(DeploymentInput{
		AgentID:      "sister",
		UserID:       "sister",
		Hostname:     "sister.agent-awesome.com",
		SlackEnabled: true,
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}
	wrangler := deployment.Wrangler()

	if wrangler.Vars["SLACK_ENABLED"] != "true" {
		t.Fatalf("SLACK_ENABLED = %q, want true", wrangler.Vars["SLACK_ENABLED"])
	}
	if !contains(wrangler.Secrets.Required, "SLACK_SIGNING_SECRET") {
		t.Fatalf("required secrets missing Slack signing secret: %v", wrangler.Secrets.Required)
	}
	if got := wrangler.R2Buckets[0].BucketName; got != "agent-awesome-sister-memory" {
		t.Fatalf("bucket = %q, want agent-awesome-sister-memory", got)
	}
}

// TestSlugRejectsEmptyIdentifiers verifies invalid agent ids are blocked.
func TestSlugRejectsEmptyIdentifiers(t *testing.T) {
	if _, err := Slug("___"); err == nil {
		t.Fatalf("Slug() error = nil, want invalid identifier")
	}
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
