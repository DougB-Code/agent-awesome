// This file implements local MCP server lifecycle and invocation management.
package mcp

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	stateStopped   = "stopped"
	stateRunning   = "running"
	stateExited    = "exited"
	stateUnmanaged = "unmanaged"

	healthCheckTimeout = 2 * time.Second
)

// Config stores local MCP server manager settings.
type Config struct {
	Servers        []ServerConfig
	RequestTimeout time.Duration
}

// ServerConfig stores one configured MCP server endpoint or local process.
type ServerConfig struct {
	ID         string            `json:"id"`
	Name       string            `json:"name,omitempty"`
	Endpoint   string            `json:"endpoint,omitempty"`
	HealthURL  string            `json:"health_url,omitempty"`
	Command    string            `json:"command,omitempty"`
	Arguments  []string          `json:"arguments,omitempty"`
	WorkingDir string            `json:"working_directory,omitempty"`
	Env        map[string]string `json:"env,omitempty"`
	AutoStart  bool              `json:"auto_start,omitempty"`
}

// ServerStatus reports observable state for one configured server.
type ServerStatus struct {
	ID        string `json:"id"`
	Name      string `json:"name,omitempty"`
	Endpoint  string `json:"endpoint,omitempty"`
	HealthURL string `json:"health_url,omitempty"`
	State     string `json:"state"`
	PID       int    `json:"pid,omitempty"`
	StartedAt string `json:"started_at,omitempty"`
	EndedAt   string `json:"ended_at,omitempty"`
	Error     string `json:"error,omitempty"`
	Healthy   bool   `json:"healthy"`
}

// ToolDescriptor describes one MCP tool returned by tools/list.
type ToolDescriptor struct {
	Name        string         `json:"name"`
	Description string         `json:"description,omitempty"`
	InputSchema map[string]any `json:"inputSchema,omitempty"`
}

// ToolCallRequest describes one managed MCP tool call.
type ToolCallRequest struct {
	ServerID  string         `json:"server_id"`
	Tool      string         `json:"tool"`
	Arguments map[string]any `json:"arguments,omitempty"`
}

// Service owns configured MCP server state.
type Service struct {
	cfg     Config
	servers map[string]ServerConfig
	client  *http.Client
	mu      sync.Mutex
	procs   map[string]*processState
	nextID  int64
}

// Open validates configuration and creates an MCP manager.
func Open(cfg Config) (*Service, error) {
	if cfg.RequestTimeout <= 0 {
		cfg.RequestTimeout = 10 * time.Minute
	}
	servers := map[string]ServerConfig{}
	for _, server := range cfg.Servers {
		id := strings.TrimSpace(server.ID)
		if id == "" {
			return nil, fmt.Errorf("MCP server id is required")
		}
		if _, exists := servers[id]; exists {
			return nil, fmt.Errorf("duplicate MCP server %q", id)
		}
		if strings.TrimSpace(server.Endpoint) == "" && strings.TrimSpace(server.Command) == "" {
			return nil, fmt.Errorf("MCP server %q requires endpoint or command", id)
		}
		servers[id] = server
	}
	return &Service{
		cfg:     cfg,
		servers: servers,
		client:  &http.Client{Timeout: cfg.RequestTimeout},
		procs:   map[string]*processState{},
	}, nil
}

// AutoStart starts every configured server that opts into local supervision.
func (s *Service) AutoStart(ctx context.Context) error {
	for _, server := range s.cfg.Servers {
		if server.AutoStart && strings.TrimSpace(server.Command) != "" {
			if _, err := s.Start(ctx, server.ID); err != nil {
				return err
			}
		}
	}
	return nil
}

// Servers returns server statuses in stable order.
func (s *Service) Servers(ctx context.Context) []ServerStatus {
	statuses := make([]ServerStatus, 0, len(s.cfg.Servers))
	for _, server := range s.cfg.Servers {
		statuses = append(statuses, s.Status(ctx, server.ID))
	}
	sort.Slice(statuses, func(i, j int) bool {
		return statuses[i].ID < statuses[j].ID
	})
	return statuses
}

// Status returns status for one configured server.
func (s *Service) Status(ctx context.Context, id string) ServerStatus {
	server, ok := s.server(id)
	if !ok {
		return ServerStatus{ID: strings.TrimSpace(id), State: stateStopped, Error: "MCP server is not configured"}
	}
	status := ServerStatus{
		ID:        server.ID,
		Name:      server.Name,
		Endpoint:  server.Endpoint,
		HealthURL: server.HealthURL,
		State:     stateUnmanaged,
		Healthy:   s.healthy(ctx, server),
	}
	if strings.TrimSpace(server.Command) == "" {
		return status
	}
	s.mu.Lock()
	process := s.procs[server.ID]
	s.mu.Unlock()
	if process == nil {
		status.State = stateStopped
		return status
	}
	status.State = process.state
	status.PID = process.pid
	status.StartedAt = process.startedAt
	status.EndedAt = process.endedAt
	status.Error = process.err
	return status
}

