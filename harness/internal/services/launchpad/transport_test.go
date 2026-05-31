// This file tests Launchpad HTTP and MCP transports.
package launchpad

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestLaunchMCPToolsList verifies Launch tools are exposed separately.
func TestLaunchMCPToolsList(t *testing.T) {
	server := NewHTTPServer(newTestLaunchpadService(t))
	body := postLaunchRPC(t, server, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
	result := body["result"].(map[string]any)
	tools := result["tools"].([]any)
	if len(tools) != 6 {
		t.Fatalf("tool count = %d, want 6", len(tools))
	}
}

// TestLaunchpadHTTPPreview verifies preview route returns resolved input.
func TestLaunchpadHTTPPreview(t *testing.T) {
	service := newTestLaunchpadService(t)
	op := createTestSourceLaunch(t, service)
	server := NewHTTPServer(service)
	payload, _ := json.Marshal(map[string]any{"input": map[string]any{"change_request": "Fix crash"}})
	req := httptest.NewRequest(http.MethodPost, "/api/launchpad/"+op.ID+"/preview", bytes.NewReader(payload))
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

// TestLaunchpadHTTPRunSnapshot verifies audit snapshot routing.
func TestLaunchpadHTTPRunSnapshot(t *testing.T) {
	service := newTestLaunchpadService(t)
	op := createTestSourceLaunch(t, service)
	started, err := service.StartLaunch(context.Background(), op.ID, LaunchRunRequest{Input: map[string]any{"change_request": "Fix crash"}})
	if err != nil {
		t.Fatalf("StartLaunch() error = %v", err)
	}
	server := NewHTTPServer(service)
	req := httptest.NewRequest(http.MethodGet, "/api/launchpad/runs/"+started.Run.ID+"/snapshot", nil)
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
	if snapshot["launch_id"] != op.ID {
		t.Fatalf("snapshot = %#v, want launch id", snapshot)
	}
}

// TestLaunchpadHTTPQueueRoutes verifies enqueue and target lease routes.
func TestLaunchpadHTTPQueueRoutes(t *testing.T) {
	service := newTestLaunchpadService(t)
	op := createTestSourceLaunch(t, service)
	server := NewHTTPServer(service)
	payload, _ := json.Marshal(map[string]any{
		"input":  map[string]any{"change_request": "Fix crash"},
		"source": "schedule",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/launchpad/"+op.ID+"/enqueue", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("enqueue status = %d body = %s", rec.Code, rec.Body.String())
	}

	leasePayload, _ := json.Marshal(map[string]any{"target_id": "this_computer"})
	req = httptest.NewRequest(http.MethodPost, "/api/launchpad/queue/lease", bytes.NewReader(leasePayload))
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
	if item["status"] != LaunchRunQueueStatusLeased {
		t.Fatalf("lease item = %#v, want leased", item)
	}
}

// TestLaunchpadHTTPEnqueueDueRoute verifies cron workers can enqueue scheduled Launchpad work.
func TestLaunchpadHTTPEnqueueDueRoute(t *testing.T) {
	service := newTestLaunchpadService(t)
	_, err := service.CreateLaunch(context.Background(), LaunchRequest{
		ID:              "scheduled_source_change",
		Name:            "Scheduled Source Change",
		RunbookID:       testRunbookID,
		CodebaseID:      "agent_awesome",
		RuntimeTargetID: "this_computer",
		Defaults:        map[string]any{"change_request": "Refresh docs"},
		Schedule:        LaunchSchedule{Enabled: true, Cron: "5 12 * * *"},
	})
	if err != nil {
		t.Fatalf("CreateLaunch() error = %v", err)
	}
	server := NewHTTPServer(service)
	payload, _ := json.Marshal(map[string]any{"now": "2026-05-24T12:05:00Z"})
	req := httptest.NewRequest(http.MethodPost, "/api/launchpad/queue/enqueue-due", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	schedule := body["schedule"].(map[string]any)
	enqueued := schedule["enqueued"].([]any)
	if len(enqueued) != 1 {
		t.Fatalf("schedule = %#v, want one enqueued run", schedule)
	}
}

// postLaunchRPC sends one JSON-RPC request to the Launchpad MCP route.
func postLaunchRPC(t *testing.T, server *HTTPServer, payload map[string]any) map[string]any {
	t.Helper()
	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("Marshal() error = %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/launchpad/mcp", bytes.NewReader(data))
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
