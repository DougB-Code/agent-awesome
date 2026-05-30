// This file tests Operations HTTP and MCP transports.
package operations

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestOperationMCPToolsList verifies Operation tools are exposed separately.
func TestOperationMCPToolsList(t *testing.T) {
	server := NewHTTPServer(newTestOperationsService(t))
	body := postOperationRPC(t, server, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	result := body["result"].(map[string]any)
	tools := result["tools"].([]any)
	if len(tools) != 6 {
		t.Fatalf("tool count = %d, want 6", len(tools))
	}
}

// TestOperationsHTTPPreview verifies preview route returns resolved input.
func TestOperationsHTTPPreview(t *testing.T) {
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)
	server := NewHTTPServer(service)
	payload, _ := json.Marshal(map[string]any{"input": map[string]any{"change_request": "Fix crash"}})
	req := httptest.NewRequest(http.MethodPost, "/api/operations/"+op.ID+"/preview", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	preview := body["preview"].(map[string]any)
	if preview["status"] != "ready" {
		t.Fatalf("preview = %#v, want ready", preview)
	}
}

// TestOperationsHTTPRunSnapshot verifies audit snapshot routing.
func TestOperationsHTTPRunSnapshot(t *testing.T) {
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)
	started, err := service.StartOperation(context.Background(), op.ID, OperationRunRequest{Input: map[string]any{"change_request": "Fix crash"}})
	if err != nil {
		t.Fatalf("StartOperation() error = %v", err)
	}
	server := NewHTTPServer(service)
	req := httptest.NewRequest(http.MethodGet, "/api/operations/runs/"+started.Run.ID+"/snapshot", nil)
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	snapshot := body["snapshot"].(map[string]any)
	if snapshot["operation_id"] != op.ID {
		t.Fatalf("snapshot = %#v, want operation id", snapshot)
	}
}

// TestOperationsHTTPQueueRoutes verifies enqueue and target lease routes.
func TestOperationsHTTPQueueRoutes(t *testing.T) {
	service := newTestOperationsService(t)
	op := createTestSourceOperation(t, service)
	server := NewHTTPServer(service)
	payload, _ := json.Marshal(map[string]any{
		"input":  map[string]any{"change_request": "Fix crash"},
		"source": "schedule",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/operations/"+op.ID+"/enqueue", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("enqueue status = %d body = %s", rec.Code, rec.Body.String())
	}

	leasePayload, _ := json.Marshal(map[string]any{"target_id": "this_computer"})
	req = httptest.NewRequest(http.MethodPost, "/api/operations/queue/lease", bytes.NewReader(leasePayload))
	rec = httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("lease status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	lease := body["lease"].(map[string]any)
	item := lease["item"].(map[string]any)
	if item["status"] != OperationRunQueueStatusLeased {
		t.Fatalf("lease item = %#v, want leased", item)
	}
}

// postOperationRPC sends one JSON-RPC request to the Operations MCP route.
func postOperationRPC(t *testing.T, server *HTTPServer, payload map[string]any) map[string]any {
	t.Helper()
	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/operations/mcp", bytes.NewReader(data))
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	return body
}
