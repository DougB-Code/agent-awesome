// This file tests workflow-to-harness agent handoffs.
package runtime

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"workflow/internal/actions"
)

// TestAgentClientRunReportsHarnessOwnedValidation verifies agent.run metadata.
func TestAgentClientRunReportsHarnessOwnedValidation(t *testing.T) {
	harness := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/apps/agent/users/user/sessions":
			w.WriteHeader(http.StatusOK)
		case "/api/run_sse":
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = w.Write([]byte("data: {\"content\":{\"parts\":[{\"text\":\"{\\\"summary\\\":\\\"ok\\\"}\"}]}}\n\n"))
		default:
			t.Fatalf("unexpected harness path %q", r.URL.Path)
		}
	}))
	defer harness.Close()

	client := NewAgentClient(harness.URL+"/api", "agent", "user", time.Second)
	output, err := client.Run(context.Background(), actions.AgentRequest{
		RunID:        "run_1",
		StepID:       "triage",
		Instructions: "Summarize the input.",
		Input:        map[string]any{"subject": "hello"},
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if output["validation_status"] != "harness_owned" || output["parse_status"] != "valid_json" {
		t.Fatalf("output = %#v, want harness-owned parsed JSON", output)
	}
}
