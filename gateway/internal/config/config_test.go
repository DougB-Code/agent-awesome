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
	if cfg.RunbookBaseURL != "http://127.0.0.1:8092/api/runbooks" {
		t.Fatalf("runbook base URL = %q", cfg.RunbookBaseURL)
	}
	if cfg.RunbookService.HealthURL != "http://127.0.0.1:8092/healthz" {
		t.Fatalf("runbook health = %q", cfg.RunbookService.HealthURL)
	}
	if len(cfg.MemoryDomains) != 1 || cfg.MemoryDomains[0].ID != "memory" || cfg.MemoryDomains[0].Endpoint != "http://127.0.0.1:8090/mcp" {
		t.Fatalf("memory domains = %#v, want default memory endpoint", cfg.MemoryDomains)
	}
	if cfg.MemoryPolicy.Actor != "agent:pilot" || cfg.MemoryPolicy.DefaultWriteDomain != "memory" {
		t.Fatalf("memory policy = %#v, want default pilot memory grant", cfg.MemoryPolicy)
	}
	if len(cfg.MemoryServices) != 1 || cfg.MemoryServices[0].DomainID != "memory" || cfg.MemoryServices[0].HealthURL != "http://127.0.0.1:8090/healthz" {
		t.Fatalf("memory services = %#v, want default memory service", cfg.MemoryServices)
	}
	if cfg.GatewayBaseURL != "http://127.0.0.1:8070/api" {
		t.Fatalf("gateway base URL = %q", cfg.GatewayBaseURL)
	}
}

// TestFromFlagsConfiguresHarnessEmbeddedServices verifies gateway launcher mode.
func TestFromFlagsConfiguresHarnessEmbeddedServices(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--harness-embedded-services",
		"--harness-auto-start",
		"--harness-command", "/usr/local/bin/agent-awesome",
		"--harness-arg", "run",
		"--harness-arg", "--model",
		"--harness-arg", "model.yaml",
		"--harness-arg", "--",
		"--harness-arg", "web",
		"--harness-arg", "--port",
		"--harness-arg", "8080",
		"--context-base-url", "http://127.0.0.1:8081/api/context",
		"--runbook-base-url", "http://127.0.0.1:8092/api/runbooks",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	wantOrder := []string{
		"run",
		"--model",
		"model.yaml",
		"--context-api-addr",
		"127.0.0.1:8081",
		"--runbook-api-addr",
		"127.0.0.1:8092",
		"--",
		"web",
		"--port",
		"8080",
	}
	if !containsAllInOrder(cfg.HarnessService.Arguments, wantOrder) {
		t.Fatalf("harness args = %#v, want ordered values %#v", cfg.HarnessService.Arguments, wantOrder)
	}
	if !cfg.HarnessEmbeddedServices {
		t.Fatalf("HarnessEmbeddedServices = false, want true")
	}
	if cfg.StatusView()["harness_embedded_services"] != true {
		t.Fatalf("status view omitted embedded services: %#v", cfg.StatusView())
	}
}

// TestFromFlagsRejectsDuplicateControlServiceLaunchers avoids competing daemons.
func TestFromFlagsRejectsDuplicateControlServiceLaunchers(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--harness-embedded-services",
		"--runbook-auto-start",
		"--runbook-command",
		"/usr/local/bin/runbook-service",
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want duplicate launcher validation")
	}
}

// TestFromFlagsRejectsRemoteHarnessEmbeddedServiceURLs keeps inner services local.
func TestFromFlagsRejectsRemoteHarnessEmbeddedServiceURLs(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--harness-embedded-services",
		"--harness-auto-start",
		"--harness-command", "/usr/local/bin/agent-awesome",
		"--harness-arg", "run",
		"--runbook-base-url", "https://agent-awesome.com/api/runbooks",
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want loopback validation")
	}
}

// TestFromFlagsParsesGatewayLogFile verifies cloud launchers can persist logs.
func TestFromFlagsParsesGatewayLogFile(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--log-file", "/tmp/agent-gateway.log"})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.LogFile != "/tmp/agent-gateway.log" {
		t.Fatalf("LogFile = %q, want configured path", cfg.LogFile)
	}
	if cfg.StatusView()["has_log_file"] != true {
		t.Fatalf("has_log_file = %#v, want true", cfg.StatusView()["has_log_file"])
	}
}

