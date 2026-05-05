package proxy

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestProxyForwardsMountedAPIPath verifies the gateway can front the ADK API path.
func TestProxyForwardsMountedAPIPath(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/apps/app/users/user/sessions" {
			t.Fatalf("upstream path = %q, want ADK sessions path", r.URL.Path)
		}
		if r.URL.RawQuery != "limit=1" {
			t.Fatalf("upstream query = %q, want limit=1", r.URL.RawQuery)
		}
		_ = json.NewEncoder(w).Encode([]map[string]string{{"id": "session-1"}})
	}))
	defer upstream.Close()
	proxy, err := New(upstream.URL+"/api", "/api", 0)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/apps/app/users/user/sessions?limit=1", nil)
	recorder := httptest.NewRecorder()
	proxy.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestProxyInjectsPolicyForRunSSE verifies run bodies are rewritten before forwarding.
func TestProxyInjectsPolicyForRunSSE(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode upstream body: %v", err)
		}
		message := decoded["newMessage"].(map[string]any)
		parts := message["parts"].([]any)
		text := parts[0].(map[string]any)["text"].(string)
		if !strings.HasPrefix(text, RuntimePolicyPrefix) {
			t.Fatalf("text = %q, want policy prefix", text)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()
	proxy, err := New(upstream.URL+"/api", "/api", 0)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	body := strings.NewReader(`{"sessionId":"s1","newMessage":{"parts":[{"text":"hello"}]}}`)
	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", body)
	recorder := httptest.NewRecorder()
	proxy.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}
