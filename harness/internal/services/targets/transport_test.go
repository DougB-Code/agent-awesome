// This file tests Runtime Target HTTP routes.
package targets

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

// TestHTTPServerServesTargets verifies target list, update, health, and logs.
func TestHTTPServerServesTargets(t *testing.T) {
	ctx := context.Background()
	store, err := OpenStore(ctx, filepath.Join(t.TempDir(), "targets.db"))
	if err != nil {
		t.Fatalf("OpenStore() error = %v", err)
	}
	defer store.Close()
	service := NewService(store)
	if _, err := service.RegisterLocalTarget(ctx, LocalRegistration{Version: "test"}); err != nil {
		t.Fatalf("RegisterLocalTarget() error = %v", err)
	}
	server := httptest.NewServer(NewHTTPServer(service).Routes())
	defer server.Close()

	listed := getJSON(t, server.URL+"/api/runtime-targets")
	targets := listed["targets"].([]any)
	if len(targets) != 1 {
		t.Fatalf("targets = %#v, want one local target", targets)
	}

	reqBody := []byte(`{"name":"Studio workstation","allowed_codebase_ids":["aa"]}`)
	req, err := http.NewRequest(http.MethodPut, server.URL+"/api/runtime-targets/local", bytes.NewReader(reqBody))
	if err != nil {
		t.Fatalf("NewRequest() error = %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PUT target error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("PUT status = %d, want 200", resp.StatusCode)
	}
	var updated map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&updated); err != nil {
		t.Fatalf("decode update: %v", err)
	}
	target := updated["target"].(map[string]any)
	if target["name"] != "Studio workstation" {
		t.Fatalf("updated target = %#v, want renamed target", target)
	}

	health := getJSON(t, server.URL+"/api/runtime-targets/local/health")
	if health["health"].(map[string]any)["status"] != TargetStatusHealthy {
		t.Fatalf("health = %#v, want healthy", health)
	}
	logs := getJSON(t, server.URL+"/api/runtime-targets/local/logs")
	if len(logs["logs"].([]any)) == 0 {
		t.Fatalf("logs = %#v, want log rows", logs)
	}

	tokenBody := []byte(`{"name":"Build laptop","kind":"lan","allowed_codebase_ids":["aa"],"expires_in_seconds":60}`)
	resp, err = http.Post(server.URL+"/api/runtime-targets/pairing-tokens", "application/json", bytes.NewReader(tokenBody))
	if err != nil {
		t.Fatalf("POST pairing token error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("pairing token status = %d, want 200", resp.StatusCode)
	}
	var pairedInvite map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&pairedInvite); err != nil {
		t.Fatalf("decode pairing token: %v", err)
	}
	invite := pairedInvite["pairing_token"].(map[string]any)
	registerBody, _ := json.Marshal(map[string]any{
		"token":    invite["token"],
		"version":  "test",
		"os":       "linux/amd64",
		"hostname": "build-laptop",
	})
	resp, err = http.Post(server.URL+"/api/runtime-targets/pair", "application/json", bytes.NewReader(registerBody))
	if err != nil {
		t.Fatalf("POST pair error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("pair status = %d, want 200", resp.StatusCode)
	}
}

// getJSON reads a JSON object from a GET response.
func getJSON(t *testing.T, url string) map[string]any {
	t.Helper()
	resp, err := http.Get(url)
	if err != nil {
		t.Fatalf("GET %s error = %v", url, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET %s status = %d, want 200", url, resp.StatusCode)
	}
	var decoded map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		t.Fatalf("decode %s: %v", url, err)
	}
	return decoded
}
