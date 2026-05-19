// This file tests gateway routing, auth, proxying, and policy injection.
package gateway

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"agentgateway/internal/config"
	"agentgateway/internal/supervisor"
)

// newTestServer creates a gateway server from the shared minimal test config.
func newTestServer(t *testing.T, manager *supervisor.Manager, configure func(*config.Config)) *Server {
	t.Helper()
	server, err := NewServer(testConfig(configure), manager)
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}
	return server
}

// testConfig returns the minimal valid gateway config used by route tests.
func testConfig(configure func(*config.Config)) config.Config {
	cfg := config.Config{
		ListenAddress:  "127.0.0.1:0",
		GatewayBaseURL: "http://127.0.0.1:9/api",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
	}
	if configure != nil {
		configure(&cfg)
	}
	if len(cfg.MemoryDomains) == 0 {
		cfg.MemoryDomains = []config.MemoryDomain{
			{
				ID:        "memory",
				Label:     "Memory",
				Endpoint:  cfg.MemoryMCPURL,
				HealthURL: strings.Replace(cfg.MemoryMCPURL, "/mcp", "/healthz", 1),
			},
		}
	}
	if cfg.MemoryPolicy.Actor == "" {
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"memory"},
			WriteDomains:         []string{"memory"},
			DefaultWriteDomain:   "memory",
			AllowedSensitivities: []string{"public", "internal", "private"},
		}
	}
	if len(cfg.AgentProfiles) == 0 {
		cfg.AgentProfiles = []config.AgentProfile{
			{
				ID:                   "test",
				Label:                "Test",
				AppName:              cfg.AppName,
				UserID:               cfg.UserID,
				Actor:                cfg.MemoryPolicy.Actor,
				ReadDomains:          cfg.MemoryPolicy.ReadDomains,
				WriteDomains:         cfg.MemoryPolicy.WriteDomains,
				DefaultWriteDomain:   cfg.MemoryPolicy.DefaultWriteDomain,
				AllowedSensitivities: cfg.MemoryPolicy.AllowedSensitivities,
				AllowedFlows:         cfg.MemoryPolicy.AllowedFlows,
			},
		}
	}
	if len(cfg.MemoryServices) == 0 && cfg.MemoryService.Name != "" {
		cfg.MemoryServices = []config.MemoryDomainService{
			{
				DomainID:   "memory",
				Name:       cfg.MemoryService.Name,
				HealthURL:  cfg.MemoryService.HealthURL,
				Command:    cfg.MemoryService.Command,
				Arguments:  cfg.MemoryService.Arguments,
				WorkingDir: cfg.MemoryService.WorkingDir,
				AutoStart:  cfg.MemoryService.AutoStart,
			},
		}
	}
	return cfg
}

// TestSlackConfigRoutesThroughGateway verifies Slack uses the control plane API.
func TestSlackConfigRoutesThroughGateway(t *testing.T) {
	cfg := testConfig(func(cfg *config.Config) {
		cfg.AuthToken = "secret"
		cfg.GatewayBaseURL = "http://gateway.test/api"
		cfg.RuntimePolicyText = "Operator policy."
		cfg.Slack = config.SlackConfig{Enabled: true}
	})

	slackCfg := slackConfig(cfg)

	if slackCfg.GatewayBaseURL != "http://gateway.test/api" {
		t.Fatalf("GatewayBaseURL = %q, want gateway API", slackCfg.GatewayBaseURL)
	}
	if slackCfg.GatewayAuthToken != "secret" {
		t.Fatalf("GatewayAuthToken = %q, want gateway auth token", slackCfg.GatewayAuthToken)
	}
	if slackCfg.DefaultProfileID != "test" {
		t.Fatalf("DefaultProfileID = %q, want test", slackCfg.DefaultProfileID)
	}
	if slackCfg.RuntimePolicyText != "Operator policy." {
		t.Fatalf("RuntimePolicyText = %q, want configured operator policy", slackCfg.RuntimePolicyText)
	}
}

// TestStatusRequiresBearerToken verifies optional personal cloud auth.
func TestStatusRequiresBearerToken(t *testing.T) {
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.AuthToken = "secret"
	})

	req := httptest.NewRequest(http.MethodGet, "/api/gateway/status", nil)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", recorder.Code)
	}
}

