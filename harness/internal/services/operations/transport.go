// This file exposes Operations HTTP routes and MCP tools.
package operations

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	platformmcp "agentawesome.dev/platform/mcptransport"
)

const maxOperationsRequestBytes int64 = 1 << 20

// HTTPServer serves Operations API and MCP routes.
type HTTPServer struct {
	service *Service
	mcp     platformmcp.Server
}

// NewHTTPServer creates an Operations transport adapter.
func NewHTTPServer(service *Service) *HTTPServer {
	server := &HTTPServer{service: service}
	server.mcp = platformmcp.Server{
		Info:            platformmcp.ServerInfo{Name: "agentawesome-operations", Version: "0.1.0"},
		MaxRequestBytes: maxOperationsRequestBytes,
		Tools:           operationToolDefinitions,
		Call:            server.callTool,
		FormatResult:    platformmcp.CompactToolResult,
	}
	return server
}

// Routes builds the Operations route multiplexer.
func (s *HTTPServer) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/api/operations/mcp", s.mcp)
	mux.HandleFunc("/api/operations", s.operationsHandler)
	mux.HandleFunc("/api/operations/", s.operationHandler)
	return mux
}

// operationsHandler lists or creates Operations.
func (s *HTTPServer) operationsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		ops, err := s.service.ListOperations(r.Context(), OperationQuery{
			WorkflowID: r.URL.Query().Get("workflow_id"),
			CodebaseID: r.URL.Query().Get("codebase_id"),
			Status:     r.URL.Query().Get("status"),
		})
		writeResult(w, map[string]any{"operations": ops}, err)
	case http.MethodPost:
		var req OperationRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		op, err := s.service.CreateOperation(r.Context(), req)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"operation": op})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

// operationHandler routes read, update, delete, preview, and start requests.
func (s *HTTPServer) operationHandler(w http.ResponseWriter, r *http.Request) {
	id, action := splitOperationPath(r.URL.Path)
	if id == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "operation id is required"})
		return
	}
	if id == "queue" {
		s.queueHandler(w, r, action)
		return
	}
	if id == "runs" {
		s.runAuditHandler(w, r, action)
		return
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		op, err := s.service.GetOperation(r.Context(), id)
		writeResult(w, map[string]any{"operation": op}, err)
	case r.Method == http.MethodPut && action == "":
		var req OperationRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		op, err := s.service.UpdateOperation(r.Context(), id, req)
		writeResult(w, map[string]any{"operation": op}, err)
	case r.Method == http.MethodDelete && action == "":
		writeResult(w, map[string]any{"deleted": id}, s.service.DeleteOperation(r.Context(), id))
	case r.Method == http.MethodPost && action == "preview":
		var req OperationRunRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		preview, err := s.service.PreviewOperationRun(r.Context(), id, req)
		writeResult(w, map[string]any{"preview": preview}, err)
	case r.Method == http.MethodPost && action == "start":
		var req OperationRunRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		result, err := s.service.StartOperation(r.Context(), id, req)
		writeResult(w, map[string]any{"operation_run": result}, err)
	case r.Method == http.MethodPost && action == "enqueue":
		var req OperationRunRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		item, err := s.service.EnqueueOperationRun(r.Context(), id, req)
		writeResult(w, map[string]any{"queued_run": item}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "operation route not found"})
	}
}

// runAuditHandler serves immutable Operation run audit snapshots.
func (s *HTTPServer) runAuditHandler(w http.ResponseWriter, r *http.Request, action string) {
	parts := strings.Split(strings.Trim(action, "/"), "/")
	if r.Method != http.MethodGet || len(parts) != 2 || parts[0] == "" || parts[1] != "snapshot" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "operation run route not found"})
		return
	}
	snapshot, err := s.service.GetOperationRunSnapshot(r.Context(), parts[0])
	writeResult(w, map[string]any{"snapshot": snapshot}, err)
}

