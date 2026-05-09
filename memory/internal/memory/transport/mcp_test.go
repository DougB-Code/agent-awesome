// This file tests the memory MCP JSON-RPC transport behavior.
package transport

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	graphrepo "memory/internal/memory/graph/repository"
	"memory/internal/memory/service"
)

// TestMCPToolsList verifies the MCP tool list is exposed.
func TestMCPToolsList(t *testing.T) {
	server := newTestMCPServer(t)
	body := postRPC(t, server, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	result := body["result"].(map[string]any)
	tools := result["tools"].([]any)
	if len(tools) != 23 {
		t.Fatalf("tool count = %d, want 23", len(tools))
	}
}

// TestMCPTaskResourceSchemaIsJSONObject verifies nested array items are schemas.
func TestMCPTaskResourceSchemaIsJSONObject(t *testing.T) {
	server := newTestMCPServer(t)
	body := postRPC(t, server, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	tool := mcpToolDefinition(t, body, "update_task")
	schema := tool["inputSchema"].(map[string]any)
	properties := schema["properties"].(map[string]any)
	workBreakdown := properties["work_breakdown"].(map[string]any)
	workProperties := workBreakdown["properties"].(map[string]any)
	resources := workProperties["resources"].(map[string]any)
	items := resources["items"].(map[string]any)
	if items["type"] != "object" {
		t.Fatalf("resources.items.type = %#v, want object", items["type"])
	}
	if _, ok := items["properties"].(map[string]any); !ok {
		t.Fatalf("resources.items.properties = %#v, want object properties", items["properties"])
	}
}

// TestMCPCreateTaskSchemaIsLowFriction verifies create_task stays micro-model friendly.
func TestMCPCreateTaskSchemaIsLowFriction(t *testing.T) {
	server := newTestMCPServer(t)
	body := postRPC(t, server, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	tool := mcpToolDefinition(t, body, "create_task")
	schema := tool["inputSchema"].(map[string]any)
	properties := schema["properties"].(map[string]any)
	for _, key := range []string{"title", "description", "priority", "due_at", "scheduled_at", "topics"} {
		if _, ok := properties[key]; !ok {
			t.Fatalf("create_task properties missing %q: %#v", key, properties)
		}
	}
	for _, key := range []string{"status", "energy_required", "effort", "value", "urgency", "risk", "work_breakdown", "memory_links"} {
		if _, ok := properties[key]; ok {
			t.Fatalf("create_task exposes advanced field %q in %#v", key, properties)
		}
	}
}

// TestMCPSaveAndSearch verifies tools call through the service boundary.
func TestMCPSaveAndSearch(t *testing.T) {
	server := newTestMCPServer(t)
	save := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "save_memory_candidate",
			"arguments": map[string]any{
				"content":         "MCP reporting source",
				"scope":           "user",
				"title":           "MCP source",
				"idempotency_key": "mcp-save",
			},
		},
	})
	saveResult := save["result"].(map[string]any)
	if saveResult["isError"].(bool) {
		t.Fatalf("save returned tool error: %#v", saveResult)
	}
	search := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "search_memory",
			"arguments": map[string]any{
				"scope": "user",
				"text":  "reporting",
			},
		},
	})
	searchResult := search["result"].(map[string]any)
	if searchResult["isError"].(bool) {
		t.Fatalf("search returned tool error: %#v", searchResult)
	}
	structured := searchResult["structuredContent"].(map[string]any)
	primary := structured["primary_memory"].([]any)
	if len(primary) != 1 {
		t.Fatalf("primary evidence count = %d, want 1", len(primary))
	}
}

// TestMCPRememberStoresMemoryNugget verifies the small memory write surface.
func TestMCPRememberStoresMemoryNugget(t *testing.T) {
	server := newTestMCPServer(t)
	remember := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "remember",
			"arguments": map[string]any{
				"text":            "Doug prefers memory to be stored as small connected nuggets.",
				"topics":          []string{"memory", "preference"},
				"entities":        []string{"Doug", "Agent Awesome"},
				"idempotency_key": "remember-nugget",
			},
		},
	})
	rememberResult := remember["result"].(map[string]any)
	if rememberResult["isError"].(bool) {
		t.Fatalf("remember returned tool error: %#v", rememberResult)
	}
	search := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "search_memory",
			"arguments": map[string]any{
				"scope": "user",
				"text":  "connected nuggets",
			},
		},
	})
	searchResult := search["result"].(map[string]any)
	if searchResult["isError"].(bool) {
		t.Fatalf("search returned tool error: %#v", searchResult)
	}
	primary := searchResult["structuredContent"].(map[string]any)["primary_memory"].([]any)
	if len(primary) != 1 {
		t.Fatalf("primary memory count = %d, want 1", len(primary))
	}
	record := primary[0].(map[string]any)
	if record["kind"] != "profile_fact" || record["trust_level"] != "user_asserted" {
		t.Fatalf("record = %#v, want user-asserted profile fact", record)
	}
}

