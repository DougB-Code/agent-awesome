package config

import "testing"

// TestFromFlagsDerivesDefaultHealthURLs verifies local dependency health defaults.
func TestFromFlagsDerivesDefaultHealthURLs(t *testing.T) {
	cfg, err := FromFlags([]string{
		"--harness-base-url", "http://127.0.0.1:8080/api",
		"--memory-mcp-url", "http://127.0.0.1:8090/mcp",
		"--app-name", "pilot",
		"--user-id", "doug",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.HarnessService.HealthURL != "http://127.0.0.1:8080/api/apps/pilot/users/doug/sessions" {
		t.Fatalf("harness health = %q", cfg.HarnessService.HealthURL)
	}
	if cfg.MemoryService.HealthURL != "http://127.0.0.1:8090/healthz" {
		t.Fatalf("memory health = %q", cfg.MemoryService.HealthURL)
	}
}

// TestValidateRequiresAutoStartCommand verifies auto-start cannot be commandless.
func TestValidateRequiresAutoStartCommand(t *testing.T) {
	_, err := FromFlags([]string{"--harness-auto-start"})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want command validation error")
	}
}

// TestSlackSocketModeRequiresAppToken verifies local Socket Mode config safety.
func TestSlackSocketModeRequiresAppToken(t *testing.T) {
	_, err := FromFlags([]string{
		"--slack-enabled",
		"--slack-socket-mode",
		"--slack-bot-token", "xoxb-test",
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want app token validation error")
	}
}

// TestSlackHTTPModeRequiresSigningSecret verifies cloud webhook config safety.
func TestSlackHTTPModeRequiresSigningSecret(t *testing.T) {
	_, err := FromFlags([]string{
		"--slack-enabled",
		"--slack-bot-token", "xoxb-test",
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want signing secret validation error")
	}
}

// TestSlackEnvUsesPlainSlackNames verifies Slack secrets do not use app prefixes.
func TestSlackEnvUsesPlainSlackNames(t *testing.T) {
	t.Setenv("SLACK_ENABLED", "true")
	t.Setenv("SLACK_SOCKET_MODE", "true")
	t.Setenv("SLACK_APP_TOKEN", "xapp-test")
	t.Setenv("SLACK_BOT_TOKEN", "xoxb-test")

	cfg, err := FromFlags(nil)
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if !cfg.Slack.Enabled || !cfg.Slack.SocketMode {
		t.Fatalf("slack mode = enabled:%v socket:%v, want both true", cfg.Slack.Enabled, cfg.Slack.SocketMode)
	}
	if cfg.Slack.AppToken != "xapp-test" || cfg.Slack.BotToken != "xoxb-test" {
		t.Fatalf("slack tokens = app:%q bot:%q", cfg.Slack.AppToken, cfg.Slack.BotToken)
	}
}
