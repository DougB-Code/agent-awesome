// This file tests gateway configuration parsing and safety validation.
package config

import "testing"

// TestFromFlagsDerivesDefaultHealthURLs verifies local dependency health defaults.
func TestFromFlagsDerivesDefaultHealthURLs(t *testing.T) {
	clearGatewayAuthEnv(t)
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
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{"--harness-auto-start"})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want command validation error")
	}
}

// TestLoopbackBindWithoutTokenAllowed verifies local-only gateway auth remains optional.
func TestLoopbackBindWithoutTokenAllowed(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--addr", "127.0.0.1:0"})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.AuthToken != "" {
		t.Fatalf("AuthToken = %q, want empty", cfg.AuthToken)
	}
}

// TestPublicBindWithoutTokenRejected verifies public gateways cannot start unauthenticated.
func TestPublicBindWithoutTokenRejected(t *testing.T) {
	clearGatewayAuthEnv(t)
	if _, err := FromFlags([]string{"--addr", "0.0.0.0:8070"}); err == nil {
		t.Fatalf("FromFlags() error = nil, want auth token validation error")
	}
}

// TestPublicBindWithTokenAllowed verifies authenticated cloud binds remain supported.
func TestPublicBindWithTokenAllowed(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--addr", "0.0.0.0:8070", "--auth-token", "secret"})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.AuthToken != "secret" {
		t.Fatalf("AuthToken = %q, want secret", cfg.AuthToken)
	}
}

// TestRemoteAllowedOriginWithoutTokenRejected verifies browser exposure requires auth.
func TestRemoteAllowedOriginWithoutTokenRejected(t *testing.T) {
	clearGatewayAuthEnv(t)
	if _, err := FromFlags([]string{
		"--addr", "127.0.0.1:8070",
		"--allowed-origin", "https://agent-awesome.com",
	}); err == nil {
		t.Fatalf("FromFlags() error = nil, want auth token validation error")
	}
}

// TestLoopbackAllowedOriginWithoutTokenAllowed verifies local browser clients still work.
func TestLoopbackAllowedOriginWithoutTokenAllowed(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--addr", "127.0.0.1:8070",
		"--allowed-origin", "http://localhost:3000",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.AllowedOrigin != "http://localhost:3000" {
		t.Fatalf("AllowedOrigin = %q, want local origin", cfg.AllowedOrigin)
	}
}

// TestRemoteAllowedOriginWithTokenAllowed verifies cloud browser clients use bearer auth.
func TestRemoteAllowedOriginWithTokenAllowed(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--addr", "127.0.0.1:8070",
		"--allowed-origin", "https://agent-awesome.com",
		"--auth-token", "secret",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.AuthToken != "secret" {
		t.Fatalf("AuthToken = %q, want secret", cfg.AuthToken)
	}
}

// TestUnauthenticatedLoopbackModeCanBeDisabled verifies auth can be forced locally.
func TestUnauthenticatedLoopbackModeCanBeDisabled(t *testing.T) {
	clearGatewayAuthEnv(t)
	if _, err := FromFlags([]string{
		"--addr", "127.0.0.1:8070",
		"--allow-unauthenticated-loopback-only=false",
	}); err == nil {
		t.Fatalf("FromFlags() error = nil, want auth token validation error")
	}
}

// TestRuntimePolicyTextCanBeConfigured verifies policy text is gateway config.
func TestRuntimePolicyTextCanBeConfigured(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--runtime-policy-text", "Configured policy text."})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.RuntimePolicyText != "Configured policy text." {
		t.Fatalf("RuntimePolicyText = %q, want configured value", cfg.RuntimePolicyText)
	}
}

// TestRuntimePolicyTextDefaultsEmpty verifies policy injection is opt-in.
func TestRuntimePolicyTextDefaultsEmpty(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags(nil)
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.RuntimePolicyText != "" {
		t.Fatalf("RuntimePolicyText = %q, want empty default", cfg.RuntimePolicyText)
	}
}

// TestContextAPITokenCanBeConfigured verifies gateway-to-harness context auth.
func TestContextAPITokenCanBeConfigured(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--context-api-token", "context-secret"})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.ContextAPIToken != "context-secret" {
		t.Fatalf("ContextAPIToken = %q, want configured token", cfg.ContextAPIToken)
	}
	if cfg.StatusView()["has_context_api_token"] != true {
		t.Fatalf("status has_context_api_token = %#v, want true", cfg.StatusView()["has_context_api_token"])
	}
}

// clearGatewayAuthEnv removes ambient auth settings from validation tests.
func clearGatewayAuthEnv(t *testing.T) {
	t.Helper()
	t.Setenv("AGENTAWESOME_GATEWAY_TOKEN", "")
	t.Setenv("AGENTAWESOME_CONTEXT_API_TOKEN", "")
	t.Setenv("AGENTAWESOME_ALLOWED_ORIGIN", "")
	t.Setenv("AGENTAWESOME_ALLOW_UNAUTHENTICATED_LOOPBACK_ONLY", "true")
	t.Setenv("AGENTAWESOME_RUNTIME_POLICY_TEXT", "")
}

// TestSlackSocketModeRequiresAppToken verifies local Socket Mode config safety.
func TestSlackSocketModeRequiresAppToken(t *testing.T) {
	clearGatewayAuthEnv(t)
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
	clearGatewayAuthEnv(t)
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
	clearGatewayAuthEnv(t)
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
