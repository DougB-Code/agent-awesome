// This file tests the Launchpad queue worker HTTP flow.
package queueworker

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// TestRunOnceProcessesQueuedLaunchRun verifies a worker leases, starts, waits, and releases one item.
func TestRunOnceProcessesQueuedLaunchRun(t *testing.T) {
	var released bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Fatalf("Authorization header = %q, want bearer token", r.Header.Get("Authorization"))
		}
		switch r.URL.Path {
		case "/api/launchpad/queue/recover":
			writeTestJSON(t, w, map[string]any{"recovered": 1})
		case "/api/launchpad/queue/enqueue-due":
			writeTestJSON(t, w, map[string]any{"schedule": map[string]any{
				"enqueued": []map[string]any{{"id": "queue-1"}},
				"skipped":  []map[string]any{},
			}})
		case "/api/launchpad/queue/lease":
			writeTestJSON(t, w, map[string]any{"lease": map[string]any{
				"lease_id": "lease-1",
				"item":     map[string]any{"id": "queue-1", "status": "leased"},
			}})
		case "/api/launchpad/queue/queue-1/start":
			writeTestJSON(t, w, map[string]any{"launch_run": map[string]any{
				"run":  map[string]any{"id": "run-1", "status": "running"},
				"item": map[string]any{"id": "queue-1", "status": "running"},
			}})
		case "/api/runbooks/runs/run-1":
			writeTestJSON(t, w, map[string]any{"run": map[string]any{"id": "run-1", "status": "succeeded"}})
		case "/api/launchpad/queue/queue-1/release":
			var req releaseRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("Decode() error = %v", err)
			}
			if req.Status != "completed" || req.RunID != "run-1" {
				t.Fatalf("release request = %#v, want completed run", req)
			}
			released = true
			writeTestJSON(t, w, map[string]any{"queued_run": map[string]any{"id": "queue-1", "status": "completed"}})
		default:
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()

	result, err := RunOnce(context.Background(), Config{
		BaseURL:        server.URL + "/api",
		AuthToken:      "test-token",
		TargetID:       "this_computer",
		PollInterval:   time.Millisecond,
		RunTimeout:     time.Second,
		EnqueueDue:     true,
		RecoverExpired: true,
	})
	if err != nil {
		t.Fatalf("RunOnce() error = %v", err)
	}
	if !released || result.QueueStatus != "completed" || result.RunID != "run-1" || result.Recovered != 1 || result.Enqueued != 1 {
		t.Fatalf("result = %#v released=%v, want completed run summary", result, released)
	}
}

// TestRunOnceNoWorkTreatsEmptyLeaseAsIdle verifies empty queues are not errors.
func TestRunOnceNoWorkTreatsEmptyLeaseAsIdle(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/launchpad/queue/lease":
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "sql: no rows in result set"})
		default:
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
	}))
	defer server.Close()

	result, err := RunOnce(context.Background(), Config{
		BaseURL:        server.URL + "/api",
		TargetID:       "this_computer",
		EnqueueDue:     false,
		RecoverExpired: false,
	})
	if err != nil {
		t.Fatalf("RunOnce() error = %v", err)
	}
	if !result.NoWork {
		t.Fatalf("result = %#v, want no work", result)
	}
}

// writeTestJSON writes one test response body.
func writeTestJSON(t *testing.T, w http.ResponseWriter, body any) {
	t.Helper()
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(body); err != nil {
		t.Fatalf("Encode() error = %v", err)
	}
}