// TestStatusReturnsSanitizedGatewayConfig verifies the status response hides secrets.
func TestStatusReturnsSanitizedGatewayConfig(t *testing.T) {
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.AuthToken = "secret"
	})

	req := httptest.NewRequest(http.MethodGet, "/api/gateway/status", nil)
	req.Header.Set("Authorization", "Bearer secret")
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	var decoded map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	text := recorder.Body.String()
	if text == "" || text == "secret" {
		t.Fatalf("status response leaked or omitted config")
	}
	if containsSecret(decoded, "secret") {
		t.Fatalf("status response leaked auth token: %s", text)
	}
}

// TestStatusIncludesReadiness verifies status exposes dependency readiness.
func TestStatusIncludesReadiness(t *testing.T) {
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: config.DefaultHarnessServiceName, HealthURL: "http://127.0.0.1:1/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.HarnessService = config.ServiceConfig{Name: config.DefaultHarnessServiceName}
	})

	req := httptest.NewRequest(http.MethodGet, "/api/gateway/status", nil)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	var decoded map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	readiness := decoded["readiness"].(map[string]any)
	if readiness["state"] != supervisor.StateStarting || readiness["ready"] != false {
		t.Fatalf("readiness = %#v, want starting and not ready", readiness)
	}
}

// TestBetaStatusReturnsSafeOperatorView verifies the beta dashboard is useful and sanitized.
func TestBetaStatusReturnsSafeOperatorView(t *testing.T) {
	snapshot := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodHead {
			t.Fatalf("snapshot method = %s, want HEAD", r.Method)
		}
		if r.URL.Path != "/internal/context-snapshot/memory" {
			t.Fatalf("snapshot path = %q, want domain-specific snapshot path", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer snapshot-secret" {
			t.Fatalf("snapshot Authorization = %q, want bearer token", got)
		}
		w.Header().Set("ETag", "snapshot-etag")
		w.Header().Set("Last-Modified", "Sun, 10 May 2026 12:00:00 GMT")
		w.Header().Set("Content-Length", "128")
		w.WriteHeader(http.StatusOK)
	}))
	defer snapshot.Close()
	harness := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer harness.Close()
	memory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok","snapshot":{"restore":{"state":"complete","completed_at":"2026-05-10T11:59:00Z"},"save":{"state":"pending"}}}`))
	}))
	defer memory.Close()
	manager := supervisor.New(0)
	manager.Ensure(context.Background(), supervisor.Service{Name: config.DefaultHarnessServiceName, HealthURL: harness.URL + "/healthz"})
	manager.Ensure(context.Background(), supervisor.Service{Name: config.DefaultMemoryServiceName, HealthURL: memory.URL + "/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.AuthToken = "gateway-secret"
		cfg.SnapshotStatusURL = snapshot.URL + "/internal/context-snapshot"
		cfg.SnapshotStatusToken = "snapshot-secret"
		cfg.ModelProviderID = "openai"
		cfg.ModelID = "gpt-mini"
		cfg.HarnessService = config.ServiceConfig{Name: config.DefaultHarnessServiceName, HealthURL: harness.URL + "/healthz"}
		cfg.MemoryService = config.ServiceConfig{Name: config.DefaultMemoryServiceName, HealthURL: memory.URL + "/healthz"}
		cfg.Slack = config.SlackConfig{
			Enabled:          true,
			SigningSecret:    "slack-secret",
			BotToken:         "xoxb-secret",
			AllowedTeamID:    "T1",
			AllowedUserID:    "U1",
			AllowedChannelID: "C1",
		}
	})

	req := httptest.NewRequest(http.MethodGet, "/api/gateway/beta-status", nil)
	req.Header.Set("Authorization", "Bearer gateway-secret")
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	text := recorder.Body.String()
	for _, secret := range []string{"gateway-secret", "snapshot-secret", "slack-secret", "xoxb-secret"} {
		if strings.Contains(text, secret) {
			t.Fatalf("beta status leaked %q in %s", secret, text)
		}
	}
	var decoded map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	snapshotStatus := decoded["snapshot"].(map[string]any)
	if snapshotStatus["last_save_at"] != "Sun, 10 May 2026 12:00:00 GMT" {
		t.Fatalf("snapshot status = %#v, want last save metadata", snapshotStatus)
	}
	if snapshotStatus["last_restore_at"] != "2026-05-10T11:59:00Z" {
		t.Fatalf("snapshot status = %#v, want memory restore timestamp", snapshotStatus)
	}
	model := decoded["model"].(map[string]any)
	if model["identifier"] != "openai:gpt-mini" {
		t.Fatalf("model = %#v, want active model identifier", model)
	}
	slack := decoded["slack"].(map[string]any)
	if slack["allowed_channel_id"] != "C1" {
		t.Fatalf("slack = %#v, want safe channel state", slack)
	}
}

