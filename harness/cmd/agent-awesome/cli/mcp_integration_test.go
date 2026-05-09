package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestRunCommandWiresModelToolCallToMCPServer(t *testing.T) {
	var mcpCalls atomic.Int32
	mcpServer := mcp.NewServer(&mcp.Implementation{Name: "test-mcp", Version: "v1.0.0"}, nil)
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "city_time",
		Description: "Returns the time for a city.",
	}, func(ctx context.Context, req *mcp.CallToolRequest, input cityTimeInput) (*mcp.CallToolResult, cityTimeOutput, error) {
		mcpCalls.Add(1)
		return nil, cityTimeOutput{Summary: "time for " + input.City + " from MCP"}, nil
	})
	mcpHandler := mcp.NewStreamableHTTPHandler(func(r *http.Request) *mcp.Server {
		return mcpServer
	}, &mcp.StreamableHTTPOptions{JSONResponse: true, Stateless: true})
	mcpHTTPServer := httptest.NewServer(mcpHandler)
	t.Cleanup(mcpHTTPServer.Close)

	model := newMockOpenAIModelServer(t)
	defer model.Close()

	dir := t.TempDir()
	modelPath := writeTestFile(t, dir, "model.yaml", fmt.Sprintf(`
default: mock:test
providers:
  mock:
    adapter: openai
    auth: optional
    url: %s
    models:
      - id: test
        model: mock-model
`, model.URL))
	agentPath := writeTestFile(t, dir, "agent.yaml", `
name: integration_agent
description: Test integration agent.
instruction: Use tools when helpful.
`)
	toolPath := writeTestFile(t, dir, "tool.yaml", fmt.Sprintf(`
mcp:
  enabled: true
  servers:
    - name: time_server
      transport: streamable-http
      endpoint: %s
      tools:
        allow:
          - city_time
`, mcpHTTPServer.URL))

	pipeStdin(t, "What time is it in Lisbon?\n")
	stdout := captureStdout(t)

	cmd := NewRootCommand(t.Context())
	cmd.SetArgs([]string{
		"run",
		"--model", modelPath,
		"--agent", agentPath,
		"--tool", toolPath,
		"--",
		"console",
	})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("Execute() error = %v", err)
	}

	output := stdout()
	if !strings.Contains(output, "final answer after MCP") {
		t.Fatalf("stdout = %q, want final model answer", output)
	}
	if got := mcpCalls.Load(); got != 1 {
		t.Fatalf("mcpCalls = %d, want 1", got)
	}
	model.AssertWiring(t)
}

type cityTimeInput struct {
	City string `json:"city" jsonschema:"city name"`
}

type cityTimeOutput struct {
	Summary string `json:"summary" jsonschema:"time summary"`
}

type mockOpenAIModelServer struct {
	*httptest.Server

	mu       sync.Mutex
	requests []map[string]any
}

func newMockOpenAIModelServer(t *testing.T) *mockOpenAIModelServer {
	t.Helper()
	mock := &mockOpenAIModelServer{}
	mock.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req map[string]any
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		mock.mu.Lock()
		mock.requests = append(mock.requests, req)
		callNumber := len(mock.requests)
		mock.mu.Unlock()

		w.Header().Set("content-type", "application/json")
		switch callNumber {
		case 1:
			_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call-city-time","type":"function","function":{"name":"city_time","arguments":"{\"city\":\"Lisbon\"}"}}]}}]}`))
		default:
			_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"final answer after MCP"}}]}`))
		}
	}))
	return mock
}

func (s *mockOpenAIModelServer) AssertWiring(t *testing.T) {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.requests) != 2 {
		t.Fatalf("model request count = %d, want 2", len(s.requests))
	}
	first, err := json.Marshal(s.requests[0])
	if err != nil {
		t.Fatalf("Marshal(first request) error = %v", err)
	}
	if !strings.Contains(string(first), "city_time") {
		t.Fatalf("first model request = %s, want MCP tool declaration", first)
	}
	second, err := json.Marshal(s.requests[1])
	if err != nil {
		t.Fatalf("Marshal(second request) error = %v", err)
	}
	if !strings.Contains(string(second), "time for Lisbon from MCP") {
		t.Fatalf("second model request = %s, want MCP tool result", second)
	}
}

func writeTestFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(strings.TrimSpace(content)+"\n"), 0o600); err != nil {
		t.Fatalf("WriteFile(%s) error = %v", path, err)
	}
	return path
}

func pipeStdin(t *testing.T, content string) {
	t.Helper()
	original := os.Stdin
	read, write, err := os.Pipe()
	if err != nil {
		t.Fatalf("Pipe() error = %v", err)
	}
	if _, err := write.WriteString(content); err != nil {
		t.Fatalf("stdin WriteString() error = %v", err)
	}
	if err := write.Close(); err != nil {
		t.Fatalf("stdin close writer error = %v", err)
	}
	os.Stdin = read
	t.Cleanup(func() {
		os.Stdin = original
		if err := read.Close(); err != nil {
			t.Errorf("stdin close reader error = %v", err)
		}
	})
}

func captureStdout(t *testing.T) func() string {
	t.Helper()
	original := os.Stdout
	out, err := os.CreateTemp(t.TempDir(), "stdout-*")
	if err != nil {
		t.Fatalf("CreateTemp(stdout) error = %v", err)
	}
	os.Stdout = out
	t.Cleanup(func() {
		os.Stdout = original
		if err := out.Close(); err != nil {
			t.Errorf("stdout close error = %v", err)
		}
	})
	return func() string {
		if _, err := out.Seek(0, 0); err != nil {
			t.Fatalf("stdout Seek() error = %v", err)
		}
		data, err := os.ReadFile(out.Name())
		if err != nil {
			t.Fatalf("ReadFile(stdout) error = %v", err)
		}
		return string(data)
	}
}
