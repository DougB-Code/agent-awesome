package supervisor

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"sync"
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
	Name    string `json:"name"`
	URL     string `json:"url"`
	State   string `json:"state"`
	Message string `json:"message"`
	PID     int    `json:"pid,omitempty"`
}

// Manager owns dependency processes started by this gateway instance.
type Manager struct {
	client       *http.Client
	startTimeout time.Duration
	mu           sync.Mutex
	processes    map[string]*exec.Cmd
	statuses     map[string]Status
}

// New creates a local service manager.
func New(startTimeout time.Duration) *Manager {
	if startTimeout <= 0 {
		startTimeout = 30 * time.Second
	}
	return &Manager{
		client:       &http.Client{Timeout: 2 * time.Second},
		startTimeout: startTimeout,
		processes:    make(map[string]*exec.Cmd),
		statuses:     make(map[string]Status),
	}
}

// Ensure verifies a dependency and starts it when configured.
func (m *Manager) Ensure(ctx context.Context, service Service) Status {
	if service.HealthURL != "" && m.isHealthy(ctx, service.HealthURL) {
		return m.remember(Status{Name: service.Name, URL: service.HealthURL, State: "connected", Message: "already running"})
	}
	if !service.AutoStart {
		return m.remember(Status{Name: service.Name, URL: service.HealthURL, State: "disconnected", Message: "external service is not reachable"})
	}
	cmd, err := m.start(ctx, service)
	if err != nil {
		return m.remember(Status{Name: service.Name, URL: service.HealthURL, State: "disconnected", Message: "startup failed: " + err.Error()})
	}
	status := m.waitForHealth(ctx, service, cmd)
	return m.remember(status)
}

// Statuses returns the latest known dependency statuses.
func (m *Manager) Statuses() []Status {
	m.mu.Lock()
	defer m.mu.Unlock()
	statuses := make([]Status, 0, len(m.statuses))
	for _, status := range m.statuses {
		statuses = append(statuses, status)
	}
	return statuses
}

// Close terminates only processes started by this manager.
func (m *Manager) Close(ctx context.Context) error {
	m.mu.Lock()
	processes := make([]*exec.Cmd, 0, len(m.processes))
	for _, cmd := range m.processes {
		processes = append(processes, cmd)
	}
	m.mu.Unlock()

	for _, cmd := range processes {
		if cmd.Process == nil {
			continue
		}
		_ = cmd.Process.Signal(os.Interrupt)
	}
	done := make(chan struct{})
	go func() {
		for _, cmd := range processes {
			_ = cmd.Wait()
		}
		close(done)
	}()
	select {
	case <-ctx.Done():
		for _, cmd := range processes {
			if cmd.Process != nil {
				_ = cmd.Process.Kill()
			}
		}
		return ctx.Err()
	case <-done:
		return nil
	}
}

// start launches one configured local service command.
func (m *Manager) start(ctx context.Context, service Service) (*exec.Cmd, error) {
	if service.Command == "" {
		return nil, fmt.Errorf("command is required")
	}
	cmd := exec.CommandContext(ctx, service.Command, service.Arguments...)
	cmd.Dir = service.WorkingDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	m.mu.Lock()
	m.processes[service.Name] = cmd
	m.mu.Unlock()
	return cmd, nil
}

// waitForHealth waits until a started process is healthy or exits.
func (m *Manager) waitForHealth(ctx context.Context, service Service, cmd *exec.Cmd) Status {
	deadline, cancel := context.WithTimeout(ctx, m.startTimeout)
	defer cancel()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-deadline.Done():
			return Status{Name: service.Name, URL: service.HealthURL, State: "disconnected", Message: "startup timed out", PID: cmd.Process.Pid}
		case <-ticker.C:
			if service.HealthURL != "" && m.isHealthy(deadline, service.HealthURL) {
				return Status{Name: service.Name, URL: service.HealthURL, State: "connected", Message: "started", PID: cmd.Process.Pid}
			}
		}
	}
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