// TestHealthzStaysLiveWhileDependenciesStart verifies liveness is not gated.
func TestHealthzStaysLiveWhileDependenciesStart(t *testing.T) {
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: config.DefaultHarnessServiceName, HealthURL: "http://127.0.0.1:1/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.HarnessService = config.ServiceConfig{Name: config.DefaultHarnessServiceName}
	})

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestAPIProxyWaitsForHarnessReadiness verifies chat traffic receives clear 503s.
func TestAPIProxyWaitsForHarnessReadiness(t *testing.T) {
	upstreamCalled := false
	harness := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer harness.Close()
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: config.DefaultHarnessServiceName, HealthURL: harness.URL + "/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.HarnessBaseURL = harness.URL + "/api"
		cfg.HarnessService = config.ServiceConfig{Name: config.DefaultHarnessServiceName}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", strings.NewReader(`{}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("harness upstream was called before readiness")
	}
	if !strings.Contains(recorder.Body.String(), "dependency not ready") {
		t.Fatalf("body = %q, want dependency readiness error", recorder.Body.String())
	}
}

// TestWorkflowProxyRoutesThroughGateway verifies user-channel workflow calls stay gateway-routed.
func TestWorkflowProxyRoutesThroughGateway(t *testing.T) {
	var upstreamPaths []string
	workflowd := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamPaths = append(upstreamPaths, r.URL.Path)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"items":[]}`))
	}))
	defer workflowd.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.WorkflowBaseURL = workflowd.URL + "/api/workflows"
	})

	paths := []string{"/api/workflows/inbox", "/api/workflows/drafts", "/api/workflows/action-types"}
	for _, path := range paths {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		recorder := httptest.NewRecorder()
		server.routes().ServeHTTP(recorder, req)
		if recorder.Code != http.StatusOK {
			t.Fatalf("%s status = %d, want 200; body = %q", path, recorder.Code, recorder.Body.String())
		}
	}
	for index, path := range paths {
		if upstreamPaths[index] != path {
			t.Fatalf("workflow upstream path[%d] = %q, want %q", index, upstreamPaths[index], path)
		}
	}
}

// TestAPIProxyWaitsForProfileMemoryReadiness verifies cold agent turns wait for memory.
func TestAPIProxyWaitsForProfileMemoryReadiness(t *testing.T) {
	upstreamCalled := false
	harness := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer harness.Close()
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: "memory-memory", HealthURL: "http://127.0.0.1:2/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.HarnessBaseURL = harness.URL + "/api"
		cfg.MemoryServices = []config.MemoryDomainService{
			{
				DomainID:  "memory",
				Name:      "memory-memory",
				HealthURL: "http://127.0.0.1:2/healthz",
			},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", strings.NewReader(`{}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("harness upstream was called before profile memory readiness")
	}
	if !strings.Contains(recorder.Body.String(), "memory domain dependency not ready") {
		t.Fatalf("body = %q, want memory readiness error", recorder.Body.String())
	}
}

// TestContextAPIProxyWaitsForHarnessReadiness verifies context traffic receives clear 503s.
func TestContextAPIProxyWaitsForHarnessReadiness(t *testing.T) {
	upstreamCalled := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: config.DefaultHarnessServiceName, HealthURL: contextAPI.URL + "/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.ContextAPIToken = "context-token"
		cfg.HarnessService = config.ServiceConfig{Name: config.DefaultHarnessServiceName}
	})

	req := httptest.NewRequest(http.MethodGet, "/api/context/tools/list", nil)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("context upstream was called before readiness")
	}
	if !strings.Contains(recorder.Body.String(), "dependency not ready") {
		t.Fatalf("body = %q, want dependency readiness error", recorder.Body.String())
	}
}

