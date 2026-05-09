// This file tests gateway proxy forwarding, rewriting, and request limits.
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

// TestProxyAppliesBodyTransformer verifies configured body rewrites are forwarded.
func TestProxyAppliesBodyTransformer(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var decoded map[string]any
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("decode upstream body: %v", err)
		}
		if decoded["rewritten"] != true {
			t.Fatalf("decoded = %#v, want transformed body", decoded)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()
	proxy, err := New(upstream.URL+"/api", "/api", 0, WithBodyTransformer(func(_ *http.Request, body []byte) ([]byte, error) {
		var decoded map[string]any
		if err := json.Unmarshal(body, &decoded); err != nil {
			return nil, err
		}
		decoded["rewritten"] = true
		return json.Marshal(decoded)
	}))
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	body := strings.NewReader(`{"message":"hello"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", body)
	recorder := httptest.NewRecorder()
	proxy.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestProxySetsTrustedUpstreamHeader verifies caller auth is not forwarded.
func TestProxySetsTrustedUpstreamHeader(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer upstream-secret" {
			t.Fatalf("Authorization = %q, want trusted upstream token", got)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()
	proxy, err := New(
		upstream.URL+"/api",
		"/api",
		0,
		WithUpstreamHeader("Authorization", "Bearer upstream-secret"),
	)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/context/tools/list", nil)
	req.Header.Set("Authorization", "Bearer caller-secret")
	recorder := httptest.NewRecorder()
	proxy.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
}

// TestProxyRejectsOversizedRequestBody verifies body caps protect proxy memory.
func TestProxyRejectsOversizedRequestBody(t *testing.T) {
	upstreamCalled := false
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamCalled = true
		w.WriteHeader(http.StatusOK)
	}))
	defer upstream.Close()
	proxy, err := New(upstream.URL+"/api", "/api", 0)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	body := strings.NewReader(strings.Repeat("x", int(maxRequestBodyBytes)+1))
	req := httptest.NewRequest(http.MethodPost, "/api/run_sse", body)
	recorder := httptest.NewRecorder()
	proxy.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", recorder.Code)
	}
	if upstreamCalled {
		t.Fatalf("upstream was called for an oversized body")
	}
}
