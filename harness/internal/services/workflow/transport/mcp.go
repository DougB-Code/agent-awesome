// This file serves workflow control tools over MCP JSON-RPC.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	platformmcp "agentawesome.dev/platform/mcptransport"

	"agentawesome/internal/services/workflow/runtime"
)

const workflowMCPVersion = "0.1.0"

// MCPServer serves the workflow MCP tool surface.
type MCPServer struct {
	service *runtime.Service
	mcp     platformmcp.Server
}

// NewMCPServer creates an MCP transport adapter for workflow control.
func NewMCPServer(service *runtime.Service) *MCPServer {
	server := &MCPServer{service: service}
	server.mcp = platformmcp.Server{
		Info:            platformmcp.ServerInfo{Name: "agentawesome-workflow", Version: workflowMCPVersion},
		MaxRequestBytes: maxRequestBytes,
		Tools:           workflowToolDefinitions,
		Call:            server.callTool,
		FormatResult:    platformmcp.CompactToolResult,
	}
	return server
}

// ServeHTTP handles JSON-RPC MCP requests.
func (s *MCPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mcp.ServeHTTP(w, r)
}

// callTool decodes workflow tool arguments and calls the service.
func (s *MCPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "workflow_list":
		return keyedResult("definitions", func() (any, error) {
			return s.service.ListDefinitions(ctx)
		})
	case "workflow_describe":
		return decodeWorkflowArgs(args, func(req definitionRequest) (any, error) {
			def, ok := s.service.DescribeDefinition(req.DefinitionID)
			if !ok {
				return nil, errors.New("workflow definition not found")
			}
			return map[string]any{"definition": def}, nil
		})
	case "workflow_graph_dot":
		return decodeWorkflowArgs(args, func(req definitionRequest) (any, error) {
			dot, ok := s.service.DefinitionDOT(req.DefinitionID)
			if !ok {
				return nil, errors.New("workflow definition not found")
			}
			return map[string]any{"dot": dot}, nil
		})
	case "workflow_start":
		return decodeKeyedResult(args, "run", func(req startRequest) (any, error) {
			return s.service.StartWorkflow(ctx, req.DefinitionID, req.Input)
		})
	case "workflow_status":
		return decodeKeyedResult(args, "run", func(req runRequest) (any, error) {
			return s.service.Status(ctx, req.RunID)
		})
	case "workflow_signal":
		return decodeKeyedResult(args, "run", func(req workflowSignalRequest) (any, error) {
			return s.service.Signal(ctx, req.RunID, req.Signal, req.Payload)
		})
	case "workflow_cancel":
		return decodeKeyedResult(args, "run", func(req runRequest) (any, error) {
			return s.service.Cancel(ctx, req.RunID)
		})
	case "workflow_history":
		return decodeKeyedResult(args, "events", func(req runRequest) (any, error) {
			return s.service.History(ctx, req.RunID)
		})
	case "workflow_action_types":
		return map[string]any{"action_types": s.service.ActionTypes()}, nil
	case "workflow_manifests":
		return map[string]any{"manifests": s.service.ActionManifests()}, nil
	case "workflow_mapping_preview":
		return decodeKeyedResult(args, "preview", func(req runtime.MappingPreviewRequest) (any, error) {
			return s.service.PreviewMapping(ctx, req)
		})
	case "workflow_design_artifacts":
		return keyedResult("artifacts", func() (any, error) {
			return s.service.ListDesignArtifacts(ctx)
		})
	case "workflow_design_suggest":
		return decodeKeyedResult(args, "suggestion", func(req runtime.DesignSuggestionRequest) (any, error) {
			return s.service.SuggestDesignArtifacts(ctx, req)
		})
	case "workflow_adapter_choice":
		return decodeKeyedResult(args, "adapter_choice", func(req runtime.AdapterChoiceRequest) (any, error) {
			return s.service.SaveAdapterChoice(ctx, req)
		})
	case "workflow_observed_contracts":
		return decodeKeyedResult(args, "observed_contracts", func(req runtime.ObservedContractQuery) (any, error) {
			return s.service.ListObservedContracts(ctx, req)
		})
	case "workflow_draft_create":
		return decodeKeyedResult(args, "draft", func(req runtime.DraftRequest) (any, error) {
			return s.service.CreateDraft(ctx, req)
		})
	case "workflow_draft_update":
		return decodeKeyedResult(args, "draft", func(req workflowDraftUpdateRequest) (any, error) {
			return s.service.UpdateDraft(ctx, req.DraftID, runtime.DraftRequest{
				Kind:        req.Kind,
				Name:        req.Name,
				Description: req.Description,
				Body:        req.Body,
			})
		})
	case "workflow_draft_validate":
		return decodeKeyedResult(args, "validation", func(req workflowDraftRequest) (any, error) {
			return s.service.ValidateDraft(ctx, req.DraftID)
		})
	case "workflow_edge_compatibility":
		return decodeKeyedResult(args, "compatibility", func(req workflowEdgeCompatibilityRequest) (any, error) {
			return s.service.CheckDraftEdgeCompatibility(ctx, req.DraftID, req.EdgeCompatibilityRequest)
		})
	case "workflow_draft_publish":
		return decodeKeyedResult(args, "definition", func(req workflowDraftRequest) (any, error) {
			return s.service.PublishDraft(ctx, req.DraftID)
		})
	default:
		return nil, errors.New("workflow tool is not supported")
	}
}