// TestMCPProxyWaitsForMemoryReadiness verifies memory traffic receives clear 503s.
func TestMCPProxyWaitsForMemoryReadiness(t *testing.T) {
	upstreamCalled := false
	memory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer memory.Close()
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: config.DefaultMemoryServiceName, HealthURL: memory.URL + "/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.MemoryMCPURL = memory.URL + "/mcp"
		cfg.MemoryService = config.ServiceConfig{Name: config.DefaultMemoryServiceName}
	})

	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0"}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("memory upstream was called before readiness")
	}
}

// TestMCPProxyWaitsForSelectedDomainReadiness verifies each domain has separate readiness.
func TestMCPProxyWaitsForSelectedDomainReadiness(t *testing.T) {
	projectCalled := false
	project := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		projectCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer project.Close()
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: "memory-project", HealthURL: project.URL + "/healthz"})
	server := newTestServer(t, manager, func(cfg *config.Config) {
		cfg.MemoryDomains = []config.MemoryDomain{
			{ID: "memory", Label: "Memory", Endpoint: "http://127.0.0.1:8090/mcp", HealthURL: "http://127.0.0.1:8090/healthz"},
			{ID: "project", Label: "Project", Endpoint: project.URL + "/mcp", HealthURL: project.URL + "/healthz"},
		}
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"memory", "project"},
			WriteDomains:         []string{"memory"},
			DefaultWriteDomain:   "memory",
			AllowedSensitivities: []string{"public"},
		}
		cfg.MemoryServices = []config.MemoryDomainService{
			{DomainID: "memory", Name: "memory", HealthURL: "http://127.0.0.1:8090/healthz"},
			{DomainID: "project", Name: "memory-project", HealthURL: project.URL + "/healthz"},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/mcp/project", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_memory","arguments":{"query":"hello"}}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", recorder.Code)
	}
	if projectCalled {
		t.Fatalf("project memory upstream was called before readiness")
	}
	if !strings.Contains(recorder.Body.String(), `"domain_id":"project"`) {
		t.Fatalf("body = %q, want selected domain readiness detail", recorder.Body.String())
	}
}

// TestMemoryMCPProxyForwardsThroughGateway verifies UI memory traffic uses control plane.
func TestMemoryMCPProxyForwardsThroughGateway(t *testing.T) {
	memory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/mcp" {
			t.Fatalf("memory path = %q, want /mcp", r.URL.Path)
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if string(body) != `{"jsonrpc":"2.0"}` {
			t.Fatalf("body = %q, want MCP payload", string(body))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer memory.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.MemoryMCPURL = memory.URL + "/mcp"
	})

	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0"}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	if !strings.Contains(recorder.Body.String(), `"ok":true`) {
		t.Fatalf("body = %q, want proxied memory response", recorder.Body.String())
	}
}

