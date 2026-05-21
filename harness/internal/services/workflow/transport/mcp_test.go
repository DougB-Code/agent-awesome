// This file tests the workflow MCP control surface.
package transport

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"agentawesome/internal/services/workflow/runtime"
)

// TestMCPWorkflowStartReturnsRun verifies agents can start workflows through MCP.
func TestMCPWorkflowStartReturnsRun(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTransportDefinition(t, definitionsDir, "daily.yaml", `
kind: state_machine
id: daily_email_triage
name: Daily Email Triage
states:
  - id: triage
    type: task
    uses: tool.call
    with:
      name: mock_tool
      arguments: {}
`)
	service, err := runtime.Open(ctx, runtime.Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()
	server := httptest.NewServer(NewHTTPServer(service).Routes())
	defer server.Close()

	body := map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "workflow_start",
			"arguments": map[string]any{
				"definition_id": "daily_email_triage",
				"input":         map[string]any{"day": "today"},
			},
		},
	}
	response := postJSONRPC(t, server.URL+"/mcp", body)
	result := response["result"].(map[string]any)
	if result["isError"] == true {
		t.Fatalf("MCP result = %#v, want successful workflow_start", result)
	}
	structured := result["structuredContent"].(map[string]any)
	if structured["run"] == nil {
		t.Fatalf("structuredContent = %#v, want run", structured)
	}
}

// TestMCPWorkflowAuthoringToolsCreateDraft verifies agents can draft workflows.
func TestMCPWorkflowAuthoringToolsCreateDraft(t *testing.T) {
	ctx := context.Background()
	service, err := runtime.Open(ctx, runtime.Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()
	server := httptest.NewServer(NewHTTPServer(service).Routes())
	defer server.Close()

	actionTypes := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "workflow_action_types",
			"arguments": map[string]any{},
		},
	})
	structured := actionTypes["result"].(map[string]any)["structuredContent"].(map[string]any)
	if structured["action_types"] == nil {
		t.Fatalf("workflow_action_types structuredContent = %#v, want action_types", structured)
	}

	created := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "workflow_draft_create",
			"arguments": map[string]any{
				"id":   "draft_mcp",
				"kind": "task_graph",
				"name": "MCP Draft",
				"body": map[string]any{
					"kind": "task_graph",
					"id":   "mcp_draft",
					"name": "MCP Draft",
					"nodes": []any{
						map[string]any{"id": "tool", "uses": "tool.call", "with": map[string]any{"name": "mock_tool", "arguments": map[string]any{}}},
					},
				},
			},
		},
	})
	createdResult := created["result"].(map[string]any)
	if createdResult["isError"] == true {
		t.Fatalf("workflow_draft_create result = %#v, want success", createdResult)
	}

}

// postJSONRPC posts one JSON-RPC body and returns the decoded response.
func postJSONRPC(t *testing.T, url string, body map[string]any) map[string]any {
	t.Helper()
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	resp, err := http.Post(url, "application/json", bytes.NewReader(encoded))
	if err != nil {
		t.Fatalf("Post() error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	var decoded map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
	return decoded
}

// writeTransportDefinition writes one YAML definition for transport tests.
func writeTransportDefinition(t *testing.T, dir string, name string, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
}
