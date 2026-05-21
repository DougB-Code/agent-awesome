// This file tests workflow MCP client behavior.
package runtime

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"agentawesome/internal/services/workflow/actions"
)

// TestMCPClientReturnsErrorForToolResultError verifies isError tool results fail actions.
func TestMCPClientReturnsErrorForToolResultError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"result": map[string]any{
			"isError":           true,
			"structuredContent": map[string]any{"error": "tool failed"},
		}})
	}))
	defer server.Close()
	client := NewMCPClient(time.Second)

	_, err := client.Call(context.Background(), actions.MCPRequest{Endpoint: server.URL, Tool: "mock.fail"})
	if err == nil || !strings.Contains(err.Error(), "tool failed") {
		t.Fatalf("Call() error = %v, want MCP tool failure", err)
	}
}
