// This file supervises optional local dependency processes for the gateway.
package supervisor

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"sync"
	"syscall"
	"time"
)

// Service describes one local dependency that can be checked or started.
type Service struct {
	Name       string
	HealthURL  string
	Command    string
	Arguments  []string
	WorkingDir string
	AutoStart  bool
}

// Status reports current readiness and process ownership for one dependency.
type Status struct {
	Name      string    `json:"name"`
	URL       string    `json:"url"`
	State     string    `json:"state"`
	Message   string    `json:"message"`
	PID       int       `json:"pid,omitempty"`
	StartedAt time.Time `json:"started_at"`
	UpdatedAt time.Time `json:"updated_at"`
	ElapsedMS int64     `json:"elapsed_ms"`
}

// Manager owns dependency processes started by this gateway instance.
type Manager struct {
	client       *http.Client
	startTimeout time.Duration
	mu           sync.Mutex
	processes    map[string]processHandle
	statuses     map[string]Status
}

// processHandle tracks one started process and its single wait result.
type processHandle struct {
	command *exec.Cmd
	done    <-chan struct{}
	result  *processResult
}

// processResult stores the single process wait result for multiple readers.
type processResult struct {
	mu  sync.Mutex
	err error
}

const startupTerminationTimeout = 2 * time.Second

const (
	// StateChecking means a dependency readiness check is in progress.
	StateChecking = "checking"
	// StateConnected means a dependency is reachable and ready.
	StateConnected = "connected"
	// StateDisconnected means a dependency is not reachable.
	StateDisconnected = "disconnected"
	// StateStarting means a managed dependency process is starting.
	StateStarting = "starting"
	// StateFailedStartup means a managed dependency failed to become ready.
	StateFailedStartup = "failed_startup"
)

// New creates a local service manager.
func New(startTimeout time.Duration) *Manager {
	if startTimeout <= 0 {
		startTimeout = 30 * time.Second
	}
	return &Manager{
		client:       &http.Client{Timeout: 2 * time.Second},
		startTimeout: startTimeout,
		processes:    make(map[string]processHandle),
		statuses:     make(map[string]Status),
	}
}

// Expect records dependencies that should become ready during startup.
func (m *Manager) Expect(services ...Service) {
	startedAt := time.Now().UTC()
	for _, service := range services {
		if service.Name == "" {
			continue
		}
		m.remember(newStatus(service, StateChecking, "waiting for dependency startup", 0, startedAt))
	}
}

// Ensure verifies a dependency and starts it when configured.
func (m *Manager) Ensure(ctx context.Context, service Service) Status {
	startedAt := time.Now().UTC()
	m.remember(newStatus(service, StateChecking, "checking health", 0, startedAt))
	if service.HealthURL != "" && m.isHealthy(ctx, service.HealthURL) {
		return m.remember(newStatus(service, StateConnected, "already running", 0, startedAt))
	}
	if !service.AutoStart {
		return m.remember(newStatus(service, StateDisconnected, "external service is not reachable", 0, startedAt))
	}
	process, err := m.start(ctx, service)
	if err != nil {
		return m.remember(newStatus(service, StateDisconnected, "startup failed: "+err.Error(), 0, startedAt))
	}
	m.remember(newStatus(service, StateStarting, "process started; waiting for health", process.command.Process.Pid, startedAt))
	status := m.waitForHealth(ctx, service, process, startedAt)
	return m.remember(status)
}

// Statuses returns the latest known dependency statuses.
func (m *Manager) Statuses() []Status {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now().UTC()
	statuses := make([]Status, 0, len(m.statuses))
	for _, status := range m.statuses {
		if status.State == StateChecking || status.State == StateStarting {
			status.UpdatedAt = now
			status.ElapsedMS = elapsedMilliseconds(status.StartedAt, now)
		}
		statuses = append(statuses, status)
	}
	sort.Slice(statuses, func(i int, j int) bool {
		return statuses[i].Name < statuses[j].Name
	})
	return statuses
}

// Close terminates only processes started by this manager.
func (m *Manager) Close(ctx context.Context) error {
	m.mu.Lock()
	processes := make([]processHandle, 0, len(m.processes))
	for _, process := range m.processes {
		processes = append(processes, process)
	}
	m.mu.Unlock()

	for _, process := range processes {
		if process.command.Process == nil {
			continue
		}
		select {
		case <-process.done:
			continue
		default:
			_ = signalProcess(process, os.Interrupt)
		}
	}
	done := make(chan struct{})
	go func() {
		for _, process := range processes {
			<-process.done
		}
		close(done)
	}()
	select {
	case <-ctx.Done():
		for _, process := range processes {
			if process.command.Process != nil {
				_ = signalProcess(process, os.Kill)
			}
		}
		return ctx.Err()
	case <-done:
		return nil
	}
}

