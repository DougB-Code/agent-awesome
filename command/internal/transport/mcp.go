// This file serves command execution tools over MCP JSON-RPC.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"command/internal/command"
)

const maxRequestBytes int64 = 2 << 20

// MCPServer serves the command MCP tool surface.
type MCPServer struct {
	service *command.Service
}

// NewMCPServer creates an MCP transport adapter for command tools.
func NewMCPServer(service *command.Service) *MCPServer {
	return &MCPServer{service: service}
}

// ServeHTTP handles JSON-RPC MCP requests.
func (s *MCPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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
func (s *MCPServer) handle(ctx context.Context, req rpcRequest) (any, *rpcError) {
	switch req.Method {
	case "initialize":
		return map[string]any{
			"protocolVersion": "2025-06-18",
			"capabilities": map[string]any{
				"tools": map[string]any{"listChanged": false},
			},
			"serverInfo": map[string]any{
				"name":    "agentawesome-command",
				"version": "0.1.0",
			},
		}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefinitions()}, nil
	case "tools/call":
		return s.handleToolCall(ctx, req.Params)
	default:
		return nil, &rpcError{Code: -32601, Message: "method not found", Data: req.Method}
	}
}

// handleToolCall invokes one command MCP tool.
func (s *MCPServer) handleToolCall(ctx context.Context, params json.RawMessage) (any, *rpcError) {
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

// callTool decodes command tool arguments and calls the service.
func (s *MCPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "command.execute":
		var req command.ExecuteRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Execute(ctx, req)
	case "command_template_list":
		return map[string]any{"templates": s.service.Templates()}, nil
	case "command_request":
		var req command.Request
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Request(ctx, req)
	case "command_run":
		var req command.RunRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Run(ctx, req)
	case "command_status":
		var req commandStatusRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Status(ctx, req.JobID)
	case "command_cancel":
		var req commandStatusRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Cancel(ctx, req.JobID)
	default:
		return nil, errors.New("command tool is not supported")
	}
}

// toolDefinitions returns the MCP tool descriptors.
func toolDefinitions() []map[string]any {
	names := []string{
		"command.execute",
		"command_template_list",
		"command_request",
		"command_run",
		"command_status",
		"command_cancel",
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

// toolDescription returns one concise model-facing tool description.
func toolDescription(name string) string {
	switch name {
	case "command.execute":
		return "Create, run, poll, and return one structured configured command result."
	case "command_template_list":
		return "List configured command templates."
	case "command_request":
		return "Create an exact command proposal for approval."
	case "command_run":
		return "Start an approved command proposal as an async job."
	case "command_status":
		return "Read command job status and bounded output tails."
	case "command_cancel":
		return "Cancel a running command job."
	default:
		return "Command execution tool."
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

// commandStatusRequest stores one command job id argument.
type commandStatusRequest struct {
	JobID string `json:"job_id"`
}