// Start launches a configured local MCP server process.
func (s *Service) Start(ctx context.Context, id string) (ServerStatus, error) {
	server, ok := s.server(id)
	if !ok {
		return ServerStatus{}, fmt.Errorf("MCP server %q is not configured", id)
	}
	if strings.TrimSpace(server.Command) == "" {
		return ServerStatus{}, fmt.Errorf("MCP server %q has no local command", id)
	}
	s.mu.Lock()
	if current := s.procs[server.ID]; current != nil && current.state == stateRunning {
		s.mu.Unlock()
		return s.Status(ctx, server.ID), nil
	}
	s.mu.Unlock()
	workdir, err := resolveWorkdir(server.WorkingDir)
	if err != nil {
		return ServerStatus{}, err
	}
	runCtx, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(runCtx, server.Command, server.Arguments...)
	cmd.Dir = workdir
	cmd.Env = processEnv(server.Env)
	configureProcess(cmd)
	if err := cmd.Start(); err != nil {
		cancel()
		return ServerStatus{}, fmt.Errorf("start MCP server %q: %w", server.ID, err)
	}
	state := &processState{
		cancel:    cancel,
		cmd:       cmd,
		state:     stateRunning,
		pid:       cmd.Process.Pid,
		startedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	s.mu.Lock()
	s.procs[server.ID] = state
	s.mu.Unlock()
	go s.waitProcess(server.ID, cmd, state)
	return s.Status(ctx, server.ID), nil
}

// Stop terminates a supervised MCP server process.
func (s *Service) Stop(ctx context.Context, id string) (ServerStatus, error) {
	server, ok := s.server(id)
	if !ok {
		return ServerStatus{}, fmt.Errorf("MCP server %q is not configured", id)
	}
	s.mu.Lock()
	process := s.procs[server.ID]
	s.mu.Unlock()
	if process == nil {
		return s.Status(ctx, server.ID), nil
	}
	terminateProcess(process.cmd)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		status := s.Status(ctx, server.ID)
		if status.State != stateRunning {
			return status, nil
		}
		time.Sleep(10 * time.Millisecond)
	}
	killProcess(process.cmd)
	process.cancel()
	return s.Status(ctx, server.ID), nil
}

// Restart stops and starts one supervised MCP server.
func (s *Service) Restart(ctx context.Context, id string) (ServerStatus, error) {
	if _, err := s.Stop(ctx, id); err != nil {
		return ServerStatus{}, err
	}
	return s.Start(ctx, id)
}

// ToolList returns tools exposed by one configured MCP endpoint.
func (s *Service) ToolList(ctx context.Context, id string) ([]ToolDescriptor, error) {
	server, ok := s.server(id)
	if !ok {
		return nil, fmt.Errorf("MCP server %q is not configured", id)
	}
	var decoded struct {
		Tools []ToolDescriptor `json:"tools"`
	}
	if err := s.rpc(ctx, server.Endpoint, "tools/list", nil, &decoded); err != nil {
		return nil, err
	}
	return decoded.Tools, nil
}

// Call invokes one tool on a configured MCP endpoint.
func (s *Service) Call(ctx context.Context, req ToolCallRequest) (map[string]any, error) {
	server, ok := s.server(req.ServerID)
	if !ok {
		return nil, fmt.Errorf("MCP server %q is not configured", req.ServerID)
	}
	if strings.TrimSpace(req.Tool) == "" {
		return nil, fmt.Errorf("MCP tool is required")
	}
	var result map[string]any
	if err := s.rpc(ctx, server.Endpoint, "tools/call", map[string]any{
		"name":      strings.TrimSpace(req.Tool),
		"arguments": nilMap(req.Arguments),
	}, &result); err != nil {
		return nil, err
	}
	if err := toolResultError(server.ID, req.Tool, result); err != nil {
		return nil, err
	}
	if structured, ok := result["structuredContent"].(map[string]any); ok {
		return structured, nil
	}
	return result, nil
}

// server returns a configured server by id.
func (s *Service) server(id string) (ServerConfig, bool) {
	server, ok := s.servers[strings.TrimSpace(id)]
	return server, ok
}

