// This file tests local MCP server management behavior.
package mcp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"
	"time"
)

// TestToolListAndCallUseConfiguredEndpoint verifies discovery and invocation route through one server config.
func TestToolListAndCallUseConfiguredEndpoint(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		switch body["method"] {
		case "tools/list":
			writeJSON(w, map[string]any{"result": map[string]any{"tools": []map[string]any{{"name": "echo"}}}})
		case "tools/call":
			writeJSON(w, map[string]any{"result": map[string]any{"structuredContent": map[string]any{"ok": true}}})
		default:
			http.Error(w, "unexpected method", http.StatusBadRequest)
		}
	}))
	defer server.Close()
	service, err := Open(Config{Servers: []ServerConfig{{ID: "local", Endpoint: server.URL}}})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	ctx := context.Background()
	tools, err := service.ToolList(ctx, "local")
	if err != nil {
		t.Fatalf("ToolList() error = %v", err)
	}
	if len(tools) != 1 || tools[0].Name != "echo" {
		t.Fatalf("tools = %#v, want echo", tools)
	}
	result, err := service.Call(ctx, ToolCallRequest{ServerID: "local", Tool: "echo"})
	if err != nil {
		t.Fatalf("Call() error = %v", err)
	}
	if result["ok"] != true {
		t.Fatalf("Call() = %#v, want structured content", result)
	}
}

// TestCallReturnsErrorForToolResultError verifies MCP isError results fail calls.
func TestCallReturnsErrorForToolResultError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"result": map[string]any{
			"isError":           true,
			"structuredContent": map[string]any{"error": "downstream failed"},
		}})
	}))
	defer server.Close()
	service, err := Open(Config{Servers: []ServerConfig{{ID: "local", Endpoint: server.URL}}})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	_, err = service.Call(context.Background(), ToolCallRequest{ServerID: "local", Tool: "fail"})
	if err == nil || !strings.Contains(err.Error(), "downstream failed") {
		t.Fatalf("Call() error = %v, want downstream failure", err)
	}
}

// TestStatusProbesEndpointHealth verifies configured endpoints must respond to be healthy.
func TestStatusProbesEndpointHealth(t *testing.T) {
	healthyServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if body["method"] != "initialize" {
			http.Error(w, "unexpected method", http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]any{"result": map[string]any{"protocolVersion": "2024-11-05"}})
	}))
	defer healthyServer.Close()
	downServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "closed", http.StatusServiceUnavailable)
	}))
	downURL := downServer.URL
	downServer.Close()
	service, err := Open(Config{
		RequestTimeout: time.Second,
		Servers: []ServerConfig{
			{ID: "healthy", Endpoint: healthyServer.URL},
			{ID: "down", Endpoint: downURL},
		},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	if status := service.Status(context.Background(), "healthy"); !status.Healthy {
		t.Fatalf("healthy status = %#v, want healthy", status)
	}
	if status := service.Status(context.Background(), "down"); status.Healthy {
		t.Fatalf("down status = %#v, want unhealthy", status)
	}
}

// TestStartStopSupervisesLocalProcess verifies configured local processes are managed.
func TestStartStopSupervisesLocalProcess(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell lifecycle test uses POSIX sleep")
	}
	service, err := Open(Config{Servers: []ServerConfig{{
		ID:        "sleep",
		Command:   "sh",
		Arguments: []string{"-c", "sleep 30"},
	}}})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	ctx := context.Background()
	status, err := service.Start(ctx, "sleep")
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	if status.State != stateRunning || status.PID == 0 {
		t.Fatalf("Start() = %#v, want running pid", status)
	}
	status, err = service.Stop(ctx, "sleep")
	if err != nil {
		t.Fatalf("Stop() error = %v", err)
	}
	deadline := time.Now().Add(time.Second)
	for status.State == stateRunning && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
		status = service.Status(ctx, "sleep")
	}
	if status.State == stateRunning {
		t.Fatalf("Status() = %#v, want stopped or exited", status)
	}
}

// writeJSON writes a JSON test response.
func writeJSON(w http.ResponseWriter, body map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(body)
}