// TestContextAPIProxyForwardsThroughGateway verifies frontends use harness context APIs.
func TestContextAPIProxyForwardsThroughGateway(t *testing.T) {
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/context/tools/list" {
			t.Fatalf("context path = %q, want /api/context/tools/list", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"tools":["search_memory"]}`))
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
	})

	req := httptest.NewRequest(http.MethodGet, "/api/context/tools/list", nil)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	if !strings.Contains(recorder.Body.String(), `"search_memory"`) {
		t.Fatalf("body = %q, want proxied context tools", recorder.Body.String())
	}
}

// TestContextAPIProxyUsesConfiguredUpstreamToken verifies direct API auth is scoped.
func TestContextAPIProxyUsesConfiguredUpstreamToken(t *testing.T) {
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer context-secret" {
			t.Fatalf("Authorization = %q, want context API token", got)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.ContextAPIToken = "context-secret"
		cfg.AuthToken = "gateway-secret"
	})

	req := httptest.NewRequest(http.MethodGet, "/api/context/tools/list", nil)
	req.Header.Set("Authorization", "Bearer gateway-secret")
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestProfileHeaderRoutesHarnessAndContext verifies profile-owned harness routing.
func TestProfileHeaderRoutesHarnessAndContext(t *testing.T) {
	dougAPI := false
	doug := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		dougAPI = true
		w.WriteHeader(http.StatusOK)
	}))
	defer doug.Close()
	familyAPI := false
	family := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		familyAPI = true
		w.WriteHeader(http.StatusOK)
	}))
	defer family.Close()
	familyContext := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		familyContext = true
		if r.Header.Get(profileHeader) != "family" {
			t.Fatalf("profile header = %q, want family", r.Header.Get(profileHeader))
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.HarnessBaseURL = doug.URL + "/api"
		cfg.ContextBaseURL = doug.URL + "/api/context"
		cfg.AgentProfiles = []config.AgentProfile{
			testProfile("doug", "doug", "memory"),
			testProfile("family", "family", "memory"),
		}
		cfg.AgentProfiles[1].HarnessBaseURL = family.URL + "/api"
		cfg.AgentProfiles[1].ContextBaseURL = contextAPI.URL + "/api/context"
	})

	apiReq := httptest.NewRequest(http.MethodPost, "/api/profile-check", strings.NewReader(`{}`))
	apiReq.Header.Set(profileHeader, "family")
	apiRecorder := httptest.NewRecorder()
	server.routes().ServeHTTP(apiRecorder, apiReq)

	if apiRecorder.Code != http.StatusOK {
		t.Fatalf("api status = %d, want 200", apiRecorder.Code)
	}
	if !familyAPI || dougAPI {
		t.Fatalf("profile routing family=%v doug=%v, want family only", familyAPI, dougAPI)
	}

	contextReq := httptest.NewRequest(http.MethodGet, "/api/context/tools/list", nil)
	contextReq.Header.Set(profileHeader, "family")
	contextRecorder := httptest.NewRecorder()
	server.routes().ServeHTTP(contextRecorder, contextReq)

	if contextRecorder.Code != http.StatusOK {
		t.Fatalf("context status = %d, want 200", contextRecorder.Code)
	}
	if !familyContext {
		t.Fatalf("family context upstream was not called")
	}
}

// TestProfileHeaderScopesMemoryGrants verifies gateway memory policy is per profile.
func TestProfileHeaderScopesMemoryGrants(t *testing.T) {
	upstreamCalled := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamCalled = true
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode context body: %v", err)
		}
		if decoded["domain_id"] != "family" {
			t.Fatalf("domain_id = %#v, want family", decoded["domain_id"])
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.MemoryDomains = memoryDomains("doug", "family")
		cfg.AgentProfiles = []config.AgentProfile{
			testProfile("doug", "doug", "doug"),
			testProfile("family", "family", "family"),
		}
	})

	blocked := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"search_memory","domain_id":"family","arguments":{"query":"hello"}}`))
	blocked.Header.Set(profileHeader, "doug")
	blockedRecorder := httptest.NewRecorder()
	server.routes().ServeHTTP(blockedRecorder, blocked)

	if blockedRecorder.Code != http.StatusForbidden {
		t.Fatalf("blocked status = %d, want 403", blockedRecorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("context upstream was called for blocked profile")
	}

	allowed := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"search_memory","domain_id":"family","arguments":{"query":"hello"}}`))
	allowed.Header.Set(profileHeader, "family")
	allowedRecorder := httptest.NewRecorder()
	server.routes().ServeHTTP(allowedRecorder, allowed)

	if allowedRecorder.Code != http.StatusOK {
		t.Fatalf("allowed status = %d, want 200; body = %q", allowedRecorder.Code, allowedRecorder.Body.String())
	}
	if !upstreamCalled {
		t.Fatalf("context upstream was not called for allowed profile")
	}
}

// TestProfileHeaderRequiredWithMultipleProfiles avoids ambiguous cloud requests.
func TestProfileHeaderRequiredWithMultipleProfiles(t *testing.T) {
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.AgentProfiles = []config.AgentProfile{
			testProfile("doug", "doug", "memory"),
			testProfile("family", "family", "memory"),
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/profile-check", strings.NewReader(`{}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", recorder.Code)
	}
}

// TestContextAPIInjectsSingleAllowedDomain verifies the gateway owns domain defaults.
func TestContextAPIInjectsSingleAllowedDomain(t *testing.T) {
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode context body: %v", err)
		}
		if decoded["domain_id"] != "memory" {
			t.Fatalf("domain_id = %#v, want injected memory domain", decoded["domain_id"])
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
	})

	req := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"search_memory","arguments":{"query":"hello"}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestContextAPIBlocksUnauthorizedReadDomain verifies UI calls cannot bypass grants.