// TestMCPCreateTaskAcceptsMinimalTodo verifies a one-line user todo is enough.
func TestMCPCreateTaskAcceptsMinimalTodo(t *testing.T) {
	server := newTestMCPServer(t)
	before := time.Now().UTC()
	create := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "create_task",
			"arguments": map[string]any{"title": "Buy milk"},
		},
	})
	after := time.Now().UTC()
	createResult := create["result"].(map[string]any)
	if createResult["isError"].(bool) {
		t.Fatalf("create task returned tool error: %#v", createResult)
	}
	task := createResult["structuredContent"].(map[string]any)
	if task["title"] != "Buy milk" || task["status"] != "open" || task["priority"] != "normal" {
		t.Fatalf("task = %#v, want low-friction open normal task", task)
	}
	followUpAt, err := time.Parse(time.RFC3339Nano, task["follow_up_at"].(string))
	if err != nil {
		t.Fatalf("follow_up_at = %#v, want RFC3339 timestamp: %v", task["follow_up_at"], err)
	}
	minFollowUp := before.Add(7*24*time.Hour - time.Second)
	maxFollowUp := after.Add(7*24*time.Hour + time.Second)
	if followUpAt.Before(minFollowUp) || followUpAt.After(maxFollowUp) {
		t.Fatalf("follow_up_at = %s, want between %s and %s", followUpAt, minFollowUp, maxFollowUp)
	}
}

// TestMCPCreateTaskCoercesLegacyModelMetadata verifies stale local-model calls survive.
func TestMCPCreateTaskCoercesLegacyModelMetadata(t *testing.T) {
	server := newTestMCPServer(t)
	create := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "create_task",
			"arguments": map[string]any{
				"title":            "Buy Milk",
				"description":      "Purchase milk.",
				"status":           "pending",
				"priority":         "medium",
				"energy_required":  1,
				"effort":           5,
				"urgency":          "low",
				"value":            10,
				"memory_links":     []any{},
				"work_breakdown":   []string{"Go to store", "Select milk", "Pay"},
				"idempotency_key":  "buy-milk-legacy",
				"estimate_minutes": 10,
			},
		},
	})
	createResult := create["result"].(map[string]any)
	if createResult["isError"].(bool) {
		t.Fatalf("create task returned tool error: %#v", createResult)
	}
	task := createResult["structuredContent"].(map[string]any)
	if task["status"] != "open" || task["priority"] != "normal" {
		t.Fatalf("task status/priority = %#v/%#v, want coerced open/normal", task["status"], task["priority"])
	}
	if task["energy_required"] != "1" || task["urgency"] != 0.25 || task["value"] != 1.0 {
		t.Fatalf("task metadata = %#v, want tolerant scalar coercion", task)
	}
}

// TestMCPCreateTaskRecoversMalformedGemmaKeys verifies memory accepts bad keys.
func TestMCPCreateTaskRecoversMalformedGemmaKeys(t *testing.T) {
	server := newTestMCPServer(t)
	create := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "create_task",
			"arguments": map[string]any{
				`title:<|"|>Buy milk<|"|>`:                         nil,
				`description:<|"|>Buy milk<|"|>`:                   nil,
				`idempotency_key:<|"|>agent_awesome:session:<|"|>`: nil,
			},
		},
	})
	createResult := create["result"].(map[string]any)
	if createResult["isError"].(bool) {
		t.Fatalf("create task returned tool error: %#v", createResult)
	}
	task := createResult["structuredContent"].(map[string]any)
	if task["title"] != "Buy milk" || task["description"] != "Buy milk" {
		t.Fatalf("task = %#v, want recovered title and description", task)
	}
	if task["idempotency_key"] != "agent_awesome:session:" {
		t.Fatalf("task idempotency key = %#v, want recovered key", task["idempotency_key"])
	}
}

