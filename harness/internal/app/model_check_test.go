// This file tests model smoke-check orchestration.
package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// TestCheckModelSendsPromptThroughSelectedProvider verifies model ID smoke checks.
func TestCheckModelSendsPromptThroughSelectedProvider(t *testing.T) {
	var decoded struct {
		Model string `json:"model"`
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&decoded); err != nil {
			t.Fatalf("Decode() error = %v", err)
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"ok"}}]}`))
	}))
	defer server.Close()
	modelPath := writeModelCheckFile(t, `
default: local:mock
providers:
  local:
    adapter: openai
    auth: optional
    url: `+server.URL+`
    models:
      - id: mock
        model: mock-model
`)

	result, err := CheckModel(context.Background(), ModelCheckOptions{
		ModelConfigPath: modelPath,
		Prompt:          "ping",
	})
	if err != nil {
		t.Fatalf("CheckModel() error = %v", err)
	}
	if decoded.Model != "mock-model" {
		t.Fatalf("request model = %q, want mock-model", decoded.Model)
	}
	if result.ProviderName != "local" || result.ModelID != "mock" || result.ResponseText != "ok" {
		t.Fatalf("CheckModel() result = %#v, want local mock ok", result)
	}
}

// writeModelCheckFile writes a temporary model config for smoke-check tests.
func writeModelCheckFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "model.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	return path
}
