// This file tests Capability Registry HTTP routes.
package capabilities

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"agentawesome/internal/config/schema"
)

// TestHTTPServerListsAndReturnsCapabilities verifies the REST adapter shape.
func TestHTTPServerListsAndReturnsCapabilities(t *testing.T) {
	registry := NewRegistry(testToolsConfig(true), schema.Agent{Name: "AA", Instruction: "Work."})
	server := httptest.NewServer(NewHTTPServer(registry).Routes())
	defer server.Close()

	resp, err := http.Get(server.URL + "/api/capabilities?kind=command&usable_in_workflows=true")
	if err != nil {
		t.Fatalf("GET capabilities error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("list status = %d, want 200", resp.StatusCode)
	}
	var listed struct {
		Capabilities []Capability `json:"capabilities"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&listed); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(listed.Capabilities) != 1 || listed.Capabilities[0].ID != "command:lint" {
		t.Fatalf("listed capabilities = %#v, want command:lint only", listed.Capabilities)
	}

	resp, err = http.Get(server.URL + "/api/capabilities/command:lint")
	if err != nil {
		t.Fatalf("GET capability error = %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("get status = %d, want 200", resp.StatusCode)
	}
	var got struct {
		Capability Capability `json:"capability"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode get: %v", err)
	}
	if got.Capability.ID != "command:lint" {
		t.Fatalf("capability id = %q, want command:lint", got.Capability.ID)
	}
}
