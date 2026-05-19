// This file serves workflow control tools over MCP JSON-RPC.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"workflow/internal/runtime"
)

// MCPServer serves the workflow MCP tool surface.
type MCPServer struct {
	service *runtime.Service
}

// NewMCPServer creates an MCP transport adapter for workflow control.
func NewMCPServer(service *runtime.Service) *MCPServer {
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
				"name":    "agentawesome-workflow",
				"version": "0.1.0",
			},
		}, nil
	case "tools/list":
		return map[string]any{"tools": workflowToolDefinitions()}, nil
	case "tools/call":
		return s.handleToolCall(ctx, req.Params)
	default:
		return nil, &rpcError{Code: -32601, Message: "method not found", Data: req.Method}
	}
}

// handleToolCall invokes one workflow MCP tool.
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

// callTool decodes workflow tool arguments and calls the service.
func (s *MCPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "workflow_list":
		defs, err := s.service.ListDefinitions(ctx)
		return map[string]any{"definitions": defs}, err
	case "workflow_describe":
		var req definitionRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		def, ok := s.service.DescribeDefinition(req.DefinitionID)
		if !ok {
			return nil, errors.New("workflow definition not found")
		}
		return map[string]any{"definition": def}, nil
	case "workflow_start":
		var req startRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		run, err := s.service.StartWorkflow(ctx, req.DefinitionID, req.Input)
		return map[string]any{"run": run}, err
	case "workflow_status":
		var req runRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		run, err := s.service.Status(ctx, req.RunID)
		return map[string]any{"run": run}, err
	case "workflow_signal":
		var req workflowSignalRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		run, err := s.service.Signal(ctx, req.RunID, req.Signal, req.Payload)
		return map[string]any{"run": run}, err
	case "workflow_cancel":
		var req runRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		run, err := s.service.Cancel(ctx, req.RunID)
		return map[string]any{"run": run}, err
	case "workflow_history":
		var req runRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		events, err := s.service.History(ctx, req.RunID)
		return map[string]any{"events": events}, err
	case "workflow_action_types":
		return map[string]any{"action_types": s.service.ActionTypes()}, nil
	case "workflow_draft_create":
		var req runtime.DraftRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		draft, err := s.service.CreateDraft(ctx, req)
		return map[string]any{"draft": draft}, err
	case "workflow_draft_update":
		var req workflowDraftUpdateRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		draft, err := s.service.UpdateDraft(ctx, req.DraftID, runtime.DraftRequest{
			Kind:        req.Kind,
			Name:        req.Name,
			Description: req.Description,
			Body:        req.Body,
		})
		return map[string]any{"draft": draft}, err
	case "workflow_draft_validate":
		var req workflowDraftRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		result, err := s.service.ValidateDraft(ctx, req.DraftID)
		return map[string]any{"validation": result}, err
	case "workflow_draft_publish":
		var req workflowDraftRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		definition, err := s.service.PublishDraft(ctx, req.DraftID)
		return map[string]any{"definition": definition}, err
	case "workflow_template_list":
		templates, err := s.service.ListTemplates(ctx)
		return map[string]any{"templates": templates}, err
	case "workflow_template_instantiate":
		var req workflowTemplateInstantiateRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		draft, err := s.service.InstantiateTemplate(ctx, req.TemplateID, runtime.TemplateInstantiateRequest{
			Parameters: req.Parameters,
			Name:       req.Name,
		})
		return map[string]any{"draft": draft}, err
	case "workflow_agent_spec_list":
		specs, err := s.service.ListAgentSpecs(ctx)
		return map[string]any{"agent_specs": specs}, err
	case "workflow_agent_spec_create":
		var req runtime.AgentSpecRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		spec, err := s.service.CreateAgentSpec(ctx, req)
		return map[string]any{"agent_spec": spec}, err
	case "workflow_agent_spec_update":
		var req workflowAgentSpecUpdateRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		spec, err := s.service.UpdateAgentSpec(ctx, req.AgentSpecID, req.AgentSpecRequest)
		return map[string]any{"agent_spec": spec}, err
	case "workflow_agent_spec_delete":
		var req workflowAgentSpecRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return map[string]any{"deleted": req.AgentSpecID}, s.service.DeleteAgentSpec(ctx, req.AgentSpecID)
	default:
		return nil, errors.New("workflow tool is not supported")
	}
}