// TestMCPGraphTaskTools verifies task tools call through graph-backed memory.
func TestMCPGraphTaskTools(t *testing.T) {
	server := newTestMCPServer(t)
	create := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "create_task",
			"arguments": map[string]any{
				"title":           "Prepare graph readout",
				"topics":          []string{"graph"},
				"idempotency_key": "mcp-task",
			},
		},
	})
	createResult := create["result"].(map[string]any)
	if createResult["isError"].(bool) {
		t.Fatalf("create task returned tool error: %#v", createResult)
	}
	task := createResult["structuredContent"].(map[string]any)
	list := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "list_tasks",
			"arguments": map[string]any{"topics": []string{"graph"}, "include_done": true},
		},
	})
	listResult := list["result"].(map[string]any)
	if listResult["isError"].(bool) {
		t.Fatalf("list tasks returned tool error: %#v", listResult)
	}
	tasks := listResult["structuredContent"].([]any)
	if len(tasks) != 1 || tasks[0].(map[string]any)["id"] != task["id"] {
		t.Fatalf("tasks = %#v, want created task %s", tasks, task["id"])
	}
	blockerCreate := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      3,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      "create_task",
			"arguments": map[string]any{"title": "Clean graph inputs"},
		},
	})
	blocker := blockerCreate["result"].(map[string]any)["structuredContent"].(map[string]any)
	relation := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      4,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "upsert_task_relation",
			"arguments": map[string]any{
				"from_task_id": task["id"],
				"type":         "depends_on",
				"to_task_id":   blocker["id"],
			},
		},
	})
	if relation["result"].(map[string]any)["isError"].(bool) {
		t.Fatalf("upsert relation returned tool error: %#v", relation["result"])
	}
	traverse := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      5,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "traverse_task_relations",
			"arguments": map[string]any{
				"root_task_id":  task["id"],
				"types":         []string{"depends_on"},
				"include_tasks": true,
			},
		},
	})
	traverseResult := traverse["result"].(map[string]any)
	if traverseResult["isError"].(bool) {
		t.Fatalf("traverse relations returned tool error: %#v", traverseResult)
	}
	paths := traverseResult["structuredContent"].(map[string]any)["paths"].([]any)
	if len(paths) != 1 {
		t.Fatalf("paths = %#v, want one depends_on path", paths)
	}
	projection := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      6,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "task_graph_projection",
			"arguments": map[string]any{
				"tasks":          map[string]any{"include_done": true},
				"include_facets": true,
			},
		},
	})
	projectionResult := projection["result"].(map[string]any)
	if projectionResult["isError"].(bool) {
		t.Fatalf("projection returned tool error: %#v", projectionResult)
	}
	graph := projectionResult["structuredContent"].(map[string]any)
	if len(graph["nodes"].([]any)) != 2 || len(graph["relations"].([]any)) != 1 {
		t.Fatalf("projection graph = %#v, want two task nodes and one relation", graph)
	}
	query := postRPC(t, server, map[string]any{
		"jsonrpc": "2.0",
		"id":      7,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "query_context_graph",
			"arguments": map[string]any{
				"query": `FIND task WHERE status = "open" RETURN id, title, status ORDER BY title ASC LIMIT 10`,
			},
		},
	})
	queryResult := query["result"].(map[string]any)
	if queryResult["isError"].(bool) {
		t.Fatalf("query returned tool error: %#v", queryResult)
	}
	rows := queryResult["structuredContent"].(map[string]any)["rows"].([]any)
	if len(rows) != 2 {
		t.Fatalf("query rows = %#v, want two open tasks", rows)
	}
}

// TestMCPRejectsOversizedJSONRPCRequest verifies MCP requests have a hard cap.
func TestMCPRejectsOversizedJSONRPCRequest(t *testing.T) {
	server := NewMCPServer(nil)
	body := `{"jsonrpc":"2.0","id":1,"method":"tools/list","padding":"` + strings.Repeat("x", int(maxJSONRPCRequestBytes)) + `"}`
	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(body))
	rec := httptest.NewRecorder()

	server.ServeHTTP(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", rec.Code)
	}
}

// mcpToolDefinition returns one named tool definition from a tools/list body.
func mcpToolDefinition(t *testing.T, body map[string]any, name string) map[string]any {
	t.Helper()
	result := body["result"].(map[string]any)
	tools := result["tools"].([]any)
	for _, raw := range tools {
		tool := raw.(map[string]any)
		if tool["name"] == name {
			return tool
		}
	}
	t.Fatalf("tool %q not found in %#v", name, tools)
	return nil
}

// newTestMCPServer creates an isolated MCP server.
func newTestMCPServer(t *testing.T) *MCPServer {
	t.Helper()
	root := t.TempDir()
	repo, err := graphrepo.Open(context.Background(), graphrepo.Config{
		DBPath:   filepath.Join(root, "graph.db"),
		DataRoot: filepath.Join(root, "data"),
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = repo.Close() })
	return NewMCPServer(service.New(repo, nil, service.Config{}))
}

// postRPC sends a JSON-RPC request and decodes its response.
func postRPC(t *testing.T, server *MCPServer, payload map[string]any) map[string]any {
	t.Helper()
	bytesBody, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal rpc: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/mcp", bytes.NewReader(bytesBody))
	rec := httptest.NewRecorder()
	server.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode rpc response: %v", err)
	}
	if _, ok := body["error"]; ok {
		t.Fatalf("rpc error: %#v", body)
	}
	return body
}
