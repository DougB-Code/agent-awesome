package gateway

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"agentgateway/internal/config"
	"agentgateway/internal/supervisor"
)

// TestStatusRequiresBearerToken verifies optional personal cloud auth.
func TestStatusRequiresBearerToken(t *testing.T) {
	server, err := NewServer(config.Config{
		ListenAddress:  "127.0.0.1:0",
		HarnessBaseURL: "http://127.0.0.1:1/api",
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