// TestFromFlagsParsesMemoryTopologyJSON verifies gateway domain policy is explicit config.
func TestFromFlagsParsesMemoryTopologyJSON(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--memory-domains-json", `[
			{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"},
			{"id":"project","label":"Project","endpoint":"http://127.0.0.1:8091/mcp","health_url":"http://127.0.0.1:8091/healthz"}
		]`,
		"--memory-policy-json", `{
			"actor":"agent:project",
			"read_domains":["memory","project"],
			"write_domains":["project"],
			"default_write_domain":"project",
			"allowed_sensitivities":["public","internal"],
			"allowed_flows":[{"from":"memory","to":"project"}]
		}`,
		"--memory-services-json", `[
			{"domain_id":"memory","health_url":"http://127.0.0.1:8090/healthz","auto_start":false},
			{"domain_id":"project","health_url":"http://127.0.0.1:8091/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8091"],"auto_start":true}
		]`,
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if len(cfg.MemoryDomains) != 2 {
		t.Fatalf("memory domains = %#v, want two domains", cfg.MemoryDomains)
	}
	if cfg.MemoryPolicy.Actor != "agent:project" {
		t.Fatalf("memory policy actor = %q, want project actor", cfg.MemoryPolicy.Actor)
	}
	if cfg.MemoryPolicy.DefaultWriteDomain != "project" {
		t.Fatalf("default write domain = %q, want project", cfg.MemoryPolicy.DefaultWriteDomain)
	}
	if len(cfg.MemoryServices) != 2 || cfg.MemoryServices[1].Name != "memory-project" {
		t.Fatalf("memory services = %#v, want normalized services", cfg.MemoryServices)
	}
	if cfg.StatusView()["memory_policy"] == nil || cfg.StatusView()["memory_domains"] == nil {
		t.Fatalf("status view omitted memory topology: %#v", cfg.StatusView())
	}
}

// TestFromFlagsParsesAgentProfilesJSON verifies request-scoped profile policy.
func TestFromFlagsParsesAgentProfilesJSON(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--memory-domains-json", `[
			{"id":"doug","label":"Doug","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"},
			{"id":"family","label":"Family","endpoint":"http://127.0.0.1:8091/mcp","health_url":"http://127.0.0.1:8091/healthz"}
		]`,
		"--agent-profiles-json", `[
			{"id":"doug","label":"Doug","app_name":"Agent Awesome","user_id":"doug","harness_base_url":"http://127.0.0.1:8080/api","context_base_url":"http://127.0.0.1:8081/api/context","actor":"agent:doug","read_domains":["doug"],"write_domains":["doug"],"default_write_domain":"doug","allowed_sensitivities":["public","private"]},
			{"id":"family","label":"Family","app_name":"Agent Awesome","user_id":"family","harness_base_url":"http://127.0.0.1:8082/api","context_base_url":"http://127.0.0.1:8083/api/context","actor":"agent:family","read_domains":["family"],"write_domains":["family"],"default_write_domain":"family","allowed_sensitivities":["public","private"]}
		]`,
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if len(cfg.AgentProfiles) != 2 {
		t.Fatalf("AgentProfiles = %#v, want two profiles", cfg.AgentProfiles)
	}
	if cfg.MemoryPolicy.Actor != "agent:doug" || cfg.MemoryPolicy.DefaultWriteDomain != "doug" {
		t.Fatalf("MemoryPolicy = %#v, want first profile policy", cfg.MemoryPolicy)
	}
	family, ok := cfg.ProfileByID("family")
	if !ok {
		t.Fatalf("ProfileByID(family) not found")
	}
	if family.ContextBaseURL != "http://127.0.0.1:8083/api/context" {
		t.Fatalf("family context URL = %q", family.ContextBaseURL)
	}
	if cfg.StatusView()["agent_profiles"] == nil {
		t.Fatalf("status view omitted agent profiles: %#v", cfg.StatusView())
	}
}

// TestFromFlagsRejectsAgentProfileUnknownDomain verifies profiles cannot invent domains.
func TestFromFlagsRejectsAgentProfileUnknownDomain(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--memory-domains-json", `[{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp"}]`,
		"--agent-profiles-json", `[{"id":"bad","label":"Bad","app_name":"Agent Awesome","user_id":"bad","actor":"agent:bad","read_domains":["other"],"write_domains":["memory"],"default_write_domain":"memory","allowed_sensitivities":["public"]}]`,
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want unknown profile domain validation error")
	}
}