// queueHandler routes durable Operation run queue requests.
func (s *HTTPServer) queueHandler(w http.ResponseWriter, r *http.Request, action string) {
	switch {
	case r.Method == http.MethodGet && action == "":
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		items, err := s.service.ListQueuedOperationRuns(r.Context(), OperationRunQueueQuery{
			Status:   r.URL.Query().Get("status"),
			TargetID: r.URL.Query().Get("target_id"),
			Limit:    limit,
		})
		writeResult(w, map[string]any{"queued_runs": items}, err)
	case r.Method == http.MethodPost && action == "lease":
		var req OperationRunLeaseRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		lease, err := s.service.LeaseQueuedOperationRun(r.Context(), req)
		writeResult(w, map[string]any{"lease": lease}, err)
	case r.Method == http.MethodPost && action == "recover":
		count, err := s.service.RecoverExpiredQueuedOperationRunLeases(r.Context())
		writeResult(w, map[string]any{"recovered": count}, err)
	default:
		s.queueItemHandler(w, r, action)
	}
}

// queueItemHandler routes item-specific queue lease requests.
func (s *HTTPServer) queueItemHandler(w http.ResponseWriter, r *http.Request, action string) {
	parts := strings.Split(strings.Trim(action, "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "operation queue route not found"})
		return
	}
	queueID, queueAction := parts[0], parts[1]
	switch {
	case r.Method == http.MethodPost && queueAction == "renew":
		var req OperationRunLeaseRenewRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		lease, err := s.service.RenewQueuedOperationRunLease(r.Context(), queueID, req)
		writeResult(w, map[string]any{"lease": lease}, err)
	case r.Method == http.MethodPost && queueAction == "start":
		var req operationRunLeaseIDRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		result, err := s.service.StartQueuedOperationRun(r.Context(), queueID, req.LeaseID)
		writeResult(w, map[string]any{"operation_run": result}, err)
	case r.Method == http.MethodPost && queueAction == "release":
		var req OperationRunLeaseReleaseRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		item, err := s.service.ReleaseQueuedOperationRunLease(r.Context(), queueID, req)
		writeResult(w, map[string]any{"queued_run": item}, err)
	case r.Method == http.MethodPost && queueAction == "cancel":
		item, err := s.service.CancelQueuedOperationRun(r.Context(), queueID)
		writeResult(w, map[string]any{"queued_run": item}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "operation queue route not found"})
	}
}

// callTool decodes and invokes one Operations MCP tool.
func (s *HTTPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "operation_list":
		var req OperationQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		ops, err := s.service.ListOperations(ctx, req)
		return map[string]any{"operations": ops}, err
	case "operation_get":
		var req operationIDArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		op, err := s.service.GetOperation(ctx, req.OperationID)
		return map[string]any{"operation": op}, err
	case "operation_run_snapshot":
		var req operationRunIDArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		snapshot, err := s.service.GetOperationRunSnapshot(ctx, req.RunID)
		return map[string]any{"snapshot": snapshot}, err
	case "operation_start":
		var req operationStartArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		result, err := s.service.StartOperation(ctx, req.OperationID, req.OperationRunRequest)
		return map[string]any{"operation_run": result}, err
	case "operation_enqueue":
		var req operationStartArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		item, err := s.service.EnqueueOperationRun(ctx, req.OperationID, req.OperationRunRequest)
		return map[string]any{"queued_run": item}, err
	case "operation_queue_list":
		var req OperationRunQueueQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		items, err := s.service.ListQueuedOperationRuns(ctx, req)
		return map[string]any{"queued_runs": items}, err
	default:
		return nil, fmt.Errorf("operations tool %q is not supported", name)
	}
}

