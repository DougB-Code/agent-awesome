// This file tests MCP transport construction details.
package mcptransport

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"agentawesome/internal/config/schema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// TestNewHTTPTransportInjectsConfiguredHeaders verifies remote MCP auth headers.
func TestNewHTTPTransportInjectsConfiguredHeaders(t *testing.T) {
	t.Setenv("MCP_AUTH_HEADER", "Bearer secret")
	transport, err := New(schema.MCPServer{
		Transport: "streamable-http",
		Endpoint:  "https://example.test/mcp",
		Headers: map[string]string{
			"CF-Access-Client-Id": "client-id",
		},
		HeadersFromEnv: map[string]string{
			"Authorization": "MCP_AUTH_HEADER",
		},
	})
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	streamable, ok := transport.(*mcp.StreamableClientTransport)
	if !ok {
		t.Fatalf("transport type = %T, want streamable HTTP", transport)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got, want := r.Header.Get("Authorization"), "Bearer secret"; got != want {
			t.Fatalf("Authorization = %q, want %q", got, want)
		}
		if got, want := r.Header.Get("CF-Access-Client-Id"), "client-id"; got != want {
			t.Fatalf("CF-Access-Client-Id = %q, want %q", got, want)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	req, err := http.NewRequest(http.MethodGet, server.URL, nil)
	if err != nil {
		t.Fatalf("NewRequest() error = %v", err)
	}
	resp, err := streamable.HTTPClient.Do(req)
	if err != nil {
		t.Fatalf("Do() error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", resp.StatusCode)
	}
}
