// This file tests the in-process workflow host surface.
package embedded

import (
	"context"
	"encoding/json"
	"net/http"
	"path/filepath"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/capabilities"
)

// TestStartServesHealth verifies embedded workflow exposes the HTTP routes.
func TestStartServesHealth(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	server, err := Start(ctx, Config{
		ListenAddress:         "127.0.0.1:0",
		DefinitionsDir:        filepath.Join(t.TempDir(), "workflows"),
		DatabasePath:          filepath.Join(t.TempDir(), "workflow.db"),
		HarnessContextBaseURL: "http://127.0.0.1:8081/api/context",
	})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), time.Second)
		defer shutdownCancel()
		_ = server.Close(shutdownCtx)
	}()

	resp, err := http.Get("http://" + server.http.Addr + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusOK)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode health body: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("status body = %#v, want ok", body)
	}
}

// TestStartServesCapabilities verifies embedded host mounts the registry boundary.
func TestStartServesCapabilities(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	server, err := Start(ctx, Config{
		ListenAddress:         "127.0.0.1:0",
		DefinitionsDir:        filepath.Join(t.TempDir(), "workflows"),
		DatabasePath:          filepath.Join(t.TempDir(), "workflow.db"),
		HarnessContextBaseURL: "http://127.0.0.1:8081/api/context",
		Capabilities: capabilities.NewRegistry(&schema.Tools{
			LocalExec: schema.LocalExec{
				Enabled: true,
				Commands: []schema.LocalExecCommand{{
					Name:       "lint",
					Executable: "go",
				}},
			},
		}, schema.Agent{Name: "AA", Instruction: "Work."}),
	})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	defer func() {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), time.Second)
		defer shutdownCancel()
		_ = server.Close(shutdownCtx)
	}()

	resp, err := http.Get("http://" + server.http.Addr + "/api/capabilities?kind=command")
	if err != nil {
		t.Fatalf("GET /api/capabilities error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusOK)
	}
	var body struct {
		Capabilities []capabilities.Capability `json:"capabilities"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("decode capabilities body: %v", err)
	}
	if len(body.Capabilities) != 1 || body.Capabilities[0].ID != "command:lint" {
		t.Fatalf("capabilities = %#v, want command:lint", body.Capabilities)
	}

	targetResp, err := http.Get("http://" + server.http.Addr + "/api/runtime-targets")
	if err != nil {
		t.Fatalf("GET /api/runtime-targets error = %v", err)
	}
	defer targetResp.Body.Close()
	if targetResp.StatusCode != http.StatusOK {
		t.Fatalf("target status = %d, want %d", targetResp.StatusCode, http.StatusOK)
	}
	var targetBody struct {
		Targets []struct {
			ID           string   `json:"id"`
			Name         string   `json:"name"`
			Capabilities []string `json:"capabilities"`
		} `json:"targets"`
	}
	if err := json.NewDecoder(targetResp.Body).Decode(&targetBody); err != nil {
		t.Fatalf("decode targets body: %v", err)
	}
	if len(targetBody.Targets) != 1 || targetBody.Targets[0].ID != "local" {
		t.Fatalf("targets = %#v, want local target", targetBody.Targets)
	}
	if len(targetBody.Targets[0].Capabilities) == 0 {
		t.Fatalf("local target capabilities = %#v, want inventory", targetBody.Targets[0].Capabilities)
	}
}
