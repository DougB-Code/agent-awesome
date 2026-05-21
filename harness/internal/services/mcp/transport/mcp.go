// This file serves local MCP management tools over MCP JSON-RPC.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"agentawesome/internal/services/mcp/mcp"
)

const maxRequestBytes int64 = 2 << 20

// Server serves the MCP manager tool surface.
type Server struct {
	service *mcp.Service
}

// NewServer creates a transport adapter for MCP management tools.
func NewServer(service *mcp.Service) *Server {
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

// handle dispatches supported MCP protocol methods.
func (s *Server) handle(ctx context.Context, req rpcRequest) (any, *rpcError) {
	switch req.Method {
	case "initialize":
		return map[string]any{
			"protocolVersion": "2025-06-18",
			"capabilities": map[string]any{
				"tools": map[string]any{"listChanged": false},
			},
			"serverInfo": map[string]any{"name": "agentawesome-mcp", "version": "0.1.0"},
		}, nil
	case "tools/list":
		return map[string]any{"tools": toolDefinitions()}, nil
	case "tools/call":
		return s.handleToolCall(ctx, req.Params)
	default:
		return nil, &rpcError{Code: -32601, Message: "method not found", Data: req.Method}
	}
}

// handleToolCall invokes one MCP manager tool.
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

// callTool decodes tool arguments and calls the manager service.
func (s *Server) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "mcp.server_list":
		return map[string]any{"servers": s.service.Servers(ctx)}, nil
	case "mcp.status":
		var req serverRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Status(ctx, req.ServerID), nil
	case "mcp.start":
		var req serverRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Start(ctx, req.ServerID)
	case "mcp.stop":
		var req serverRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Stop(ctx, req.ServerID)
	case "mcp.restart":
		var req serverRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Restart(ctx, req.ServerID)
	case "mcp.tool_list":
		var req serverRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		tools, err := s.service.ToolList(ctx, req.ServerID)
		return map[string]any{"tools": tools}, err
	case "mcp.call":
		var req mcp.ToolCallRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Call(ctx, req)
	default:
		return nil, errors.New("MCP manager tool is not supported")
	}
}

// toolDefinitions returns tool descriptors for local MCP management.
func toolDefinitions() []map[string]any {
	names := []string{
		"mcp.server_list",
		"mcp.tool_list",
		"mcp.call",
		"mcp.start",
		"mcp.stop",
		"mcp.restart",
		"mcp.status",
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
	case "mcp.server_list":
		return "List configured local MCP servers and health state."
	case "mcp.tool_list":
		return "List tools exposed by one configured MCP server."
	case "mcp.call":
		return "Call one tool on one configured MCP server."
	case "mcp.start":
		return "Start one supervised local MCP server process."
	case "mcp.stop":
		return "Stop one supervised local MCP server process."
	case "mcp.restart":
		return "Restart one supervised local MCP server process."
	case "mcp.status":
		return "Read one configured MCP server status."
	default:
		return "Local MCP management tool."
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

// serverRequest stores one configured server id argument.
type serverRequest struct {
	ServerID string `json:"server_id"`
}
