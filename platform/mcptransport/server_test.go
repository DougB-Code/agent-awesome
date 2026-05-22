// This file tests the shared MCP JSON-RPC transport shell.
package mcptransport

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestServerToolsCall verifies a tool call returns structured MCP content.
func TestServerToolsCall(t *testing.T) {
	server := Server{
		Info: ServerInfo{Name: "test"},
		Call: func(_ context.Context, name string, _ json.RawMessage) (any, error) {
			return map[string]string{"name": name}, nil
		},
	}
	encoded, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params":  map[string]any{"name": "ping", "arguments": map[string]any{}},
	})
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	rec := httptest.NewRecorder()
	server.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/mcp", bytes.NewReader(encoded)))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	result := body["result"].(map[string]any)
	if result["isError"] == true {
		t.Fatalf("result = %#v, want success", result)
	}
}

// TestServerHTTPGuards verifies notification and bounded-body behavior.
func TestServerHTTPGuards(t *testing.T) {
	cases := []struct {
		name   string
		server Server
		body   string
		want   int
	}{
		{name: "notification", body: `{"jsonrpc":"2.0","method":"tools/list"}`, want: http.StatusNoContent},
		{name: "oversized", server: Server{MaxRequestBytes: 8}, body: `{"jsonrpc":"2.0","id":1}`, want: http.StatusRequestEntityTooLarge},
	}
	for _, tt := range cases {
		rec := httptest.NewRecorder()
		tt.server.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(tt.body)))
		if rec.Code != tt.want {
			t.Fatalf("%s status = %d, want %d", tt.name, rec.Code, tt.want)
		}
	}
}