// operationToolDefinitions returns Operations MCP tool descriptors.
func operationToolDefinitions() []map[string]any {
	return []map[string]any{
		tool("operation_list", "List saved Operations.", map[string]any{
			"workflow_id": stringSchema("Filter by workflow id."),
			"codebase_id": stringSchema("Filter by codebase id."),
			"status":      stringSchema("Filter by operation status."),
		}, []string{}),
		tool("operation_get", "Load one saved Operation.", map[string]any{
			"operation_id": stringSchema("Operation id."),
		}, []string{"operation_id"}),
		tool("operation_run_snapshot", "Load immutable Operation audit data for a workflow run.", map[string]any{
			"run_id": stringSchema("Workflow run id."),
		}, []string{"run_id"}),
		tool("operation_start", "Start one saved Operation after shared input resolution.", map[string]any{
			"operation_id":  stringSchema("Operation id."),
			"input":         mapSchema("Run request input values."),
			"codebase_name": stringSchema("Optional codebase name, id, or alias for this run."),
			"source":        stringSchema("Start source such as slack, ui, api, schedule, or task."),
			"task":          mapSchema("Optional structured task context."),
		}, []string{"operation_id"}),
		tool("operation_enqueue", "Queue one saved Operation for a Computer or Server target.", map[string]any{
			"operation_id":  stringSchema("Operation id."),
			"input":         mapSchema("Run request input values."),
			"codebase_name": stringSchema("Optional codebase name, id, or alias for this run."),
			"source":        stringSchema("Start source such as schedule, task, api, or slack."),
			"task":          mapSchema("Optional structured task context."),
		}, []string{"operation_id"}),
		tool("operation_queue_list", "List queued Operation runs.", map[string]any{
			"status":    stringSchema("Filter by queue status."),
			"target_id": stringSchema("Filter by eligible Computer or Server target."),
			"limit":     integerSchema("Maximum queued runs to return."),
		}, []string{}),
	}
}

// tool creates one MCP tool definition.
func tool(name string, description string, properties map[string]any, required []string) map[string]any {
	return map[string]any{
		"name":        name,
		"title":       name,
		"description": description,
		"inputSchema": objectSchema(properties, required),
	}
}

// objectSchema creates a JSON object schema.
func objectSchema(properties map[string]any, required []string) map[string]any {
	schema := map[string]any{"type": "object", "properties": properties, "additionalProperties": false}
	if len(required) > 0 {
		schema["required"] = required
	}
	return schema
}

// stringSchema creates a JSON string schema.
func stringSchema(description string) map[string]any {
	return map[string]any{"type": "string", "description": description}
}

// integerSchema creates a JSON integer schema.
func integerSchema(description string) map[string]any {
	return map[string]any{"type": "integer", "description": description}
}

// mapSchema creates a JSON object map schema.
func mapSchema(description string) map[string]any {
	return map[string]any{"type": "object", "description": description, "additionalProperties": true}
}

// decodeArgs unmarshals MCP tool arguments.
func decodeArgs(args json.RawMessage, target any) error {
	if len(args) == 0 || string(args) == "null" {
		args = []byte("{}")
	}
	return json.Unmarshal(args, target)
}

// decodeHTTPRequestJSON decodes one bounded HTTP JSON body.
func decodeHTTPRequestJSON(w http.ResponseWriter, r *http.Request, target any) error {
	body := http.MaxBytesReader(w, r.Body, maxOperationsRequestBytes)
	defer body.Close()
	return json.NewDecoder(body).Decode(target)
}

// writeResult writes a success or error response.
func writeResult(w http.ResponseWriter, body map[string]any, err error) {
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, body)
}

// writeJSON writes one JSON response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// splitOperationPath returns the operation id and optional action suffix.
func splitOperationPath(path string) (string, string) {
	tail := strings.Trim(strings.TrimPrefix(path, "/api/operations/"), "/")
	parts := strings.Split(tail, "/")
	if len(parts) == 0 {
		return "", ""
	}
	action := ""
	if len(parts) > 1 {
		action = strings.Join(parts[1:], "/")
	}
	return parts[0], action
}

// operationRunLeaseIDRequest stores one queue lease id request.
type operationRunLeaseIDRequest struct {
	LeaseID string `json:"lease_id"`
}

// operationIDArgs stores one operation id MCP request.
type operationIDArgs struct {
	OperationID string `json:"operation_id"`
}

// operationRunIDArgs stores one workflow run id MCP request.
type operationRunIDArgs struct {
	RunID string `json:"run_id"`
}

// operationStartArgs stores one generic Operation start MCP request.
type operationStartArgs struct {
	OperationID string `json:"operation_id"`
	OperationRunRequest
}
