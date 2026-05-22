// This file owns the shared HTTP JSON-RPC shell for MCP tool servers.
package mcptransport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"agentawesome.dev/platform/httpjson"
)

const protocolVersion = "2025-06-18"

// ToolCallFunc invokes one named MCP tool with raw JSON arguments.
type ToolCallFunc func(ctx context.Context, name string, args json.RawMessage) (any, error)

// ResultFormatter converts structured tool data into an MCP tool result.
type ResultFormatter func(value any, isError bool) any

// ServerInfo describes the JSON-RPC server identity returned by initialize.
type ServerInfo struct {
	Name    string
	Version string
}

// ToolCall stores MCP tools/call parameters.
type ToolCall struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

// RPCError stores one JSON-RPC error.
type RPCError struct {
	Code    int
	Message string
	Data    any
}

// Hooks observes tool calls without owning domain behavior.
type Hooks struct {
	OnToolCallStart    func(name string)
	OnToolCallError    func(name string, err error)
	OnToolCallComplete func(name string)
}

// Server serves MCP JSON-RPC methods over HTTP.
type Server struct {
	Info            ServerInfo
	MaxRequestBytes int64
	Tools           func() []map[string]any
	Call            ToolCallFunc
	Ready           func() *RPCError
	Validate        func(call ToolCall) *RPCError
	FormatResult    ResultFormatter
	Hooks           Hooks
}

// ServeHTTP handles one HTTP JSON-RPC request.
func (s Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	limit := s.MaxRequestBytes
	if limit <= 0 {
		limit = 1 << 20
	}
	var req rpcRequest
	if err := httpjson.DecodeBounded(w, r, limit, &req); err != nil {
		if errors.Is(err, httpjson.ErrPayloadTooLarge) {
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
	httpjson.WriteEscaped(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": json.RawMessage(req.ID), "result": result})
}

// CompactToolResult wraps structured MCP content in compact text form.
func CompactToolResult(value any, isError bool) any {
	data, _ := json.Marshal(value)
	return map[string]any{
		"content": []map[string]string{
			{"type": "text", "text": string(data)},
		},
		"structuredContent": value,
		"isError":           isError,
	}
}

// handle dispatches supported MCP methods.
func (s Server) handle(ctx context.Context, req rpcRequest) (any, *RPCError) {
	switch req.Method {
	case "initialize":
		return s.initializeResult(), nil
	case "tools/list":
		tools := []map[string]any{}
		if s.Tools != nil {
			tools = s.Tools()
		}
		return map[string]any{"tools": tools}, nil
	case "tools/call":
		return s.handleToolCall(ctx, req.Params)
	default:
		return nil, &RPCError{Code: -32601, Message: "method not found", Data: req.Method}
	}
}

// handleToolCall decodes and invokes one MCP tool call.
func (s Server) handleToolCall(ctx context.Context, params json.RawMessage) (any, *RPCError) {
	if s.Ready != nil {
		if rpcErr := s.Ready(); rpcErr != nil {
			return nil, rpcErr
		}
	}
	var call ToolCall
	if err := json.Unmarshal(params, &call); err != nil {
		return nil, &RPCError{Code: -32602, Message: "invalid params", Data: err.Error()}
	}
	if s.Validate != nil {
		if rpcErr := s.Validate(call); rpcErr != nil {
			return nil, rpcErr
		}
	}
	if s.Call == nil {
		return nil, &RPCError{Code: -32603, Message: "tool caller is required"}
	}
	if hook := s.Hooks.OnToolCallStart; hook != nil {
		hook(call.Name)
	}
	format := s.FormatResult
	if format == nil {
		format = CompactToolResult
	}
	result, err := s.Call(ctx, call.Name, call.Arguments)
	if err != nil {
		if hook := s.Hooks.OnToolCallError; hook != nil {
			hook(call.Name, err)
		}
		return format(map[string]string{"error": err.Error()}, true), nil
	}
	if hook := s.Hooks.OnToolCallComplete; hook != nil {
		hook(call.Name)
	}
	return format(result, false), nil
}

// initializeResult returns the standard MCP initialize response.
func (s Server) initializeResult() map[string]any {
	version := s.Info.Version
	if version == "" {
		version = "0.1.0"
	}
	return map[string]any{
		"protocolVersion": protocolVersion,
		"capabilities": map[string]any{
			"tools": map[string]any{"listChanged": false},
		},
		"serverInfo": map[string]any{
			"name":    s.Info.Name,
			"version": version,
		},
	}
}

// writeRPCError writes a JSON-RPC error response.
func writeRPCError(w http.ResponseWriter, id json.RawMessage, code int, message string, data any) {
	errBody := map[string]any{"code": code, "message": message}
	if data != nil {
		errBody["data"] = data
	}
	body := map[string]any{"jsonrpc": "2.0", "error": errBody}
	if len(id) > 0 {
		body["id"] = json.RawMessage(id)
	}
	httpjson.WriteEscaped(w, http.StatusOK, body)
}

// rpcRequest stores one JSON-RPC request.
type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}