// healthy reports whether a configured health endpoint responds successfully.
func (s *Service) healthy(ctx context.Context, server ServerConfig) bool {
	healthURL := strings.TrimSpace(server.HealthURL)
	healthCtx, cancel := context.WithTimeout(ctx, healthCheckTimeout)
	defer cancel()
	if healthURL != "" {
		req, err := http.NewRequestWithContext(healthCtx, http.MethodGet, healthURL, nil)
		if err != nil {
			return false
		}
		resp, err := s.client.Do(req)
		if err != nil {
			return false
		}
		defer resp.Body.Close()
		return resp.StatusCode >= 200 && resp.StatusCode < 300
	}
	endpoint := strings.TrimSpace(server.Endpoint)
	if endpoint == "" {
		return false
	}
	var decoded map[string]any
	err := s.rpc(healthCtx, endpoint, "initialize", map[string]any{
		"protocolVersion": "2024-11-05",
		"capabilities":    map[string]any{},
		"clientInfo": map[string]any{
			"name":    "agent-awesome-mcpd",
			"version": "dev",
		},
	}, &decoded)
	if err != nil {
		return false
	}
	return true
}

// rpc sends one JSON-RPC request to an MCP endpoint.
func (s *Service) rpc(ctx context.Context, endpoint string, method string, params any, target any) error {
	trimmed := strings.TrimSpace(endpoint)
	if trimmed == "" {
		return fmt.Errorf("MCP endpoint is required")
	}
	s.mu.Lock()
	s.nextID++
	id := s.nextID
	s.mu.Unlock()
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"method":  method,
		"params":  params,
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, trimmed, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("call MCP endpoint: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return fmt.Errorf("read MCP response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("MCP HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	var decoded rpcResponse
	if err := json.Unmarshal(data, &decoded); err != nil {
		return fmt.Errorf("decode MCP response: %w", err)
	}
	if decoded.Error != nil {
		return fmt.Errorf("MCP error: %s", decoded.Error.Message)
	}
	if target == nil {
		return nil
	}
	encoded, err := json.Marshal(decoded.Result)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, target)
}

// waitProcess records process exit state for one supervised server.
func (s *Service) waitProcess(id string, cmd *exec.Cmd, state *processState) {
	err := cmd.Wait()
	s.mu.Lock()
	defer s.mu.Unlock()
	current := s.procs[id]
	if current != state {
		return
	}
	state.state = stateExited
	state.endedAt = time.Now().UTC().Format(time.RFC3339Nano)
	if err != nil {
		state.err = err.Error()
	}
}

// resolveWorkdir resolves an optional process working directory.
func resolveWorkdir(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	abs, err := filepath.Abs(value)
	if err != nil {
		return "", fmt.Errorf("resolve working directory: %w", err)
	}
	return filepath.Clean(abs), nil
}

// processEnv returns inherited environment plus configured overrides.
func processEnv(extra map[string]string) []string {
	env := os.Environ()
	for key, value := range extra {
		env = append(env, key+"="+value)
	}
	return env
}

// nilMap returns an empty argument map when callers omit arguments.
func nilMap(value map[string]any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	return value
}

// toolResultError converts MCP tool-result errors into manager call errors.
func toolResultError(serverID string, toolName string, result map[string]any) error {
	isError, _ := result["isError"].(bool)
	if !isError {
		return nil
	}
	return fmt.Errorf("MCP tool %s on server %s failed: %s", strings.TrimSpace(toolName), strings.TrimSpace(serverID), toolErrorText(result))
}

// toolErrorText extracts a useful message from an MCP error tool result.
func toolErrorText(result map[string]any) string {
	if structured, ok := result["structuredContent"].(map[string]any); ok {
		if message, ok := structured["error"].(string); ok && strings.TrimSpace(message) != "" {
			return strings.TrimSpace(message)
		}
		if data, err := json.Marshal(structured); err == nil && len(data) > 0 {
			return string(data)
		}
	}
	if content, ok := result["content"].([]any); ok {
		for _, item := range content {
			itemMap, _ := item.(map[string]any)
			text, _ := itemMap["text"].(string)
			if strings.TrimSpace(text) != "" {
				return strings.TrimSpace(text)
			}
		}
	}
	return "tool returned isError=true"
}

// processState stores mutable supervised process state.
type processState struct {
	cancel    context.CancelFunc
	cmd       *exec.Cmd
	state     string
	pid       int
	startedAt string
	endedAt   string
	err       string
}

// rpcResponse stores one JSON-RPC response from an MCP endpoint.
type rpcResponse struct {
	Result any       `json:"result,omitempty"`
	Error  *rpcError `json:"error,omitempty"`
}

// rpcError stores one JSON-RPC error.
type rpcError struct {
	Message string `json:"message"`
}
