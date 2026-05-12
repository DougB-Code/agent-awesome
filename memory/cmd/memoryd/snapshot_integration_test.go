// This file tests memoryd snapshot behavior across real process restarts.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

const snapshotIntegrationToken = "snapshot-integration-token"

// TestMemoryDSnapshotSaveRestoreDrill verifies the beta daemon-level snapshot workflow.
func TestMemoryDSnapshotSaveRestoreDrill(t *testing.T) {
	binary := buildMemoryDBinary(t)
	snapshots := newSnapshotEndpoint()
	endpoint := httptest.NewServer(snapshots)
	defer endpoint.Close()

	firstRoot := t.TempDir()
	first := startMemoryD(t, binary, memoryDInstance{
		Address:     freeLocalAddress(t),
		DBPath:      filepath.Join(firstRoot, "memory.db"),
		DataRoot:    filepath.Join(firstRoot, "data"),
		SnapshotURL: endpoint.URL,
	})
	callMemoryDTool(t, first.Address, "save_memory_candidate", map[string]any{
		"content":         "Daemon snapshot preference survives restart.",
		"title":           "Daemon snapshot memory",
		"firewall":        "user",
		"kind":            "profile_fact",
		"trust_level":     "user_asserted",
		"idempotency_key": "daemon-snapshot-memory",
	})
	callMemoryDTool(t, first.Address, "create_task", map[string]any{
		"title":           "Verify daemon snapshot restore",
		"idempotency_key": "daemon-snapshot-task",
	})
	stopMemoryD(t, first)
	if snapshots.latestSize() == 0 {
		t.Fatalf("memoryd shutdown did not upload a snapshot")
	}

	secondRoot := t.TempDir()
	second := startMemoryD(t, binary, memoryDInstance{
		Address:     freeLocalAddress(t),
		DBPath:      filepath.Join(secondRoot, "memory.db"),
		DataRoot:    filepath.Join(secondRoot, "data"),
		SnapshotURL: endpoint.URL,
	})
	defer stopMemoryD(t, second)

	search := callMemoryDTool(t, second.Address, "search_sources", map[string]any{
		"firewall": "user",
		"text":     "survives restart",
		"limit":    10,
	})
	primary := search["primary_memory"].([]any)
	if len(primary) != 1 {
		t.Fatalf("restored primary memory = %#v, want one memory record", primary)
	}
	record := primary[0].(map[string]any)
	raw := record["raw"].(map[string]any)
	if !strings.Contains(raw["content_text"].(string), "survives restart") {
		t.Fatalf("restored raw memory = %#v, want original source text", raw)
	}

	list := callMemoryDTool(t, second.Address, "list_tasks", map[string]any{
		"search":       "Verify daemon snapshot restore",
		"include_done": true,
		"limit":        10,
	})
	tasks := list["items"].([]any)
	if len(tasks) != 1 {
		t.Fatalf("restored tasks = %#v, want one task", tasks)
	}
	if title := tasks[0].(map[string]any)["title"]; title != "Verify daemon snapshot restore" {
		t.Fatalf("restored task title = %#v, want snapshot task", title)
	}
}

// memoryDInstance stores process settings for one daemon run.
type memoryDInstance struct {
	Address     string
	DBPath      string
	DataRoot    string
	SnapshotURL string
	Command     *exec.Cmd
	Output      *bytes.Buffer
}

// snapshotEndpoint stores the latest uploaded snapshot for daemon tests.
type snapshotEndpoint struct {
	mu   sync.Mutex
	data []byte
}

// newSnapshotEndpoint creates an authenticated test snapshot endpoint.
func newSnapshotEndpoint() *snapshotEndpoint {
	return &snapshotEndpoint{}
}

// ServeHTTP implements authenticated GET/PUT snapshot storage.
func (e *snapshotEndpoint) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Authorization") != "Bearer "+snapshotIntegrationToken {
		http.NotFound(w, r)
		return
	}
	switch r.Method {
	case http.MethodGet:
		e.mu.Lock()
		data := append([]byte(nil), e.data...)
		e.mu.Unlock()
		if len(data) == 0 {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/gzip")
		_, _ = w.Write(data)
	case http.MethodPut:
		data, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "read snapshot", http.StatusBadRequest)
			return
		}
		e.mu.Lock()
		e.data = append(e.data[:0], data...)
		e.mu.Unlock()
		w.WriteHeader(http.StatusNoContent)
	default:
		http.NotFound(w, r)
	}
}

