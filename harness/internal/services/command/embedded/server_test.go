// This file tests command service embedding for host processes.
package embedded

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

// TestStartServesHealthAndMCP verifies embedded command exposes daemon routes.
func TestStartServesHealthAndMCP(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	server, err := Start(ctx, Config{
		ListenAddress:   "127.0.0.1:0",
		DataDir:         t.TempDir(),
		AllowedWorkdirs: []string{t.TempDir()},
		DefaultTimeout:  time.Second,
		ApprovalTTL:     time.Second,
		AllowArbitrary:  true,
	})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() {
		closeCtx, closeCancel := context.WithTimeout(context.Background(), time.Second)
		defer closeCancel()
		_ = server.Close(closeCtx)
	}()

	resp, err := http.Get("http://" + server.Address() + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health status = %d, want %d", resp.StatusCode, http.StatusOK)
	}

	body := bytes.NewBufferString(`{"jsonrpc":"2.0","id":1,"method":"tools/list"}`)
	mcpResp, err := http.Post("http://"+server.Address()+"/mcp", "application/json", body)
	if err != nil {
		t.Fatalf("POST /mcp error = %v", err)
	}
	defer mcpResp.Body.Close()
	if mcpResp.StatusCode != http.StatusOK {
		t.Fatalf("mcp status = %d, want %d", mcpResp.StatusCode, http.StatusOK)
	}
	var payload struct {
		Result struct {
			Tools []struct {
				Name string `json:"name"`
			} `json:"tools"`
		} `json:"result"`
	}
	if err := json.NewDecoder(mcpResp.Body).Decode(&payload); err != nil {
		t.Fatalf("decode MCP response: %v", err)
	}
	if len(payload.Result.Tools) == 0 {
		t.Fatalf("tools/list returned no tools")
	}
}
