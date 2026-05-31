// This file tests the runbook MCP control surface.
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

	"agentawesome/internal/services/runbook/runtime"
)

// TestMCPRunbookStartReturnsRun verifies agents can start runbooks through MCP.
func TestMCPRunbookStartReturnsRun(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTransportDefinition(t, definitionsDir, "daily.yaml", `
kind: state_machine
id: daily_email_triage
name: Daily Email Triage
initial: triage
states:
  - id: triage
    on_entry:
      - id: triage
        type: tool
        tool: mock_tool
        with:
          arguments: {}
`)
	service, err := runtime.Open(ctx, runtime.Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "runbook.db"),
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
			"name": "runbook_start",
			"arguments": map[string]any{
				"definition_id": "daily_email_triage",
				"input":         map[string]any{"day": "today"},
			},
		},
	}
	response := postJSONRPC(t, server.URL+"/mcp", body)
	result := response["result"].(map[string]any)
	if result["isError"] == true {
		t.Fatalf("MCP result = %#v, want successful runbook_start", result)
	}
	structured := result["structuredContent"].(map[string]any)
	if structured["run"] == nil {
		t.Fatalf("structuredContent = %#v, want run", structured)
	}
}

// TestMCPRunbookAuthoringToolsCreateDraft verifies agents can draft runbooks.
func TestMCPRunbookAuthoringToolsCreateDraft(t *testing.T) {
	ctx := context.Background()
	service, err := runtime.Open(ctx, runtime.Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "runbook.db"),
		RequestTimeout: time.Second,
		DesignAssistant: transportDesignAssistant{artifacts: []runtime.DesignArtifact{{
			Kind: "mapping",
			Body: map[string]any{
				"apiVersion": "aa.mapping/v1",
				"kind":       "Mapping",
				"name":       "mcp-suggested",
				"steps": []any{
					map[string]any{"set": map[string]any{
						"target": "approval.title",
						"value":  map[string]any{"expr": `"Approve " + input.body.value.subject`},
					}},
				},
			},
		}}},
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
			"name":      "runbook_action_types",
			"arguments": map[string]any{},
		},
	})
	structured := actionTypes["result"].(map[string]any)["structuredContent"].(map[string]any)
	if structured["action_types"] == nil {
		t.Fatalf("runbook_action_types structuredContent = %#v, want action_types", structured)
	}
	manifests := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "runbook_manifests",
			"arguments": map[string]any{},
		},
	})
	manifestContent := manifests["result"].(map[string]any)["structuredContent"].(map[string]any)
	if manifestContent["manifests"] == nil {
		t.Fatalf("runbook_manifests structuredContent = %#v, want manifests", manifestContent)
	}
	preview := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      3,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "runbook_mapping_preview",
			"arguments": map[string]any{
				"input": map[string]any{"subject": "Invoice"},
				"mapping": map[string]any{
					"steps": []any{
						map[string]any{"set": map[string]any{
							"target": "approval.title",
							"value":  map[string]any{"expr": `"Approve " + input.body.value.subject`},
						}},
					},
				},
			},
		},
	})
	previewContent := preview["result"].(map[string]any)["structuredContent"].(map[string]any)
	if previewContent["preview"] == nil {
		t.Fatalf("runbook_mapping_preview structuredContent = %#v, want preview", previewContent)
	}
	suggested := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      4,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "runbook_design_suggest",
			"arguments": map[string]any{"prompt": "suggest mapping"},
		},
	})
	suggestedContent := suggested["result"].(map[string]any)["structuredContent"].(map[string]any)
	if suggestedContent["suggestion"] == nil {
		t.Fatalf("runbook_design_suggest structuredContent = %#v, want suggestion", suggestedContent)
	}

	created := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      5,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "runbook_draft_create",
			"arguments": map[string]any{
				"id":   "draft_mcp",
				"kind": "runbook",
				"name": "MCP Draft",
				"body": map[string]any{
					"kind":    "state_machine",
					"id":      "mcp_draft",
					"name":    "MCP Draft",
					"initial": "call",
					"states": []any{
						map[string]any{
							"id": "call",
							"on_entry": []any{
								map[string]any{
									"id":   "source",
									"uses": "tool.call",
									"with": map[string]any{"name": "mock_tool", "arguments": map[string]any{}},
								},
							},
						},
					},
				},
			},
		},
	})
	createdResult := created["result"].(map[string]any)
	if createdResult["isError"] == true {
		t.Fatalf("runbook_draft_create result = %#v, want success", createdResult)
	}
	observed := postJSONRPC(t, server.URL+"/mcp", map[string]any{
		"jsonrpc": "2.0",
		"id":      6,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "runbook_observed_contracts",
			"arguments": map[string]any{"definition_id": "mcp_draft"},
		},
	})
	observedContent := observed["result"].(map[string]any)["structuredContent"].(map[string]any)
	if observedContent["observed_contracts"] == nil {
		t.Fatalf("runbook_observed_contracts structuredContent = %#v, want observed_contracts", observedContent)
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

// transportDesignAssistant returns fixed artifacts for MCP transport tests.
type transportDesignAssistant struct {
	artifacts []runtime.DesignArtifact
}

// SuggestDesignArtifacts returns configured test artifacts.
func (a transportDesignAssistant) SuggestDesignArtifacts(context.Context, runtime.DesignSuggestionRequest) ([]runtime.DesignArtifact, error) {
	return a.artifacts, nil
}
