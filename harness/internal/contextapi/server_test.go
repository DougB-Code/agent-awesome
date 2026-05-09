// This file tests context API HTTP request handling safety.
package contextapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestCallToolRejectsOversizedRequest verifies tool calls have a hard body cap.
func TestCallToolRejectsOversizedRequest(t *testing.T) {
	server := &Server{}
	body := `{"name":"search_memory","arguments":{"padding":"` + strings.Repeat("x", int(maxContextAPIRequestBytes)) + `"}}`
	req := httptest.NewRequest(http.MethodPost, contextAPIPrefix+"/tools/call", strings.NewReader(body))
	rec := httptest.NewRecorder()

	server.routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", rec.Code)
	}
}

// TestStartRejectsPublicBindWithoutToken verifies direct exposure needs auth.
func TestStartRejectsPublicBindWithoutToken(t *testing.T) {
	_, err := StartWithConfig(context.Background(), Config{Addr: "0.0.0.0:0"}, nil)
	if err == nil {
		t.Fatalf("StartWithConfig() error = nil, want public bind token error")
	}
}

// TestStartAllowsLoopbackBindWithoutToken verifies local development stays simple.
func TestStartAllowsLoopbackBindWithoutToken(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	server, err := StartWithConfig(ctx, Config{Addr: "127.0.0.1:0"}, nil)
	if err != nil {
		t.Fatalf("StartWithConfig() error = %v", err)
	}
	if server == nil {
		t.Fatalf("StartWithConfig() server = nil, want server")
	}
}

// TestContextAPITokenProtectsToolRoutes verifies tool access requires bearer auth.
func TestContextAPITokenProtectsToolRoutes(t *testing.T) {
	server := &Server{authToken: "secret"}
	req := httptest.NewRequest(http.MethodGet, contextAPIPrefix+"/tools/list", nil)
	rec := httptest.NewRecorder()

	server.routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

// TestContextAPIHealthzStaysTokenless verifies liveness exposes no tool data.
func TestContextAPIHealthzStaysTokenless(t *testing.T) {
	server := &Server{authToken: "secret"}
	req := httptest.NewRequest(http.MethodGet, contextAPIPrefix+"/healthz", nil)
	rec := httptest.NewRecorder()

	server.routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}
