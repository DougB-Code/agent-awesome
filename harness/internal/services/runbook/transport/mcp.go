// This file serves runbook control tools over MCP JSON-RPC.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	platformmcp "agentawesome.dev/platform/mcptransport"

	"agentawesome/internal/services/runbook/runtime"
)

const runbookMCPVersion = "0.1.0"

// MCPServer serves the runbook MCP tool surface.
type MCPServer struct {
	service *runtime.Service
	mcp     platformmcp.Server
}

// NewMCPServer creates an MCP transport adapter for runbook control.
func NewMCPServer(service *runtime.Service) *MCPServer {
	server := &MCPServer{service: service}
	server.mcp = platformmcp.Server{
		Info:            platformmcp.ServerInfo{Name: "agentawesome-runbook", Version: runbookMCPVersion},
		MaxRequestBytes: maxRequestBytes,
		Tools:           runbookToolDefinitions,
		Call:            server.callTool,
		FormatResult:    platformmcp.CompactToolResult,
	}
	return server
}

// ServeHTTP handles JSON-RPC MCP requests.
func (s *MCPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mcp.ServeHTTP(w, r)
}

// callTool decodes runbook tool arguments and calls the service.
func (s *MCPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "runbook_list":
		return keyedResult("definitions", func() (any, error) {
			return s.service.ListDefinitions(ctx)
		})
	case "runbook_describe":
		return decodeRunbookArgs(args, func(req definitionRequest) (any, error) {
			def, ok := s.service.DescribeDefinition(req.DefinitionID)
			if !ok {
				return nil, errors.New("runbook definition not found")
			}
			return map[string]any{"definition": def}, nil
		})
	case "runbook_graph_dot":
		return decodeRunbookArgs(args, func(req definitionRequest) (any, error) {
			dot, ok := s.service.DefinitionDOT(req.DefinitionID)
			if !ok {
				return nil, errors.New("runbook definition not found")
			}
			return map[string]any{"dot": dot}, nil
		})
	case "runbook_start":
		return decodeKeyedResult(args, "run", func(req startRequest) (any, error) {
			return s.service.StartRunbook(ctx, req.DefinitionID, req.Input)
		})
	case "runbook_status":
		return decodeKeyedResult(args, "run", func(req runRequest) (any, error) {
			return s.service.Status(ctx, req.RunID)
		})
	case "runbook_signal":
		return decodeKeyedResult(args, "run", func(req runbookSignalRequest) (any, error) {
			return s.service.Signal(ctx, req.RunID, req.Signal, req.Payload)
		})
	case "runbook_cancel":
		return decodeKeyedResult(args, "run", func(req runRequest) (any, error) {
			return s.service.Cancel(ctx, req.RunID)
		})
	case "runbook_history":
		return decodeKeyedResult(args, "events", func(req runRequest) (any, error) {
			return s.service.History(ctx, req.RunID)
		})
	case "runbook_action_types":
		return map[string]any{"action_types": s.service.ActionTypes()}, nil
	case "runbook_manifests":
		return map[string]any{"manifests": s.service.ActionManifests()}, nil
	case "runbook_mapping_preview":
		return decodeKeyedResult(args, "preview", func(req runtime.MappingPreviewRequest) (any, error) {
			return s.service.PreviewMapping(ctx, req)
		})
	case "runbook_design_artifacts":
		return keyedResult("artifacts", func() (any, error) {
			return s.service.ListDesignArtifacts(ctx)
		})
	case "runbook_design_suggest":
		return decodeKeyedResult(args, "suggestion", func(req runtime.DesignSuggestionRequest) (any, error) {
			return s.service.SuggestDesignArtifacts(ctx, req)
		})
	case "runbook_observed_contracts":
		return decodeKeyedResult(args, "observed_contracts", func(req runtime.ObservedContractQuery) (any, error) {
			return s.service.ListObservedContracts(ctx, req)
		})
	case "runbook_draft_create":
		return decodeKeyedResult(args, "draft", func(req runtime.DraftRequest) (any, error) {
			return s.service.CreateDraft(ctx, req)
		})
	case "runbook_draft_update":
		return decodeKeyedResult(args, "draft", func(req runbookDraftUpdateRequest) (any, error) {
			return s.service.UpdateDraft(ctx, req.DraftID, runtime.DraftRequest{
				Kind:        req.Kind,
				Name:        req.Name,
				Description: req.Description,
				Body:        req.Body,
			})
		})
	case "runbook_draft_validate":
		return decodeKeyedResult(args, "validation", func(req runbookDraftRequest) (any, error) {
			return s.service.ValidateDraft(ctx, req.DraftID)
		})
	case "runbook_draft_publish":
		return decodeKeyedResult(args, "definition", func(req runbookDraftRequest) (any, error) {
			return s.service.PublishDraft(ctx, req.DraftID)
		})
	default:
		return nil, errors.New("runbook tool is not supported")
	}
}

