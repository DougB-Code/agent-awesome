// This file serves source-control boundary tools over MCP JSON-RPC.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"sourcecontrol/internal/sourcecontrol"
)

const maxRequestBytes int64 = 2 << 20

// Server serves the source-control MCP tool surface.
type Server struct {
	service *sourcecontrol.Service
}

// NewServer creates a source-control MCP transport adapter.
func NewServer(service *sourcecontrol.Service) *Server {
	return &Server{service: service}
}

// ServeHTTP handles JSON-RPC MCP requests.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body := http.MaxBytesReader(w, r.Body, maxRequestBytes)
	defer body.Close()
	var req rpcRequest
	if err := json.NewDecoder(body).Decode(&req); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			http.Error(w, "payload too large", http.StatusRequestEntityTooLarge)
			return
		}
		writeRPCError(w, nil, -32700, "parse error", err.Error())
		return
	}
	if len(req.ID) == 0 {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	result, rpcErr := s.handle(r.Context(), req)
	if rpcErr != nil {
		writeRPCError(w, req.ID, rpcErr.Code, rpcErr.Message, rpcErr.Data)
		return
	}
	writeRPCResult(w, req.ID, result)
}

// handle dispatches supported MCP methods.
func (s *Server) handle(ctx context.Context, req rpcRequest) (any, *rpcError) {
	switch req.Method {
	case "initialize":
		return map[string]any{
			"protocolVersion": "2025-06-18",
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": "agentawesome-sourcecontrol", "version": "0.1.0"},
		}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefinitions()}, nil
	case "tools/call":
		return s.handleToolCall(ctx, req.Params)
	default:
		return nil, &rpcError{Code: -32601, Message: "method not found", Data: req.Method}
	}
}

// handleToolCall invokes one source-control MCP tool.
func (s *Server) handleToolCall(ctx context.Context, params json.RawMessage) (any, *rpcError) {
	var call toolCallParams
	if err := json.Unmarshal(params, &call); err != nil {
		return nil, &rpcError{Code: -32602, Message: "invalid params", Data: err.Error()}
	}
	result, err := s.callTool(ctx, call.Name, call.Arguments)
	if err != nil {
		return toolResult(map[string]string{"error": err.Error()}, true), nil
	}
	return toolResult(result, false), nil
}

// callTool decodes tool arguments and calls the source-control service.
func (s *Server) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "sourcecontrol.prepare_worktree":
		var req sourcecontrol.PrepareWorktreeRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.PrepareWorktree(ctx, req)
	case "sourcecontrol.status":
		var req sourcecontrol.StatusRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Status(ctx, req)
	case "sourcecontrol.commit":
		var req sourcecontrol.CommitRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Commit(ctx, req)
	case "sourcecontrol.push":
		var req sourcecontrol.PushRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Push(ctx, req)
	case "sourcecontrol.backup":
		var req sourcecontrol.BackupRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Backup(ctx, req)
	case "sourcecontrol.restore":
		var req sourcecontrol.RestoreRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Restore(ctx, req)
	case "sourcecontrol.cleanup_worktree":
		var req sourcecontrol.CleanupRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.CleanupWorktree(ctx, req)
	default:
		return nil, errors.New("source-control tool is not supported")
	}
}

// toolDefinitions returns source-control tool descriptors.
func toolDefinitions() []map[string]any {
	names := []string{
		"sourcecontrol.prepare_worktree",
		"sourcecontrol.status",
		"sourcecontrol.commit",
		"sourcecontrol.push",
		"sourcecontrol.backup",
		"sourcecontrol.restore",
		"sourcecontrol.cleanup_worktree",
	}
	tools := make([]map[string]any, 0, len(names))
	for _, name := range names {
		tools = append(tools, map[string]any{
			"name":        name,
			"description": toolDescription(name),
			"inputSchema": map[string]any{"type": "object"},
		})
	}
	return tools
}

// toolDescription returns one concise model-facing description.
func toolDescription(name string) string {
	switch name {
	case "sourcecontrol.prepare_worktree":
		return "Prepare an isolated Git worktree and branch after safety checks."
	case "sourcecontrol.status":
		return "Read status for a prepared source-control worktree."
	case "sourcecontrol.commit":
		return "Commit changes inside a prepared source-control worktree."
	case "sourcecontrol.push":
		return "Push the prepared worktree branch to a configured remote."
	case "sourcecontrol.backup":
		return "Create a safety backup for a prepared worktree."
	case "sourcecontrol.restore":
		return "Restore a prepared worktree from a safety backup."
	case "sourcecontrol.cleanup_worktree":
		return "Remove a prepared worktree after workflow completion."
	default:
		return "Source-control safety tool."
	}
}

// decodeArgs unmarshals MCP tool arguments.
func decodeArgs(args json.RawMessage, target any) error {
	if len(args) == 0 {
		args = []byte(`{}`)
	}
	return json.Unmarshal(args, target)
}

// toolResult wraps structured MCP content.
func toolResult(content any, isError bool) map[string]any {
	data, _ := json.Marshal(content)
	return map[string]any{
		"content": []map[string]string{
			{"type": "text", "text": string(data)},
		},
		"structuredContent": content,
		"isError":           isError,
	}
}

// writeRPCResult writes a JSON-RPC result response.
func writeRPCResult(w http.ResponseWriter, id json.RawMessage, result any) {
	writeJSON(w, http.StatusOK, rpcResponse{JSONRPC: "2.0", ID: id, Result: result})
}

// writeRPCError writes a JSON-RPC error response.
func writeRPCError(w http.ResponseWriter, id json.RawMessage, code int, message string, data any) {
	writeJSON(w, http.StatusOK, rpcResponse{JSONRPC: "2.0", ID: id, Error: &rpcError{Code: code, Message: message, Data: data}})
}

// writeJSON writes one JSON response body.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// rpcRequest stores one JSON-RPC request.
type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

// rpcResponse stores one JSON-RPC response.
type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

// rpcError stores one JSON-RPC error.
type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

// toolCallParams stores MCP tools/call params.
type toolCallParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}
