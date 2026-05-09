// This file tests gateway routing, auth, proxying, and policy injection.
package gateway

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"agentgateway/internal/config"
	"agentgateway/internal/policy"
	"agentgateway/internal/supervisor"
)

// TestStatusRequiresBearerToken verifies optional personal cloud auth.
func TestStatusRequiresBearerToken(t *testing.T) {
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
		AuthToken:      "secret",
	}, supervisor.New(0))
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/gateway/status", nil)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", recorder.Code)
	}
}

// TestStatusReturnsSanitizedGatewayConfig verifies the status response hides secrets.
func TestStatusReturnsSanitizedGatewayConfig(t *testing.T) {
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
		AuthToken:      "secret",
	}, supervisor.New(0))
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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
	manager.Expect(supervisor.Service{Name: "harness", HealthURL: "http://127.0.0.1:1/healthz"})
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
		HarnessService: config.ServiceConfig{Name: "harness"},
	}, manager)
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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
	if readiness["state"] != "starting" || readiness["ready"] != false {
		t.Fatalf("readiness = %#v, want starting and not ready", readiness)
	}
}

// TestHealthzStaysLiveWhileDependenciesStart verifies liveness is not gated.
func TestHealthzStaysLiveWhileDependenciesStart(t *testing.T) {
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: "harness", HealthURL: "http://127.0.0.1:1/healthz"})
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
		HarnessService: config.ServiceConfig{Name: "harness"},
	}, manager)
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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
	manager.Expect(supervisor.Service{Name: "harness", HealthURL: harness.URL + "/healthz"})
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: harness.URL + "/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
		HarnessService: config.ServiceConfig{Name: "harness"},
	}, manager)
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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

// TestMCPProxyWaitsForMemoryReadiness verifies memory traffic receives clear 503s.
func TestMCPProxyWaitsForMemoryReadiness(t *testing.T) {
	upstreamCalled := false
	memory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer memory.Close()
	manager := supervisor.New(0)
	manager.Expect(supervisor.Service{Name: "memory", HealthURL: memory.URL + "/healthz"})
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   memory.URL + "/mcp",
		AppName:        "app",
		UserID:         "user",
		MemoryService:  config.ServiceConfig{Name: "memory"},
	}, manager)
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: "http://127.0.0.1:3/api/context",
		MemoryMCPURL:   memory.URL + "/mcp",
		AppName:        "app",
		UserID:         "user",
	}, supervisor.New(0))
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
		ContextBaseURL: contextAPI.URL + "/api/context",
		MemoryMCPURL:   "http://127.0.0.1:2/mcp",
		AppName:        "app",
		UserID:         "user",
	}, supervisor.New(0))
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

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
	server, err := NewServer(config.Config{
		ListenAddress:   "127.0.0.1:0",
		HarnessBaseURL:  "http://127.0.0.1:1/api",
		ContextBaseURL:  contextAPI.URL + "/api/context",
		ContextAPIToken: "context-secret",
		MemoryMCPURL:    "http://127.0.0.1:2/mcp",
		AppName:         "app",
		UserID:          "user",
		AuthToken:       "gateway-secret",
	}, supervisor.New(0))
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/context/tools/list", nil)
	req.Header.Set("Authorization", "Bearer gateway-secret")
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestRunSSEProxyInjectsRuntimePolicy verifies gateway-owned policy injection.
func TestRunSSEProxyInjectsRuntimePolicy(t *testing.T) {
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
		if !strings.HasPrefix(text, policy.RuntimePolicyPrefix) {
			t.Fatalf("text = %q, want Agent Awesome runtime policy prefix", text)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer harness.Close()
	server, err := NewServer(config.Config{
		ListenAddress:     "127.0.0.1:0",
		HarnessBaseURL:    harness.URL + "/api",
		ContextBaseURL:    "http://127.0.0.1:3/api/context",
		MemoryMCPURL:      "http://127.0.0.1:2/mcp",
		AppName:           "app",
		UserID:            "user",
		RuntimePolicyText: policy.DefaultRuntimePolicyText,
	}, supervisor.New(0))
	if err != nil {
		t.Fatalf("NewServer() error = %v", err)
	}

	body := strings.NewReader(`{"sessionId":"s1","newMessage":{"parts":[{"text":"hello"}]}}`)
	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", body)
	recorder := httptest.NewRecorder()
	server.routes().ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
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