// decodeKeyedResult decodes tool arguments and wraps the service result.
func decodeKeyedResult[T any](args json.RawMessage, key string, call func(T) (any, error)) (any, error) {
	return decodeRunbookArgs(args, func(req T) (any, error) {
		value, err := call(req)
		return map[string]any{key: value}, err
	})
}

// decodeRunbookArgs decodes tool arguments before running runbook logic.
func decodeRunbookArgs[T any](args json.RawMessage, call func(T) (any, error)) (any, error) {
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

// runbookToolDefinitions returns the MCP tool descriptors.
func runbookToolDefinitions() []map[string]any {
	names := []string{
		"runbook_list",
		"runbook_describe",
		"runbook_graph_dot",
		"runbook_start",
		"runbook_status",
		"runbook_signal",
		"runbook_cancel",
		"runbook_history",
		"runbook_action_types",
		"runbook_manifests",
		"runbook_mapping_preview",
		"runbook_design_artifacts",
		"runbook_design_suggest",
		"runbook_observed_contracts",
		"runbook_draft_create",
		"runbook_draft_update",
		"runbook_draft_validate",
		"runbook_draft_publish",
	}
	tools := make([]map[string]any, 0, len(names))
	for _, name := range names {
		tools = append(tools, map[string]any{
			"name":        name,
			"description": runbookToolDescription(name),
			"inputSchema": map[string]any{"type": "object"},
		})
	}
	return tools
}

// runbookToolDescription returns a concise model-facing tool description.
func runbookToolDescription(name string) string {
	switch name {
	case "runbook_list":
		return "List installed runbook definitions."
	case "runbook_describe":
		return "Describe one installed runbook definition."
	case "runbook_graph_dot":
		return "Return a Graphviz DOT state-machine view for one runbook definition."
	case "runbook_start":
		return "Start a durable runbook run from a definition id."
	case "runbook_status":
		return "Get one runbook run status."
	case "runbook_signal":
		return "Send a signal or user response to one runbook run."
	case "runbook_cancel":
		return "Cancel one runbook run."
	case "runbook_history":
		return "List durable events for one runbook run."
	case "runbook_action_types":
		return "List runbook action types available for authoring."
	case "runbook_manifests":
		return "List AA-owned manifests for runbook action boundaries."
	case "runbook_mapping_preview":
		return "Preview a deterministic AA Mapping Spec against sample input."
	case "runbook_design_artifacts":
		return "List persisted deterministic design-time runbook artifacts."
	case "runbook_design_suggest":
		return "Ask the configured design assistant to propose deterministic runbook artifacts."
	case "runbook_observed_contracts":
		return "List runtime-observed output contracts that can strengthen runbook node contracts."
	case "runbook_draft_create":
		return "Create an editable runbook draft."
	case "runbook_draft_update":
		return "Update an editable runbook draft."
	case "runbook_draft_validate":
		return "Validate a runbook draft before publishing."
	case "runbook_draft_publish":
		return "Publish a runbook draft as an installed definition."
	default:
		return "Runbook control tool."
	}
}

// decodeArgs unmarshals MCP tool arguments.
func decodeArgs(args json.RawMessage, target any) error {
	if len(args) == 0 {
		args = []byte(`{}`)
	}
	return json.Unmarshal(args, target)
}

// definitionRequest stores a runbook definition id argument.
type definitionRequest struct {
	DefinitionID string `json:"definition_id"`
}

// runRequest stores a runbook run id argument.
type runRequest struct {
	RunID string `json:"run_id"`
}

// runbookSignalRequest stores runbook signal arguments.
type runbookSignalRequest struct {
	RunID   string         `json:"run_id"`
	Signal  string         `json:"signal"`
	Payload map[string]any `json:"payload"`
}

// runbookDraftRequest stores one runbook draft id argument.
type runbookDraftRequest struct {
	DraftID string `json:"draft_id"`
}

// runbookDraftUpdateRequest stores runbook draft update arguments.
type runbookDraftUpdateRequest struct {
	DraftID     string         `json:"draft_id"`
	Kind        string         `json:"kind"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Body        map[string]any `json:"body"`
}