// decodeKeyedResult decodes tool arguments and wraps the service result.
func decodeKeyedResult[T any](args json.RawMessage, key string, call func(T) (any, error)) (any, error) {
	return decodeWorkflowArgs(args, func(req T) (any, error) {
		value, err := call(req)
		return map[string]any{key: value}, err
	})
}

// decodeWorkflowArgs decodes tool arguments before running workflow logic.
func decodeWorkflowArgs[T any](args json.RawMessage, call func(T) (any, error)) (any, error) {
	var req T
	if err := decodeArgs(args, &req); err != nil {
		return nil, err
	}
	return call(req)
}

// keyedResult wraps a service call return value under its MCP response key.
func keyedResult(key string, call func() (any, error)) (any, error) {
	value, err := call()
	return map[string]any{key: value}, err
}

// workflowToolDefinitions returns the MCP tool descriptors.
func workflowToolDefinitions() []map[string]any {
	names := []string{
		"workflow_list",
		"workflow_describe",
		"workflow_graph_dot",
		"workflow_start",
		"workflow_status",
		"workflow_signal",
		"workflow_cancel",
		"workflow_history",
		"workflow_action_types",
		"workflow_manifests",
		"workflow_mapping_preview",
		"workflow_design_artifacts",
		"workflow_design_suggest",
		"workflow_adapter_choice",
		"workflow_observed_contracts",
		"workflow_draft_create",
		"workflow_draft_update",
		"workflow_draft_validate",
		"workflow_edge_compatibility",
		"workflow_draft_publish",
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
	case "workflow_graph_dot":
		return "Return a Graphviz DOT graph for one workflow definition."
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
	case "workflow_manifests":
		return "List AA-owned manifests for workflow action boundaries."
	case "workflow_mapping_preview":
		return "Preview a deterministic AA Mapping Spec against sample input."
	case "workflow_design_artifacts":
		return "List persisted deterministic design-time workflow artifacts."
	case "workflow_design_suggest":
		return "Ask the configured design assistant to propose deterministic workflow artifacts."
	case "workflow_adapter_choice":
		return "Persist a user-confirmed adapter choice for a draft workflow edge."
	case "workflow_observed_contracts":
		return "List runtime-observed output contracts that can strengthen workflow node contracts."
	case "workflow_draft_create":
		return "Create an editable workflow draft."
	case "workflow_draft_update":
		return "Update an editable workflow draft."
	case "workflow_draft_validate":
		return "Validate a workflow draft before publishing."
	case "workflow_edge_compatibility":
		return "Check whether two draft workflow nodes can be connected."
	case "workflow_draft_publish":
		return "Publish a workflow draft as an installed definition."
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

// workflowEdgeCompatibilityRequest stores one draft edge compatibility request.
type workflowEdgeCompatibilityRequest struct {
	DraftID string `json:"draft_id"`
	runtime.EdgeCompatibilityRequest
}
