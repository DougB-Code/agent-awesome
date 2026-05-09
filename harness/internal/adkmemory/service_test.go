// This file tests the ADK memory adapter against a minimal MCP endpoint.
package adkmemory

import (
	"context"
	"encoding/json"
	"fmt"
	"iter"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
	adkmemory "google.golang.org/adk/memory"
	"google.golang.org/adk/model"
	"google.golang.org/adk/session"
	"google.golang.org/genai"
)

// TestAddSessionToMemoryCapturesSanitizedChatEvents verifies MCP capture calls.
func TestAddSessionToMemoryCapturesSanitizedChatEvents(t *testing.T) {
	t.Setenv("MEMORY_AUTH", "Bearer test-token")
	stamp := time.Date(2026, 5, 8, 10, 30, 0, 0, time.UTC)
	server := newMemoryMCPTestServer(t, nil)
	service := New(schema.MCPServer{
		Name:      "memory",
		Transport: "streamable-http",
		Endpoint:  server.URL,
		HeadersFromEnv: map[string]string{
			"Authorization": "MEMORY_AUTH",
		},
	})
	chat := stubSession{
		id:      "session-1234567890",
		appName: "agent_awesome",
		userID:  "doug",
		events: []*session.Event{
			{
				ID:        "event-user",
				Timestamp: stamp,
				Author:    "user",
				LLMResponse: model.LLMResponse{Content: genai.NewContentFromText(
					"[[AGENT_AWESOME_RUNTIME_POLICY:test policy]]\n[[AGENT_AWESOME_SESSION_CONTEXT:test context]]\nRemember that I like green tea.",
					genai.RoleUser,
				)},
			},
			{
				ID:          "event-partial",
				Timestamp:   stamp,
				Author:      "model",
				LLMResponse: model.LLMResponse{Content: genai.NewContentFromText("partial", genai.RoleModel), Partial: true},
			},
			{
				ID:          "event-model",
				Timestamp:   stamp.Add(time.Second),
				Author:      "assistant",
				LLMResponse: model.LLMResponse{Content: genai.NewContentFromText("Got it.", genai.RoleModel)},
			},
		},
	}

	if err := service.AddSessionToMemory(context.Background(), chat); err != nil {
		t.Fatalf("AddSessionToMemory() error = %v", err)
	}

	calls := server.calls()
	if len(calls) != 2 {
		t.Fatalf("MCP calls = %d, want 2: %#v", len(calls), calls)
	}
	if got := calls[0].authorization; got != "Bearer test-token" {
		t.Fatalf("authorization = %q, want bearer token", got)
	}
	if got := calls[0].arguments["content"]; got != "Remember that I like green tea." {
		t.Fatalf("content = %q, want sanitized chat text", got)
	}
	if got := calls[0].arguments["kind"]; got != conversationKind {
		t.Fatalf("kind = %q, want conversation", got)
	}
	if got := calls[0].arguments["scope"]; got != userScope {
		t.Fatalf("scope = %q, want user", got)
	}
	if got := calls[0].arguments["idempotency_key"]; got != "adk:agent_awesome:doug:session-1234567890:event-user" {
		t.Fatalf("idempotency = %q, want ADK event key", got)
	}
	if got := calls[1].arguments["content"]; got != "Got it." {
		t.Fatalf("model content = %q, want final model text", got)
	}
}

// TestAddSessionToMemoryCapturesOnlyNewEvents prevents full-session replays.
func TestAddSessionToMemoryCapturesOnlyNewEvents(t *testing.T) {
	stamp := time.Date(2026, 5, 8, 12, 0, 0, 0, time.UTC)
	server := newMemoryMCPTestServer(t, nil)
	service := New(schema.MCPServer{Name: "memory", Transport: "streamable-http", Endpoint: server.URL})
	events := make([]*session.Event, 0, 101)
	for index := 0; index < 100; index++ {
		events = append(events, capturableEvent(
			fmt.Sprintf("event-%03d", index),
			fmt.Sprintf("remembered detail %03d", index),
			stamp.Add(time.Duration(index)*time.Second),
		))
	}
	chat := stubSession{
		id:      "long-session",
		appName: "agent_awesome",
		userID:  "doug",
		events:  events,
	}

	if err := service.AddSessionToMemory(context.Background(), chat); err != nil {
		t.Fatalf("AddSessionToMemory() first error = %v", err)
	}
	if err := service.AddSessionToMemory(context.Background(), chat); err != nil {
		t.Fatalf("AddSessionToMemory() replay error = %v", err)
	}
	if got := len(server.calls()); got != 100 {
		t.Fatalf("MCP calls after replay = %d, want initial 100 only", got)
	}

	chat.events = append(chat.events, capturableEvent("event-100", "brand new detail", stamp.Add(100*time.Second)))
	if err := service.AddSessionToMemory(context.Background(), chat); err != nil {
		t.Fatalf("AddSessionToMemory() incremental error = %v", err)
	}

	calls := server.calls()
	if len(calls) != 101 {
		t.Fatalf("MCP calls after append = %d, want one new call", len(calls))
	}
	last := calls[len(calls)-1]
	if got := last.arguments["idempotency_key"]; got != "adk:agent_awesome:doug:long-session:event-100" {
		t.Fatalf("last idempotency = %q, want appended event key", got)
	}
	if got := last.arguments["content"]; got != "brand new detail" {
		t.Fatalf("last content = %q, want appended event content", got)
	}
}