// start launches one configured local service command.
func (m *Manager) start(ctx context.Context, service Service) (processHandle, error) {
	if service.Command == "" {
		return processHandle{}, fmt.Errorf("command is required")
	}
	cmd := exec.CommandContext(ctx, service.Command, service.Arguments...)
	cmd.Dir = service.WorkingDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return processHandle{}, err
	}
	process := newProcessHandle(cmd)
	m.mu.Lock()
	m.processes[service.Name] = process
	m.mu.Unlock()
	return process, nil
}

// waitForHealth waits until a started process is healthy or exits.
func (m *Manager) waitForHealth(ctx context.Context, service Service, process processHandle, startedAt time.Time) Status {
	deadline, cancel := context.WithTimeout(ctx, m.startTimeout)
	defer cancel()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-process.done:
			m.forgetProcess(service.Name)
			return newStatus(service, StateDisconnected, processExitMessage(process.err()), process.command.Process.Pid, startedAt)
		case <-deadline.Done():
			reason := "startup timed out"
			if deadline.Err() == context.Canceled {
				reason = "startup canceled"
			}
			message := m.terminateFailedStartup(service.Name, process, reason)
			return newStatus(service, StateFailedStartup, message, process.command.Process.Pid, startedAt)
		case <-ticker.C:
			if service.HealthURL != "" && m.isHealthy(deadline, service.HealthURL) {
				return newStatus(service, StateConnected, "started", process.command.Process.Pid, startedAt)
			}
		}
	}
}

// terminateFailedStartup stops an unhealthy startup process and forgets ownership.
func (m *Manager) terminateFailedStartup(name string, process processHandle, reason string) string {
	if process.command.Process == nil {
		m.forgetProcess(name)
		return reason + "; process missing"
	}
	_ = signalProcess(process, os.Interrupt)
	select {
	case <-process.done:
		m.forgetProcess(name)
		return reason + "; process terminated"
	case <-time.After(startupTerminationTimeout):
		_ = signalProcess(process, os.Kill)
		<-process.done
		m.forgetProcess(name)
		return reason + "; process killed"
	}
}

// newProcessHandle starts the one goroutine allowed to wait on a process.
func newProcessHandle(cmd *exec.Cmd) processHandle {
	done := make(chan struct{})
	result := &processResult{}
	go func() {
		result.set(cmd.Wait())
		close(done)
	}()
	return processHandle{command: cmd, done: done, result: result}
}

// signalProcess sends a signal to the child process group when available.
func signalProcess(process processHandle, signal os.Signal) error {
	if process.command.Process == nil {
		return nil
	}
	pid := process.command.Process.Pid
	if pid > 0 {
		if typed, ok := signal.(syscall.Signal); ok {
			if err := syscall.Kill(-pid, typed); err == nil {
				return nil
			}
		}
	}
	return process.command.Process.Signal(signal)
}

// err returns the stored wait result after process completion.
func (p processHandle) err() error {
	p.result.mu.Lock()
	defer p.result.mu.Unlock()
	return p.result.err
}

// set records the process wait result before waiters observe completion.
func (r *processResult) set(err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.err = err
}

// processExitMessage describes a child process exit without exposing internals.
func processExitMessage(err error) string {
	if err == nil {
		return "process exited before health"
	}
	exitErr, ok := err.(*exec.ExitError)
	if !ok {
		return "process exited before health: " + err.Error()
	}
	status, ok := exitErr.Sys().(syscall.WaitStatus)
	if !ok {
		return "process exited before health: " + err.Error()
	}
	if status.Signaled() {
		return fmt.Sprintf("process exited before health: signal %s", status.Signal())
	}
	return fmt.Sprintf("process exited before health: exit code %d", status.ExitStatus())
}

// isHealthy reports whether one dependency health endpoint is reachable.
func (m *Manager) isHealthy(ctx context.Context, healthURL string) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, healthURL, nil)
	if err != nil {
		return false
	}
	resp, err := m.client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}

// remember stores and returns the latest status for one service.
func (m *Manager) remember(status Status) Status {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.statuses[status.Name] = status
	return status
}

// forgetProcess removes process ownership once the child has exited.
func (m *Manager) forgetProcess(name string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.processes, name)
}

// newStatus builds one timestamped dependency status snapshot.
func newStatus(service Service, state string, message string, pid int, startedAt time.Time) Status {
	now := time.Now().UTC()
	return Status{
		Name:      service.Name,
		URL:       service.HealthURL,
		State:     state,
		Message:   message,
		PID:       pid,
		StartedAt: startedAt,
		UpdatedAt: now,
		ElapsedMS: elapsedMilliseconds(startedAt, now),
	}
}

// elapsedMilliseconds returns a non-negative millisecond duration.
func elapsedMilliseconds(startedAt time.Time, now time.Time) int64 {
	if startedAt.IsZero() || now.Before(startedAt) {
		return 0
	}
	return now.Sub(startedAt).Milliseconds()
}
