// This file tests the ADK memory adapter against a minimal MCP endpoint.
package adkmemory

import (
	"context"
	"encoding/json"
	"iter"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/sessionstore"
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
		appName: "personal_pilot",
		userID:  "doug",
		events: []*session.Event{
			{
				ID:        "event-user",
				Timestamp: stamp,
				Author:    "user",
				LLMResponse: model.LLMResponse{Content: genai.NewContentFromText(
					"[[AURORA_RUNTIME_POLICY:test policy]]\n[[AURORA_SESSION_CONTEXT:test context]]\nRemember that I like green tea.",
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
	if got := calls[0].arguments["idempotency_key"]; got != "adk:personal_pilot:doug:session-1234567890:event-user" {
		t.Fatalf("idempotency = %q, want ADK event key", got)
	}
	if got := calls[1].arguments["content"]; got != "Got it." {
		t.Fatalf("model content = %q, want final model text", got)
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
		Query: "[[AURORA_RUNTIME_POLICY:test policy]]\ngreen tea",
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

// TestSearchMemoryIncludesExactSessionHistory verifies same-DB session fallback.
func TestSearchMemoryIncludesExactSessionHistory(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "memory.db")
	sessionService, err := sessionstore.Open(path)
	if err != nil {
		t.Fatalf("Open() session store error = %v", err)
	}
	created, err := sessionService.Create(ctx, &session.CreateRequest{
		AppName:   "pilot",
		UserID:    "doug",
		SessionID: "chat-history",
	})
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	event := session.NewEvent("turn-history")
	event.Timestamp = time.Now().Add(-2 * time.Hour)
	event.Author = "user"
	event.Content = genai.NewContentFromText("The launch code phrase was glass harbor.", genai.RoleUser)
	event.LLMResponse = model.LLMResponse{Content: event.Content, TurnComplete: true}
	if err := sessionService.AppendEvent(ctx, created.Session, event); err != nil {
		t.Fatalf("AppendEvent() error = %v", err)
	}

	server := newMemoryMCPTestServer(t, nil)
	service := New(schema.MCPServer{Name: "memory", Transport: "streamable-http", Endpoint: server.URL}, path)
	response, err := service.SearchMemory(ctx, &adkmemory.SearchRequest{
		AppName: "pilot",
		UserID:  "doug",
		Query:   "glass harbor",
	})
	if err != nil {
		t.Fatalf("SearchMemory() error = %v", err)
	}
	if len(response.Memories) != 1 {
		t.Fatalf("memories = %d, want exact session memory", len(response.Memories))
	}
	if !strings.HasPrefix(response.Memories[0].ID, "adk_session:chat-history:") {
		t.Fatalf("memory id = %q, want ADK session source", response.Memories[0].ID)
	}
	if got := response.Memories[0].Content.Parts[0].Text; got != "The launch code phrase was glass harbor." {
		t.Fatalf("memory text = %q, want exact session text", got)
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