func TestContextAPIBlocksUnauthorizedReadDomain(t *testing.T) {
	upstreamCalled := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.MemoryDomains = memoryDomains("memory", "project")
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"memory"},
			WriteDomains:         []string{"memory"},
			DefaultWriteDomain:   "memory",
			AllowedSensitivities: []string{"public"},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"search_memory","domain_id":"project","arguments":{"query":"hello"}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("context upstream was called for unauthorized domain")
	}
}

// TestContextAPIRequiresDomainForMultipleReadGrants avoids ambiguous fanout writes.
func TestContextAPIRequiresDomainForMultipleReadGrants(t *testing.T) {
	upstreamCalled := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.MemoryDomains = memoryDomains("memory", "project")
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"memory", "project"},
			WriteDomains:         []string{"memory"},
			DefaultWriteDomain:   "memory",
			AllowedSensitivities: []string{"public"},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"search_memory","arguments":{"query":"hello"}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("context upstream was called without required domain")
	}
}

// TestContextAPIBlocksWritesOutsideWriteDomains verifies task writes are domain scoped.
func TestContextAPIBlocksWritesOutsideWriteDomains(t *testing.T) {
	upstreamCalled := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.MemoryDomains = memoryDomains("memory", "project")
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"memory", "project"},
			WriteDomains:         []string{"memory"},
			DefaultWriteDomain:   "memory",
			AllowedSensitivities: []string{"public"},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"update_task","domain_id":"project","arguments":{"id":"TASK-1"}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("context upstream was called for unauthorized write domain")
	}
}

// TestContextAPIRoutesExportToHarness verifies export policy stays harness-owned.
func TestContextAPIRoutesExportToHarness(t *testing.T) {
	upstreamCalled := false
	contextAPI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamCalled = true
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode context body: %v", err)
		}
		if decoded["domain_id"] != nil {
			t.Fatalf("domain_id = %#v, want no gateway-selected domain", decoded["domain_id"])
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer contextAPI.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.ContextBaseURL = contextAPI.URL + "/api/context"
		cfg.MemoryDomains = memoryDomains("family", "work")
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"family", "work"},
			WriteDomains:         []string{"work"},
			DefaultWriteDomain:   "work",
			AllowedSensitivities: []string{"public"},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/api/context/tools/call", strings.NewReader(`{"name":"export_memory_copy","arguments":{"source_domain":"family","target_domain":"work","source_memory_id":"memory-1","content":"reviewed"}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body = %q", recorder.Code, recorder.Body.String())
	}
	if !upstreamCalled {
		t.Fatalf("context upstream was not called for export")
	}
}

// TestMCPRoutesDomainPathToConfiguredMemoryServer verifies model-visible MCP can be domain-scoped.
func TestMCPRoutesDomainPathToConfiguredMemoryServer(t *testing.T) {
	memoryCalled := false
	memory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		memoryCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer memory.Close()
	projectCalled := false
	project := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		projectCalled = true
		if r.URL.Path != "/mcp" {
			t.Fatalf("project memory path = %q, want /mcp", r.URL.Path)
		}
		if r.URL.Query().Get("domain_id") != "" {
			t.Fatalf("domain_id query leaked to upstream: %q", r.URL.RawQuery)
		}
		if r.Header.Get(memoryDomainHeader) != "" {
			t.Fatalf("gateway memory-domain header leaked upstream")
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer project.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.MemoryMCPURL = memory.URL + "/mcp"
		cfg.MemoryDomains = []config.MemoryDomain{
			{ID: "memory", Label: "Memory", Endpoint: memory.URL + "/mcp"},
			{ID: "project", Label: "Project", Endpoint: project.URL + "/mcp"},
		}
		cfg.MemoryPolicy = config.MemoryPolicy{
			Actor:                "agent:test",
			ReadDomains:          []string{"memory", "project"},
			WriteDomains:         []string{"project"},
			DefaultWriteDomain:   "project",
			AllowedSensitivities: []string{"public"},
		}
	})

	req := httptest.NewRequest(http.MethodPost, "/mcp/project?domain_id=project", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_memory","arguments":{"query":"hello"}}}`))
	req.Header.Set(memoryDomainHeader, "project")
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body = %q", recorder.Code, recorder.Body.String())
	}
	if !projectCalled {
		t.Fatalf("project memory upstream was not called")
	}
	if memoryCalled {
		t.Fatalf("default memory upstream was called")
	}
}

