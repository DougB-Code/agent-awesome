package supervisor

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// TestEnsureReportsStartingStatusWhileWaiting verifies startup timing is observable before health is ready.
func TestEnsureReportsStartingStatusWhileWaiting(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "not ready", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	manager := New(5 * time.Second)
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	defer func() {
		closeCtx, closeCancel := context.WithTimeout(context.Background(), time.Second)
		defer closeCancel()
		if err := manager.Close(closeCtx); err != nil && err != context.Canceled {
			t.Fatalf("Close() error = %v", err)
		}
	}()

	done := make(chan Status, 1)
	go func() {
		done <- manager.Ensure(ctx, Service{
			Name:      "slow-service",
			HealthURL: server.URL,
			AutoStart: true,
			Command:   "/bin/sh",
			Arguments: []string{"-c", "sleep 5"},
		})
	}()

	status := waitForServiceStatus(t, manager, "slow-service", "starting")
	if status.PID == 0 {
		t.Fatalf("starting status PID = 0, want process PID")
	}
	if status.StartedAt.IsZero() {
		t.Fatalf("starting status StartedAt is zero")
	}
	if status.UpdatedAt.Before(status.StartedAt) {
		t.Fatalf("UpdatedAt %s is before StartedAt %s", status.UpdatedAt, status.StartedAt)
	}
	if status.ElapsedMS < 0 {
		t.Fatalf("ElapsedMS = %d, want non-negative", status.ElapsedMS)
	}

	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatalf("Ensure() did not stop after cancellation")
	}
}

// TestEnsureReportsProcessExitBeforeHealth verifies failed children do not wait for timeout.
func TestEnsureReportsProcessExitBeforeHealth(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "not ready", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	manager := New(5 * time.Second)
	started := time.Now()
	status := manager.Ensure(t.Context(), Service{
		Name:      "failed-service",
		HealthURL: server.URL,
		AutoStart: true,
		Command:   "/bin/sh",
		Arguments: []string{"-c", "exit 7"},
	})

	if status.State != "disconnected" {
		t.Fatalf("State = %q, want disconnected", status.State)
	}
	if status.Message != "process exited before health: exit code 7" {
		t.Fatalf("Message = %q, want process exit message", status.Message)
	}
	if time.Since(started) > time.Second {
		t.Fatalf("Ensure() waited too long after process exit")
	}
}

// waitForServiceStatus polls manager statuses until the wanted service state is visible.
func waitForServiceStatus(t *testing.T, manager *Manager, name string, state string) Status {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		for _, status := range manager.Statuses() {
			if status.Name == name && status.State == state {
				return status
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("service %q did not reach state %q; statuses: %+v", name, state, manager.Statuses())
	return Status{}
}