// latestSize returns the latest stored snapshot size in bytes.
func (e *snapshotEndpoint) latestSize() int {
	e.mu.Lock()
	defer e.mu.Unlock()
	return len(e.data)
}

// buildMemoryDBinary compiles memoryd into the repository build directory.
func buildMemoryDBinary(t *testing.T) string {
	t.Helper()
	root := repoRoot(t)
	outputDir := filepath.Join(root, "build", "memoryd-integration")
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		t.Fatalf("create build dir: %v", err)
	}
	binary := filepath.Join(outputDir, "memoryd")
	cmd := exec.Command("go", "build", "-o", binary, "./cmd/memoryd")
	cmd.Dir = filepath.Join(root, "memory")
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("build memoryd: %v\n%s", err, output)
	}
	return binary
}

// startMemoryD launches one memoryd process and waits for health readiness.
func startMemoryD(t *testing.T, binary string, instance memoryDInstance) memoryDInstance {
	t.Helper()
	output := &bytes.Buffer{}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	t.Cleanup(cancel)
	cmd := exec.CommandContext(ctx, binary,
		"--addr", instance.Address,
		"--db", instance.DBPath,
		"--data", instance.DataRoot,
		"--snapshot-url", instance.SnapshotURL,
		"--snapshot-token", snapshotIntegrationToken,
		"--snapshot-timeout", "5s",
	)
	cmd.Stdout = output
	cmd.Stderr = output
	if err := cmd.Start(); err != nil {
		t.Fatalf("start memoryd: %v", err)
	}
	instance.Command = cmd
	instance.Output = output
	waitForMemoryDHealth(t, instance.Address, output)
	return instance
}

// stopMemoryD terminates one memoryd process and waits for graceful shutdown.
func stopMemoryD(t *testing.T, instance memoryDInstance) {
	t.Helper()
	if instance.Command == nil || instance.Command.Process == nil {
		return
	}
	if err := instance.Command.Process.Signal(syscall.SIGTERM); err != nil && !strings.Contains(err.Error(), "process already finished") {
		t.Fatalf("signal memoryd: %v\n%s", err, instance.Output.String())
	}
	done := make(chan error, 1)
	go func() { done <- instance.Command.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("memoryd exited with error: %v\n%s", err, instance.Output.String())
		}
	case <-time.After(10 * time.Second):
		_ = instance.Command.Process.Kill()
		t.Fatalf("memoryd did not stop gracefully\n%s", instance.Output.String())
	}
}

// waitForMemoryDHealth polls /healthz until memoryd is ready.
func waitForMemoryDHealth(t *testing.T, address string, output *bytes.Buffer) {
	t.Helper()
	client := &http.Client{Timeout: 500 * time.Millisecond}
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := client.Get("http://" + address + "/healthz")
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("memoryd did not become healthy\n%s", output.String())
}

// callMemoryDTool invokes one memoryd MCP tool and returns structured content.
func callMemoryDTool(t *testing.T, address string, name string, arguments map[string]any) map[string]any {
	t.Helper()
	body := map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      name,
			"arguments": arguments,
		},
	}
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal MCP request: %v", err)
	}
	resp, err := http.Post("http://"+address+"/mcp", "application/json", bytes.NewReader(data))
	if err != nil {
		t.Fatalf("post MCP request %s: %v", name, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		t.Fatalf("MCP status for %s = %d body = %s", name, resp.StatusCode, raw)
	}
	var decoded map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		t.Fatalf("decode MCP response: %v", err)
	}
	if rawErr, ok := decoded["error"]; ok {
		t.Fatalf("MCP error for %s: %#v", name, rawErr)
	}
	result := decoded["result"].(map[string]any)
	if result["isError"].(bool) {
		t.Fatalf("MCP tool %s returned error: %#v", name, result)
	}
	if structured, ok := result["structuredContent"].(map[string]any); ok {
		return structured
	}
	if items, ok := result["structuredContent"].([]any); ok {
		return map[string]any{"items": items}
	}
	return map[string]any{"value": result["structuredContent"]}
}

// freeLocalAddress reserves and releases one loopback TCP address for a test process.
func freeLocalAddress(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve local address: %v", err)
	}
	defer listener.Close()
	return listener.Addr().String()
}

// repoRoot returns the repository root from this test file location.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller() failed")
	}
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", ".."))
	if _, err := os.Stat(filepath.Join(root, "package.json")); err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}
	return root
}

// formatMCPValue renders unknown structured content in assertion messages.
func formatMCPValue(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Sprintf("%#v", value)
	}
	return string(data)
}
