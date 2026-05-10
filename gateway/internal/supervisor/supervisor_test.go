// This file tests local dependency supervision behavior.
package supervisor

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
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

	status := waitForServiceStatus(t, manager, "slow-service", StateStarting)
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

	if status.State != StateDisconnected {
		t.Fatalf("State = %q, want disconnected", status.State)
	}
	if status.Message != "process exited before health: exit code 7" {
		t.Fatalf("Message = %q, want process exit message", status.Message)
	}
	if time.Since(started) > time.Second {
		t.Fatalf("Ensure() waited too long after process exit")
	}
}

// TestEnsureStartupTimeoutTerminatesProcess verifies unhealthy startups are killed.
func TestEnsureStartupTimeoutTerminatesProcess(t *testing.T) {
	server := unhealthyServer(t)
	manager := New(50 * time.Millisecond)
	status := manager.Ensure(t.Context(), Service{
		Name:      "hung-service",
		HealthURL: server.URL,
		AutoStart: true,
		Command:   commandPath(t, "sleep"),
		Arguments: []string{"5"},
	})

	if status.State != StateFailedStartup {
		t.Fatalf("State = %q, want failed_startup", status.State)
	}
	if !strings.Contains(status.Message, "startup timed out") || !strings.Contains(status.Message, "process") {
		t.Fatalf("Message = %q, want timeout termination reason", status.Message)
	}
	stored := statusByName(t, manager, "hung-service")
	if stored.State != StateFailedStartup || stored.Message != status.Message {
		t.Fatalf("stored status = %#v, want failed startup reason %q", stored, status.Message)
	}
	if status.PID == 0 {
		t.Fatalf("PID = 0, want timed-out process PID")
	}
	if processExists(status.PID) {
		t.Fatalf("process %d still exists after failed startup", status.PID)
	}
}

// TestCloseAfterFailedStartupDoesNotDoubleKill verifies shutdown ignores reaped children.
func TestCloseAfterFailedStartupDoesNotDoubleKill(t *testing.T) {
	server := unhealthyServer(t)
	manager := New(50 * time.Millisecond)
	status := manager.Ensure(t.Context(), Service{
		Name:      "failed-close-service",
		HealthURL: server.URL,
		AutoStart: true,
		Command:   commandPath(t, "sleep"),
		Arguments: []string{"5"},
	})
	if status.State != StateFailedStartup {
		t.Fatalf("State = %q, want failed_startup", status.State)
	}

	ctx, cancel := context.WithTimeout(t.Context(), time.Second)
	defer cancel()
	if err := manager.Close(ctx); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
}

// TestEnsureHealthyAlreadyRunningServiceIsNotStarted verifies healthy dependencies are left alone.
func TestEnsureHealthyAlreadyRunningServiceIsNotStarted(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	root := t.TempDir()
	marker := filepath.Join(root, "started")

	manager := New(time.Second)
	status := manager.Ensure(t.Context(), Service{
		Name:      "healthy-service",
		HealthURL: server.URL,
		AutoStart: true,
		Command:   "/bin/sh",
		Arguments: []string{"-c", "touch " + marker},
	})

	if status.State != StateConnected || status.PID != 0 {
		t.Fatalf("status = %#v, want already-running connected status without PID", status)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("marker stat = %v, want command not started", err)
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

// statusByName returns the last stored status for a service.
func statusByName(t *testing.T, manager *Manager, name string) Status {
	t.Helper()
	for _, status := range manager.Statuses() {
		if status.Name == name {
			return status
		}
	}
	t.Fatalf("status for %q was not recorded; statuses: %+v", name, manager.Statuses())
	return Status{}
}

// unhealthyServer returns a health endpoint that never becomes ready.
func unhealthyServer(t *testing.T) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "not ready", http.StatusServiceUnavailable)
	}))
	t.Cleanup(server.Close)
	return server
}

// commandPath returns a command path or fails the test.
func commandPath(t *testing.T, name string) string {
	t.Helper()
	path, err := exec.LookPath(name)
	if err != nil {
		t.Fatalf("lookup %s: %v", name, err)
	}
	return path
}

// processExists reports whether a PID is still visible to the OS.
func processExists(pid int) bool {
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}