// workflowToolDefinitions returns the MCP tool descriptors.
func workflowToolDefinitions() []map[string]any {
	names := []string{
		"workflow_list",
		"workflow_describe",
		"workflow_start",
		"workflow_status",
		"workflow_signal",
		"workflow_cancel",
		"workflow_history",
		"workflow_action_types",
		"workflow_draft_create",
		"workflow_draft_update",
		"workflow_draft_validate",
		"workflow_draft_publish",
		"workflow_template_list",
		"workflow_template_instantiate",
		"workflow_agent_spec_list",
		"workflow_agent_spec_create",
		"workflow_agent_spec_update",
		"workflow_agent_spec_delete",
	}
	tools := make([]map[string]any, 0, len(names))
	for _, name := range names {
		tools = append(tools, map[string]any{
			"name":        name,
			"description": workflowToolDescription(name),
			"inputSchema": map[string]any{"type": "object"},
		})
	}
	return tools
}

// workflowToolDescription returns a concise model-facing tool description.
func workflowToolDescription(name string) string {
	switch name {
	case "workflow_list":
		return "List installed workflow definitions."
	case "workflow_describe":
		return "Describe one installed workflow definition."
	case "workflow_start":
		return "Start a durable workflow run from a definition id."
	case "workflow_status":
		return "Get one workflow run status."
	case "workflow_signal":
		return "Send a signal or user response to one workflow run."
	case "workflow_cancel":
		return "Cancel one workflow run."
	case "workflow_history":
		return "List durable events for one workflow run."
	case "workflow_action_types":
		return "List workflow action types available for authoring."
	case "workflow_draft_create":
		return "Create an editable workflow draft."
	case "workflow_draft_update":
		return "Update an editable workflow draft."
	case "workflow_draft_validate":
		return "Validate a workflow draft before publishing."
	case "workflow_draft_publish":
		return "Publish a workflow draft as an installed definition."
	case "workflow_template_list":
		return "List available workflow templates."
	case "workflow_template_instantiate":
		return "Create an editable draft from a workflow template."
	case "workflow_agent_spec_list":
		return "List reusable workflow agent specs."
	case "workflow_agent_spec_create":
		return "Create a reusable workflow agent spec."
	case "workflow_agent_spec_update":
		return "Update a reusable workflow agent spec."
	case "workflow_agent_spec_delete":
		return "Delete a reusable workflow agent spec."
	default:
		return "Workflow control tool."
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

// definitionRequest stores a workflow definition id argument.
type definitionRequest struct {
	DefinitionID string `json:"definition_id"`
}

// runRequest stores a workflow run id argument.
type runRequest struct {
	RunID string `json:"run_id"`
}

// workflowSignalRequest stores workflow signal arguments.
type workflowSignalRequest struct {
	RunID   string         `json:"run_id"`
	Signal  string         `json:"signal"`
	Payload map[string]any `json:"payload"`
}

// workflowDraftRequest stores one workflow draft id argument.
type workflowDraftRequest struct {
	DraftID string `json:"draft_id"`
}

// workflowDraftUpdateRequest stores workflow draft update arguments.
type workflowDraftUpdateRequest struct {
	DraftID     string         `json:"draft_id"`
	Kind        string         `json:"kind"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Body        map[string]any `json:"body"`
}

// workflowTemplateInstantiateRequest stores template instantiation arguments.
type workflowTemplateInstantiateRequest struct {
	TemplateID string         `json:"template_id"`
	Name       string         `json:"name"`
	Parameters map[string]any `json:"parameters"`
}

// workflowAgentSpecRequest stores one reusable agent spec id argument.
type workflowAgentSpecRequest struct {
	AgentSpecID string `json:"agent_spec_id"`
}

// workflowAgentSpecUpdateRequest stores reusable agent spec update arguments.
type workflowAgentSpecUpdateRequest struct {
	AgentSpecID string `json:"agent_spec_id"`
	runtime.AgentSpecRequest
}