// TestSearchMemoryMapsSourceRecords verifies ADK search response mapping.
func TestSearchMemoryMapsSourceRecords(t *testing.T) {
	stamp := time.Date(2026, 5, 8, 11, 0, 0, 0, time.UTC)
	server := newMemoryMCPTestServer(t, map[string]any{
		"primary_memory": []map[string]any{
			{
				"id":          "mem_1",
				"evidence_id": "evidence_1",
				"title":       "Tea preference",
				"subjects":    []string{"user"},
				"event_time":  stamp.Format(time.RFC3339Nano),
				"created_at":  stamp.Format(time.RFC3339Nano),
				"updated_at":  stamp.Format(time.RFC3339Nano),
				"source":      map[string]any{"system": "google_adk_session", "id": "event-user"},
				"raw": map[string]any{
					"id":           "evidence_1",
					"content_text": "Remember that I like green tea.",
					"created_at":   stamp.Format(time.RFC3339Nano),
					"source":       map[string]any{"system": "google_adk_session", "id": "event-user"},
				},
			},
		},
	})
	service := New(schema.MCPServer{Name: "memory", Transport: "streamable-http", Endpoint: server.URL})

	response, err := service.SearchMemory(context.Background(), &adkmemory.SearchRequest{
		Query: "[[AGENT_AWESOME_RUNTIME_POLICY:test policy]]\ngreen tea",
	})
	if err != nil {
		t.Fatalf("SearchMemory() error = %v", err)
	}
	if len(response.Memories) != 1 {
		t.Fatalf("memories = %d, want 1", len(response.Memories))
	}
	if got := response.Memories[0].Content.Parts[0].Text; got != "Remember that I like green tea." {
		t.Fatalf("memory text = %q, want raw evidence text", got)
	}
	if got := response.Memories[0].Author; got != "user" {
		t.Fatalf("author = %q, want subject", got)
	}

	calls := server.calls()
	if len(calls) != 1 {
		t.Fatalf("MCP calls = %d, want search call", len(calls))
	}
	if got := calls[0].arguments["text"]; got != "green tea" {
		t.Fatalf("search text = %q, want sanitized query", got)
	}
}

// TestNewFromToolsConfigSelectsAllowedMemoryServer verifies config discovery.
func TestNewFromToolsConfigSelectsAllowedMemoryServer(t *testing.T) {
	service, ok, err := NewFromToolsConfig(&schema.Tools{
		MCP: schema.MCP{
			Enabled: true,
			Servers: []schema.MCPServer{
				{Name: "files", Transport: "streamable-http", Endpoint: "http://127.0.0.1/files", Tools: schema.MCPToolFilter{Allow: []string{"read_file"}}},
				{Name: "context", Transport: "streamable-http", Endpoint: "http://127.0.0.1/memory", Tools: schema.MCPToolFilter{Allow: []string{saveMemoryToolName, searchSourcesToolName}}},
			},
		},
	})
	if err != nil {
		t.Fatalf("NewFromToolsConfig() error = %v", err)
	}
	if !ok || service == nil {
		t.Fatalf("NewFromToolsConfig() ok/service = %v/%v, want selected service", ok, service)
	}
}

// mcpToolCall stores one tool call observed by the test MCP server.
type mcpToolCall struct {
	name          string
	arguments     map[string]any
	authorization string
}