// TestMCPBlocksModelSuppliedDomainOverrides keeps model output below policy.
func TestMCPBlocksModelSuppliedDomainOverrides(t *testing.T) {
	upstreamCalled := false
	memory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer memory.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.MemoryMCPURL = memory.URL + "/mcp"
	})

	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_memory","arguments":{"query":"hello","domain_id":"project"}}}`))
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("memory upstream was called for model domain override")
	}
}

// TestRunSSEProxyDoesNotInjectRuntimePolicyByDefault verifies clean ADK runs.
func TestRunSSEProxyDoesNotInjectRuntimePolicyByDefault(t *testing.T) {
	harness := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/run_sse" {
			t.Fatalf("harness path = %q, want /api/run_sse", r.URL.Path)
		}
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode harness body: %v", err)
		}
		message := decoded["newMessage"].(map[string]any)
		parts := message["parts"].([]any)
		text := parts[0].(map[string]any)["text"].(string)
		if text != "hello" {
			t.Fatalf("text = %q, want gateway to leave user text unchanged", text)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer harness.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.HarnessBaseURL = harness.URL + "/api"
	})

	body := strings.NewReader(`{"sessionId":"s1","newMessage":{"parts":[{"text":"hello"}]}}`)
	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", body)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestRunSSEProxyInjectsConfiguredRuntimePolicy verifies gateway policy is opt-in.
func TestRunSSEProxyInjectsConfiguredRuntimePolicy(t *testing.T) {
	harness := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode harness body: %v", err)
		}
		message := decoded["newMessage"].(map[string]any)
		parts := message["parts"].([]any)
		text := parts[0].(map[string]any)["text"].(string)
		if !strings.HasPrefix(text, "[[AGENT_AWESOME_RUNTIME_POLICY:") || !strings.Contains(text, "Configured gateway policy.") {
			t.Fatalf("text = %q, want configured runtime policy prefix", text)
		}
		if strings.Contains(text, "idempotency_key") {
			t.Fatalf("text = %q, want idempotency handled outside model text", text)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer harness.Close()
	server := newTestServer(t, supervisor.New(0), func(cfg *config.Config) {
		cfg.HarnessBaseURL = harness.URL + "/api"
		cfg.RuntimePolicyText = "Configured gateway policy."
		cfg.RequestTimeout = 0
		cfg.ServiceStartTimeout = 0
	})

	body := strings.NewReader(`{"sessionId":"s1","newMessage":{"parts":[{"text":"hello"}]}}`)
	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", body)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// memoryDomains builds routable test memory domain configs.
func memoryDomains(ids ...string) []config.MemoryDomain {
	domains := make([]config.MemoryDomain, 0, len(ids))
	for index, id := range ids {
		domains = append(domains, config.MemoryDomain{
			ID:        id,
			Label:     id,
			Endpoint:  "http://127.0.0.1:" + strconv.Itoa(8090+index) + "/mcp",
			HealthURL: "http://127.0.0.1:" + strconv.Itoa(8090+index) + "/healthz",
		})
	}
	return domains
}

// testProfile builds a minimal profile for gateway route tests.
func testProfile(id string, userID string, domainID string) config.AgentProfile {
	return config.AgentProfile{
		ID:                   id,
		Label:                id,
		AppName:              "app",
		UserID:               userID,
		Actor:                "agent:" + id,
		ReadDomains:          []string{domainID},
		WriteDomains:         []string{domainID},
		DefaultWriteDomain:   domainID,
		AllowedSensitivities: []string{"public", "internal", "private"},
	}
}

// containsSecret recursively checks a decoded JSON value for a secret.
func containsSecret(value any, secret string) bool {
	switch typed := value.(type) {
	case map[string]any:
		for _, item := range typed {
			if containsSecret(item, secret) {
				return true
			}
		}
	case []any:
		for _, item := range typed {
			if containsSecret(item, secret) {
				return true
			}
		}
	case string:
		return typed == secret
	}
	return false
}
