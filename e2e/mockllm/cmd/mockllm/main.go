// Package main starts an OpenAI-compatible mock provider for release E2E tests.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultListenAddress = ":8080"
	taskPromptMarker     = "create release e2e task"
	taskTitle            = "Release E2E Verified Task"
	taskResponseText     = "mock llm e2e task created: " + taskTitle
	taskToolCallID       = "call-create-release-e2e-task"
)

// recordedRequest stores one provider request for later E2E assertions.
type recordedRequest struct {
	Method        string         `json:"method"`
	Path          string         `json:"path"`
	Authorization string         `json:"authorization"`
	Body          map[string]any `json:"body"`
	ReceivedAt    string         `json:"received_at"`
}

// requestStore keeps a bounded in-memory list of provider calls.
type requestStore struct {
	mu       sync.Mutex
	limit    int
	requests []recordedRequest
}

// main configures the mock provider HTTP routes and blocks on ListenAndServe.
func main() {
	store := &requestStore{limit: envInt("AGENTAWESOME_MOCK_LLM_REQUEST_LIMIT", 100)}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthHandler)
	mux.HandleFunc("/requests", store.requestsHandler)
	mux.HandleFunc("/reset", store.resetHandler)
	mux.HandleFunc("/v1/chat/completions", store.chatCompletionsHandler)

	server := &http.Server{
		Addr:              envString("AGENTAWESOME_MOCK_LLM_ADDR", defaultListenAddress),
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("mock LLM provider listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve mock LLM provider: %v", err)
	}
}

// healthHandler reports that the mock provider process is ready.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// requestsHandler returns all recorded chat-completion requests.
func (s *requestStore) requestsHandler(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	requests := make([]recordedRequest, len(s.requests))
	copy(requests, s.requests)
	writeJSON(w, http.StatusOK, map[string]any{
		"requests": requests,
	})
}

// resetHandler clears previously recorded requests.
func (s *requestStore) resetHandler(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requests = nil
	writeJSON(w, http.StatusOK, map[string]string{"status": "reset"})
}

// chatCompletionsHandler records one OpenAI-compatible request and replies.
func (s *requestStore) chatCompletionsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var body map[string]any
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "decode request: " + err.Error()})
		return
	}
	s.record(recordedRequest{
		Method:        r.Method,
		Path:          r.URL.Path,
		Authorization: r.Header.Get("Authorization"),
		Body:          body,
		ReceivedAt:    time.Now().UTC().Format(time.RFC3339Nano),
	})
	writeJSON(w, http.StatusOK, chatCompletionResponseFor(body))
}

// record appends one provider request while preserving the configured limit.
func (s *requestStore) record(request recordedRequest) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requests = append(s.requests, request)
	if s.limit > 0 && len(s.requests) > s.limit {
		s.requests = append([]recordedRequest(nil), s.requests[len(s.requests)-s.limit:]...)
	}
}

// chatCompletionResponseFor builds deterministic content or tool-call replies.
func chatCompletionResponseFor(body map[string]any) map[string]any {
	prompt := strings.ToLower(latestUserMessage(body))
	if !strings.Contains(prompt, taskPromptMarker) {
		return chatCompletionResponse(responseText(body))
	}
	if hasToolResponse(body, taskToolCallID) {
		return chatCompletionResponse(taskResponseText)
	}
	return toolCallCompletionResponse()
}

// hasToolResponse reports whether the request includes a completed tool result.
func hasToolResponse(body map[string]any, callID string) bool {
	messages, ok := body["messages"].([]any)
	if !ok {
		return false
	}
	for _, item := range messages {
		message, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if message["role"] == "tool" && stringValue(message["tool_call_id"]) == callID {
			return true
		}
	}
	return false
}

// responseText builds deterministic assistant content from the latest user turn.
func responseText(body map[string]any) string {
	prompt := latestUserMessage(body)
	if prompt == "" {
		return "mock llm e2e response"
	}
	return fmt.Sprintf("mock llm e2e response: %s", prompt)
}

// toolCallCompletionResponse asks the harness to create one graph-backed task.
func toolCallCompletionResponse() map[string]any {
	now := time.Now().Unix()
	return map[string]any{
		"id":      "chatcmpl-agentawesome-e2e-tool",
		"object":  "chat.completion",
		"created": now,
		"model":   "mock-e2e-model",
		"choices": []map[string]any{
			{
				"index": 0,
				"message": map[string]any{
					"role": "assistant",
					"tool_calls": []map[string]any{
						{
							"id":   taskToolCallID,
							"type": "function",
							"function": map[string]string{
								"name":      "create_task",
								"arguments": taskCreationArguments(),
							},
						},
					},
				},
				"finish_reason": "tool_calls",
			},
		},
	}
}

// taskCreationArguments returns the stable create_task payload for E2E runs.
func taskCreationArguments() string {
	encoded, err := json.Marshal(map[string]any{
		"title":           taskTitle,
		"description":     "Created by the release E2E mock provider.",
		"priority":        "normal",
		"topics":          []string{"e2e", "release"},
		"idempotency_key": "release-e2e-verified-task",
	})
	if err != nil {
		return "{}"
	}
	return string(encoded)
}

// latestUserMessage extracts the final user message from an OpenAI request body.
func latestUserMessage(body map[string]any) string {
	messages, ok := body["messages"].([]any)
	if !ok {
		return ""
	}
	for index := len(messages) - 1; index >= 0; index-- {
		message, ok := messages[index].(map[string]any)
		if !ok || message["role"] != "user" {
			continue
		}
		return strings.TrimSpace(stringValue(message["content"]))
	}
	return ""
}

// stringValue normalizes OpenAI text content from string or content-part arrays.
func stringValue(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case []any:
		parts := make([]string, 0, len(typed))
		for _, part := range typed {
			partMap, ok := part.(map[string]any)
			if !ok {
				continue
			}
			if text, ok := partMap["text"].(string); ok {
				parts = append(parts, text)
			}
		}
		return strings.Join(parts, "\n")
	default:
		return ""
	}
}

// chatCompletionResponse returns a minimal OpenAI-compatible JSON response.
func chatCompletionResponse(content string) map[string]any {
	now := time.Now().Unix()
	return map[string]any{
		"id":      "chatcmpl-agentawesome-e2e",
		"object":  "chat.completion",
		"created": now,
		"model":   "mock-e2e-model",
		"choices": []map[string]any{
			{
				"index": 0,
				"message": map[string]any{
					"role":    "assistant",
					"content": content,
				},
				"finish_reason": "stop",
			},
		},
	}
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("write json response: %v", err)
	}
}

// envString returns one environment value or a fallback.
func envString(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// envInt returns one positive integer environment value or a fallback.
func envInt(name string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