// memoryMCPTestServer records tool calls and returns configured search content.
type memoryMCPTestServer struct {
	*httptest.Server
	mu               sync.Mutex
	toolCalls        []mcpToolCall
	searchStructured map[string]any
}

// newMemoryMCPTestServer creates a minimal streamable HTTP MCP test endpoint.
func newMemoryMCPTestServer(t *testing.T, searchStructured map[string]any) *memoryMCPTestServer {
	t.Helper()
	server := &memoryMCPTestServer{searchStructured: searchStructured}
	server.Server = httptest.NewServer(http.HandlerFunc(server.serveHTTP))
	t.Cleanup(server.Close)
	return server
}

// calls returns a snapshot of observed MCP tool calls.
func (s *memoryMCPTestServer) calls() []mcpToolCall {
	s.mu.Lock()
	defer s.mu.Unlock()
	calls := make([]mcpToolCall, len(s.toolCalls))
	copy(calls, s.toolCalls)
	return calls
}

// serveHTTP handles the subset of MCP JSON-RPC needed by the adapter.
func (s *memoryMCPTestServer) serveHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodDelete {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	var req mcpRPCRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if len(req.ID) == 0 || string(req.ID) == "null" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	switch req.Method {
	case "initialize":
		writeMCPResult(w, req.ID, map[string]any{
			"protocolVersion": "2025-06-18",
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": "test-memory", "version": "v0"},
		})
	case "tools/call":
		s.handleToolCall(w, r, req)
	default:
		writeMCPResult(w, req.ID, map[string]any{})
	}
}

// handleToolCall records an MCP tools/call request and writes a tool result.
func (s *memoryMCPTestServer) handleToolCall(w http.ResponseWriter, r *http.Request, req mcpRPCRequest) {
	var params struct {
		Name      string         `json:"name"`
		Arguments map[string]any `json:"arguments"`
	}
	if err := json.Unmarshal(req.Params, &params); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	s.mu.Lock()
	s.toolCalls = append(s.toolCalls, mcpToolCall{
		name:          params.Name,
		arguments:     params.Arguments,
		authorization: r.Header.Get("Authorization"),
	})
	s.mu.Unlock()

	structured := map[string]any{"memory_id": "mem_saved", "evidence_id": "ev_saved"}
	if params.Name == searchSourcesToolName {
		structured = s.searchStructured
	}
	writeMCPResult(w, req.ID, map[string]any{
		"content":           []any{},
		"structuredContent": structured,
	})
}

// mcpRPCRequest decodes one JSON-RPC request from the MCP SDK.
type mcpRPCRequest struct {
	ID     json.RawMessage `json:"id,omitempty"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params,omitempty"`
}

// writeMCPResult writes one JSON-RPC result response.
func writeMCPResult(w http.ResponseWriter, id json.RawMessage, result any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"result":  result,
	})
}

// capturableEvent creates one complete chat event for memory capture tests.
func capturableEvent(id string, text string, timestamp time.Time) *session.Event {
	return &session.Event{
		ID:          id,
		Timestamp:   timestamp,
		Author:      "user",
		LLMResponse: model.LLMResponse{Content: genai.NewContentFromText(text, genai.RoleUser)},
	}
}

// stubSession implements the ADK session interface for adapter tests.
type stubSession struct {
	id      string
	appName string
	userID  string
	events  []*session.Event
}

// ID returns the test session ID.
func (s stubSession) ID() string { return s.id }

// AppName returns the test app name.
func (s stubSession) AppName() string { return s.appName }

// UserID returns the test user ID.
func (s stubSession) UserID() string { return s.userID }

// State returns no session state because memory capture does not inspect it.
func (s stubSession) State() session.State { return nil }

// Events returns the test session event list.
func (s stubSession) Events() session.Events { return stubEvents(s.events) }

// LastUpdateTime returns zero because memory capture does not inspect it.
func (s stubSession) LastUpdateTime() time.Time { return time.Time{} }

// stubEvents implements ADK session.Events for adapter tests.
type stubEvents []*session.Event

// All returns each event in insertion order.
func (e stubEvents) All() iter.Seq[*session.Event] {
	return func(yield func(*session.Event) bool) {
		for _, event := range e {
			if !yield(event) {
				return
			}
		}
	}
}

// Len returns the number of stub events.
func (e stubEvents) Len() int { return len(e) }

// At returns one event by index.
func (e stubEvents) At(i int) *session.Event { return e[i] }