// TestFromFlagsRejectsMultipleDomainsWithSingleServiceFlags avoids accidental shared services.
func TestFromFlagsRejectsMultipleDomainsWithSingleServiceFlags(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--memory-domains-json", `[{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp"},{"id":"project","label":"Project","endpoint":"http://127.0.0.1:8091/mcp"}]`,
		"--memory-policy-json", `{
			"actor":"agent:test",
			"read_domains":["memory","project"],
			"write_domains":["memory"],
			"default_write_domain":"memory",
			"allowed_sensitivities":["public"]
		}`,
		"--memory-auto-start",
		"--memory-command", "/usr/local/bin/memoryd",
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want memory-services-json validation error")
	}
}

// TestFromFlagsRejectsUnsafeMemoryDomainIDs verifies route ids stay constrained.
func TestFromFlagsRejectsUnsafeMemoryDomainIDs(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--memory-domains-json", `[{"id":"bad/domain","label":"Bad","endpoint":"http://127.0.0.1:8090/mcp"}]`,
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want unsafe id validation error")
	}
}

// TestFromFlagsRejectsUnknownMemoryGrants verifies active profiles cannot invent domains.
func TestFromFlagsRejectsUnknownMemoryGrants(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--memory-domains-json", `[{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp"}]`,
		"--memory-policy-json", `{
			"actor":"agent:test",
			"read_domains":["other"],
			"write_domains":["memory"],
			"default_write_domain":"memory",
			"allowed_sensitivities":["public"]
		}`,
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want unknown grant validation error")
	}
}

