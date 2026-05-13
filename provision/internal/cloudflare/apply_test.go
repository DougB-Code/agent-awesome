// This file verifies Cloudflare apply orchestration and command planning.
package cloudflare

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// TestApplyDryRunBuildsCommands verifies dry runs render without reading secrets.
func TestApplyDryRunBuildsCommands(t *testing.T) {
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

	result, err := Apply(t.Context(), deployment, ApplyOptions{
		WorkerDirectory: t.TempDir(),
		OutputDirectory: t.TempDir(),
		Runner:          recordingRunner{},
		DryRun:          true,
	})
	if err != nil {
		t.Fatalf("Apply() error = %v", err)
	}

	if len(result.CommandNames) != 7 {
		t.Fatalf("command count = %d, want bucket + 5 secrets + deploy", len(result.CommandNames))
	}
	if result.CommandNames[0] != "npx wrangler r2 bucket create agent-awesome-sister-memory" {
		t.Fatalf("first command = %q", result.CommandNames[0])
	}
}

// TestApplyDryRunWithAPISkipsWranglerBucketCreate verifies direct R2 reconciliation replaces Wrangler bucket create.
func TestApplyDryRunWithAPISkipsWranglerBucketCreate(t *testing.T) {
	deployment, err := NewDeployment(DeploymentInput{
		AgentID:  "sister",
		UserID:   "sister",
		Hostname: "sister.agent-awesome.com",
		ZoneName: "agent-awesome.com",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}
	api, err := NewAPIClient(APIClientOptions{AccountID: "account"})
	if err != nil {
		t.Fatalf("NewAPIClient() error = %v", err)
	}

	result, err := Apply(t.Context(), deployment, ApplyOptions{
		WorkerDirectory: t.TempDir(),
		OutputDirectory: t.TempDir(),
		Runner:          recordingRunner{},
		API:             api,
		DryRun:          true,
	})
	if err != nil {
		t.Fatalf("Apply() error = %v", err)
	}
	if containsCommand(result.CommandNames, "npx wrangler r2 bucket create") {
		t.Fatalf("CommandNames included Wrangler bucket create: %v", result.CommandNames)
	}
	if !containsCommand(result.CommandNames, "cloudflare api r2 bucket ensure agent-awesome-sister-memory") {
		t.Fatalf("CommandNames missing direct R2 ensure: %v", result.CommandNames)
	}
}

// TestDeleteDryRunBuildsCommands verifies destructive cleanup is inspectable first.
func TestDeleteDryRunBuildsCommands(t *testing.T) {
	deployment, err := NewDeployment(DeploymentInput{
		AgentID:      "sister",
		UserID:       "sister",
		Hostname:     "sister.agent-awesome.com",
		SlackEnabled: false,
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}

	result, err := Delete(t.Context(), deployment, DeleteOptions{
		WorkerDirectory: t.TempDir(),
		Runner:          recordingRunner{},
		DryRun:          true,
	})
	if err != nil {
		t.Fatalf("Delete() error = %v", err)
	}

	if len(result.CommandNames) != 3 {
		t.Fatalf("command count = %d, want worker + object + bucket delete", len(result.CommandNames))
	}
	if !strings.HasPrefix(result.CommandNames[0], "npx wrangler delete agent-awesome-sister --config ") || !strings.HasSuffix(result.CommandNames[0], " --force") {
		t.Fatalf("first command = %q", result.CommandNames[0])
	}
	if result.CommandNames[1] != "npx wrangler r2 object delete agent-awesome-sister-memory/memory/memory/context-snapshot.tar.gz --remote --force" {
		t.Fatalf("second command = %q", result.CommandNames[1])
	}
	if result.CommandNames[2] != "npx wrangler r2 bucket delete agent-awesome-sister-memory" {
		t.Fatalf("third command = %q", result.CommandNames[2])
	}
}

// TestDeleteDryRunWithAPIUsesDirectBucketCleanup verifies object cleanup stays on Wrangler.
func TestDeleteDryRunWithAPIUsesDirectBucketCleanup(t *testing.T) {
	deployment := testDeployment(t)
	api, err := NewAPIClient(APIClientOptions{AccountID: "account"})
	if err != nil {
		t.Fatalf("NewAPIClient() error = %v", err)
	}

	result, err := Delete(t.Context(), deployment, DeleteOptions{
		WorkerDirectory: t.TempDir(),
		Runner:          recordingRunner{},
		API:             api,
		DryRun:          true,
	})
	if err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if !containsCommand(result.CommandNames, "npx wrangler r2 object delete") {
		t.Fatalf("CommandNames missing Wrangler object cleanup: %v", result.CommandNames)
	}
	if containsCommand(result.CommandNames, "npx wrangler r2 bucket delete") {
		t.Fatalf("CommandNames included Wrangler bucket cleanup: %v", result.CommandNames)
	}
	if !containsCommand(result.CommandNames, "cloudflare api route delete sister.agent-awesome.com/*") {
		t.Fatalf("CommandNames missing direct route delete: %v", result.CommandNames)
	}
	if !containsCommand(result.CommandNames, "cloudflare api r2 bucket delete agent-awesome-sister-memory") {
		t.Fatalf("CommandNames missing direct R2 bucket delete: %v", result.CommandNames)
	}
}

// TestEnsureWorkerScriptBootstrapsMissingWorker verifies first-time secret uploads have a script target.
func TestEnsureWorkerScriptBootstrapsMissingWorker(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/accounts/account/workers/scripts/agent-awesome-sister" {
			t.Fatalf("unexpected request %s %s", r.Method, r.URL.String())
		}
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"success":false,"errors":[{"message":"not found"}]}`))
	}))
	defer server.Close()
	api := newTestAPIClient(t, server.URL)
	runner := &bootstrapRecordingRunner{}

	commands, err := ensureWorkerScript(t.Context(), testDeployment(t), ApplyOptions{
		WorkerDirectory: t.TempDir(),
		Runner:          runner,
		API:             api,
	})
	if err != nil {
		t.Fatalf("ensureWorkerScript() error = %v", err)
	}
	if len(commands) != 2 || !strings.HasPrefix(commands[0], "cloudflare api worker inspect ") {
		t.Fatalf("commands = %v, want inspect plus bootstrap deploy", commands)
	}
	if len(runner.commands) != 1 {
		t.Fatalf("runner commands = %d, want one bootstrap deploy", len(runner.commands))
	}
	if strings.Contains(runner.config, `"routes"`) || strings.Contains(runner.config, `"required"`) {
		t.Fatalf("bootstrap config exposed routes or required secrets:\n%s", runner.config)
	}
}

// TestCommandFailureDiagnosesNodeVersion verifies prerequisite failures are actionable.
func TestCommandFailureDiagnosesNodeVersion(t *testing.T) {
	err := commandFailure(Command{Name: "npx", Arguments: []string{"wrangler", "deploy"}}, CommandResult{
		Output: "Wrangler requires at least Node.js v22.0.0. You are using v18.19.1.",
	}, errors.New("test command failed"))
	if !strings.Contains(err.Error(), "Install Node.js 22 or newer") {
		t.Fatalf("commandFailure() = %v, want Node diagnosis", err)
	}
}

// TestApplyRequiresSecretsWhenLive verifies Cloudflare apply never sources secrets itself.
func TestApplyRequiresSecretsWhenLive(t *testing.T) {
	deployment, err := NewDeployment(DeploymentInput{
		AgentID:  "sister",
		UserID:   "sister",
		Hostname: "sister.agent-awesome.com",
	})
	if err != nil {
		t.Fatalf("NewDeployment() error = %v", err)
	}

	_, err = Apply(t.Context(), deployment, ApplyOptions{
		WorkerDirectory: t.TempDir(),
		OutputDirectory: t.TempDir(),
		Runner:          recordingRunner{},
	})
	if err == nil || !strings.Contains(err.Error(), "secret values are required") {
		t.Fatalf("Apply() error = %v, want missing secrets", err)
	}
}

// TestAllServicesConnectedRequiresHarnessAndMemory verifies health readiness criteria.
func TestAllServicesConnectedRequiresHarnessAndMemory(t *testing.T) {
	if allServicesConnected([]ServiceStatus{{Name: "harness", State: "connected"}}) {
		t.Fatalf("allServicesConnected() accepted missing memory service")
	}
	if !allServicesConnected([]ServiceStatus{
		{Name: "harness", State: "connected"},
		{Name: "memory", State: "connected"},
	}) {
		t.Fatalf("allServicesConnected() rejected connected services")
	}
	if !allServicesConnected([]ServiceStatus{
		{Name: "harness", State: "connected"},
		{Name: "memory", State: "connected"},
		{Name: "memory-project", State: "connected"},
	}) {
		t.Fatalf("allServicesConnected() rejected connected multi-memory services")
	}
	if allServicesConnected([]ServiceStatus{
		{Name: "harness", State: "connected"},
		{Name: "memory", State: "connected"},
		{Name: "memory-project", State: "starting"},
	}) {
		t.Fatalf("allServicesConnected() accepted pending multi-memory service")
	}
}

// recordingRunner records no commands because dry-run mode skips execution.
type recordingRunner struct{}

// Run records one command invocation.
func (recordingRunner) Run(context.Context, Command) (CommandResult, error) {
	return CommandResult{}, nil
}

// bootstrapRecordingRunner records bootstrap deploy commands and config content.
type bootstrapRecordingRunner struct {
	commands []Command
	config   string
}

// Run records one bootstrap command and reads its transient config.
func (r *bootstrapRecordingRunner) Run(_ context.Context, command Command) (CommandResult, error) {
	r.commands = append(r.commands, command)
	if len(command.Arguments) >= 4 && command.Arguments[0] == "wrangler" && command.Arguments[1] == "deploy" {
		data, err := os.ReadFile(command.Arguments[3])
		if err != nil {
			return CommandResult{}, err
		}
		r.config = string(data)
	}
	return CommandResult{}, nil
}

// containsCommand reports whether a command list contains one prefix.
func containsCommand(commands []string, prefix string) bool {
	for _, command := range commands {
		if strings.HasPrefix(command, prefix) {
			return true
		}
	}
	return false
}