// TestFromFlagsRejectsUnwritableDefaultDomain verifies writes stay grant-scoped.
func TestFromFlagsRejectsUnwritableDefaultDomain(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--memory-domains-json", `[{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp"},{"id":"project","label":"Project","endpoint":"http://127.0.0.1:8091/mcp"}]`,
		"--memory-policy-json", `{
			"actor":"agent:test",
			"read_domains":["memory","project"],
			"write_domains":["project"],
			"default_write_domain":"memory",
			"allowed_sensitivities":["public"]
		}`,
	})
	if err == nil {
		t.Fatalf("FromFlags() error = nil, want default write validation error")
	}
}

// TestFromFlagsDerivesLoopbackGatewayBaseURL verifies channel adapters self-call gateway.
func TestFromFlagsDerivesLoopbackGatewayBaseURL(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--addr", "0.0.0.0:8070", "--auth-token", "secret"})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.GatewayBaseURL != "http://127.0.0.1:8070/api" {
		t.Fatalf("gateway base URL = %q, want loopback URL", cfg.GatewayBaseURL)
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

// TestCheckConfigFlagParses verifies preflight mode is a config-only concern.
func TestCheckConfigFlagParses(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{"--check-config"})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if !cfg.CheckConfig {
		t.Fatalf("CheckConfig = false, want true")
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

// containsAllInOrder reports whether every expected value appears in order.
func containsAllInOrder(values []string, expected []string) bool {
	index := 0
	for _, value := range values {
		if index < len(expected) && value == expected[index] {
			index++
		}
	}
	return index == len(expected)
}

// flagValue returns the next argument after flag.
func flagValue(values []string, flag string) string {
	for index, value := range values {
		if value == flag && index+1 < len(values) {
			return values[index+1]
		}
	}
	return ""
}

// clearGatewayAuthEnv removes ambient auth settings from validation tests.
func clearGatewayAuthEnv(t *testing.T) {
	t.Helper()
	t.Setenv("AGENTAWESOME_GATEWAY_TOKEN", "")
	t.Setenv("AGENTAWESOME_CONTEXT_API_TOKEN", "")
	t.Setenv("AGENTAWESOME_MEMORY_DOMAINS_JSON", "")
	t.Setenv("AGENTAWESOME_MEMORY_POLICY_JSON", "")
	t.Setenv("AGENTAWESOME_MEMORY_SERVICES_JSON", "")
	t.Setenv("AGENTAWESOME_HARNESS_HEALTH_URL", "")
	t.Setenv("AGENTAWESOME_HARNESS_COMMAND", "")
	t.Setenv("AGENTAWESOME_HARNESS_ARGS", "")
	t.Setenv("AGENTAWESOME_HARNESS_WORKDIR", "")
	t.Setenv("AGENTAWESOME_HARNESS_AUTO_START", "")
	t.Setenv("AGENTAWESOME_RUNBOOK_BASE_URL", "")
	t.Setenv("AGENTAWESOME_RUNBOOK_HEALTH_URL", "")
	t.Setenv("AGENTAWESOME_RUNBOOK_COMMAND", "")
	t.Setenv("AGENTAWESOME_RUNBOOK_ARGS", "")
	t.Setenv("AGENTAWESOME_RUNBOOK_WORKDIR", "")
	t.Setenv("AGENTAWESOME_RUNBOOK_AUTO_START", "")
	t.Setenv("AGENTAWESOME_HARNESS_EMBEDDED_SERVICES", "")
	t.Setenv("AGENTAWESOME_AGENT_PROFILES_JSON", "")
	t.Setenv("AGENTAWESOME_ALLOWED_ORIGIN", "")
	t.Setenv("AGENTAWESOME_ALLOW_UNAUTHENTICATED_LOOPBACK_ONLY", "true")
	t.Setenv("AGENTAWESOME_RUNTIME_POLICY_TEXT", "")
	t.Setenv("AGENTAWESOME_GATEWAY_LOG_FILE", "")
	t.Setenv("SLACK_ENABLED", "")
	t.Setenv("SLACK_SOCKET_MODE", "")
	t.Setenv("SLACK_SIGNING_SECRET", "")
	t.Setenv("SLACK_APP_TOKEN", "")
	t.Setenv("SLACK_BOT_TOKEN", "")
	t.Setenv("SLACK_ALLOWED_TEAM_ID", "")
	t.Setenv("SLACK_ALLOWED_USER_ID", "")
	t.Setenv("SLACK_ALLOWED_CHANNEL_ID", "")
}

// TestSlackSocketModeRequiresAppToken verifies local Socket Mode config safety.
func TestSlackSocketModeRequiresAppToken(t *testing.T) {
	clearGatewayAuthEnv(t)
	_, err := FromFlags([]string{
		"--slack-enabled",
		"--slack-socket-mode",
		"--slack-bot-token", "xoxb-test",
		"--slack-allowed-team-id", "T1",
		"--slack-allowed-user-id", "U1",
		"--slack-allowed-channel-id", "C1",
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
		"--slack-allowed-team-id", "T1",
		"--slack-allowed-user-id", "U1",
		"--slack-allowed-channel-id", "C1",
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
	t.Setenv("SLACK_ALLOWED_TEAM_ID", "T1")
	t.Setenv("SLACK_ALLOWED_USER_ID", "U1")
	t.Setenv("SLACK_ALLOWED_CHANNEL_ID", "C1")

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

// TestSlackAllowsWorkspaceScopedEvents verifies Slack can trust signed workspace installs.
func TestSlackAllowsWorkspaceScopedEvents(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--slack-enabled",
		"--slack-signing-secret", "secret",
		"--slack-bot-token", "xoxb-test",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if !cfg.Slack.Enabled {
		t.Fatalf("Slack enabled = false, want true")
	}

	cfg, err = FromFlags([]string{
		"--slack-enabled",
		"--slack-signing-secret", "secret",
		"--slack-bot-token", "xoxb-test",
		"--slack-allowed-team-id", "T1",
		"--slack-allowed-user-id", "U1",
		"--slack-allowed-channel-id", "C1",
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if cfg.Slack.AllowedTeamID != "T1" || cfg.Slack.AllowedUserID != "U1" || cfg.Slack.AllowedChannelID != "C1" {
		t.Fatalf("Slack allow-lists = %#v", cfg.Slack)
	}
}

// TestSlackAllowsProfileBindings verifies Slack can scope ingress by profile.
func TestSlackAllowsProfileBindings(t *testing.T) {
	clearGatewayAuthEnv(t)
	cfg, err := FromFlags([]string{
		"--slack-enabled",
		"--slack-signing-secret", "secret",
		"--slack-bot-token", "xoxb-test",
		"--agent-profiles-json", `[{
			"id":"family",
			"label":"Family",
			"app_name":"Agent Awesome",
			"user_id":"family",
			"actor":"agent:family",
			"read_domains":["memory"],
			"write_domains":["memory"],
			"default_write_domain":"memory",
			"allowed_sensitivities":["public"],
			"slack_bindings":[{"team_id":"T1","channel_id":"C1","allowed_user_ids":["U1","U2"]}]
		}]`,
	})
	if err != nil {
		t.Fatalf("FromFlags() error = %v", err)
	}
	if got := cfg.AgentProfiles[0].SlackBindings[0].AllowedUserIDs; len(got) != 2 {
		t.Fatalf("Slack allowed users = %#v, want two users", got)
	}
}
