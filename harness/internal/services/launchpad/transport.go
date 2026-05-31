// This file exposes Launchpad HTTP routes and MCP tools.
package launchpad

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	platformmcp "agentawesome.dev/platform/mcptransport"
)

const maxLaunchpadRequestBytes int64 = 1 << 20

// HTTPServer serves Launchpad API and MCP routes.
type HTTPServer struct {
	service *Service
	mcp     platformmcp.Server
}

// NewHTTPServer creates an Launchpad transport adapter.
func NewHTTPServer(service *Service) *HTTPServer {
	server := &HTTPServer{service: service}
	server.mcp = platformmcp.Server{
		Info:            platformmcp.ServerInfo{Name: "agentawesome-launchpad", Version: "0.1.0"},
		MaxRequestBytes: maxLaunchpadRequestBytes,
		Tools:           launchToolDefinitions,
		Call:            server.callTool,
		FormatResult:    platformmcp.CompactToolResult,
	}
	return server
}

// Routes builds the Launchpad route multiplexer.
func (s *HTTPServer) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/api/launchpad/mcp", s.mcp)
	mux.HandleFunc("/api/launchpad", s.launchpadHandler)
	mux.HandleFunc("/api/launchpad/", s.launchHandler)
	return mux
}

// launchpadHandler lists or creates Launchpad.
func (s *HTTPServer) launchpadHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		ops, err := s.service.ListLaunchpad(r.Context(), LaunchQuery{
			RunbookID:  r.URL.Query().Get("runbook_id"),
			CodebaseID: r.URL.Query().Get("codebase_id"),
			Status:     r.URL.Query().Get("status"),
		})
		writeResult(w, map[string]any{"launchpad": ops}, err)
	case http.MethodPost:
		var req LaunchRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		op, err := s.service.CreateLaunch(r.Context(), req)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"launch": op})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

// launchHandler routes read, update, delete, preview, and start requests.
func (s *HTTPServer) launchHandler(w http.ResponseWriter, r *http.Request) {
	id, action := splitLaunchPath(r.URL.Path)
	if id == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "launch id is required"})
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
		op, err := s.service.GetLaunch(r.Context(), id)
		writeResult(w, map[string]any{"launch": op}, err)
	case r.Method == http.MethodPut && action == "":
		var req LaunchRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		op, err := s.service.UpdateLaunch(r.Context(), id, req)
		writeResult(w, map[string]any{"launch": op}, err)
	case r.Method == http.MethodDelete && action == "":
		writeResult(w, map[string]any{"deleted": id}, s.service.DeleteLaunch(r.Context(), id))
	case r.Method == http.MethodPost && action == "preview":
		var req LaunchRunRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		preview, err := s.service.PreviewLaunchRun(r.Context(), id, req)
		writeResult(w, map[string]any{"preview": preview}, err)
	case r.Method == http.MethodPost && action == "start":
		var req LaunchRunRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		result, err := s.service.StartLaunch(r.Context(), id, req)
		writeResult(w, map[string]any{"launch_run": result}, err)
	case r.Method == http.MethodPost && action == "enqueue":
		var req LaunchRunRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		item, err := s.service.EnqueueLaunchRun(r.Context(), id, req)
		writeResult(w, map[string]any{"queued_run": item}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "launch route not found"})
	}
}

// runAuditHandler serves immutable Launch run audit snapshots.
func (s *HTTPServer) runAuditHandler(w http.ResponseWriter, r *http.Request, action string) {
	parts := strings.Split(strings.Trim(action, "/"), "/")
	if r.Method != http.MethodGet || len(parts) != 2 || parts[0] == "" || parts[1] != "snapshot" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "launch run route not found"})
		return
	}
	snapshot, err := s.service.GetLaunchRunSnapshot(r.Context(), parts[0])
	writeResult(w, map[string]any{"snapshot": snapshot}, err)
}

// queueHandler routes durable Launch run queue requests.
func (s *HTTPServer) queueHandler(w http.ResponseWriter, r *http.Request, action string) {
	switch {
	case r.Method == http.MethodGet && action == "":
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		items, err := s.service.ListQueuedLaunchRuns(r.Context(), LaunchRunQueueQuery{
			Status:   r.URL.Query().Get("status"),
			TargetID: r.URL.Query().Get("target_id"),
			Limit:    limit,
		})
		writeResult(w, map[string]any{"queued_runs": items}, err)
	case r.Method == http.MethodPost && action == "lease":
		var req LaunchRunLeaseRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		lease, err := s.service.LeaseQueuedLaunchRun(r.Context(), req)
		writeResult(w, map[string]any{"lease": lease}, err)
	case r.Method == http.MethodPost && action == "recover":
		count, err := s.service.RecoverExpiredQueuedLaunchRunLeases(r.Context())
		writeResult(w, map[string]any{"recovered": count}, err)
	case r.Method == http.MethodPost && action == "enqueue-due":
		var req launchScheduleEnqueueRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		now := time.Now().UTC()
		if strings.TrimSpace(req.Now) != "" {
			parsed, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(req.Now))
			if err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			now = parsed
		}
		result, err := s.service.EnqueueDueScheduledLaunchpad(r.Context(), now)
		writeResult(w, map[string]any{"schedule": result}, err)
	default:
		s.queueItemHandler(w, r, action)
	}
}

// queueItemHandler routes item-specific queue lease requests.
func (s *HTTPServer) queueItemHandler(w http.ResponseWriter, r *http.Request, action string) {
	parts := strings.Split(strings.Trim(action, "/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "launch queue route not found"})
		return
	}
	queueID, queueAction := parts[0], parts[1]
	switch {
	case r.Method == http.MethodPost && queueAction == "renew":
		var req LaunchRunLeaseRenewRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		lease, err := s.service.RenewQueuedLaunchRunLease(r.Context(), queueID, req)
		writeResult(w, map[string]any{"lease": lease}, err)
	case r.Method == http.MethodPost && queueAction == "start":
		var req launchRunLeaseIDRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		result, err := s.service.StartQueuedLaunchRun(r.Context(), queueID, req.LeaseID)
		writeResult(w, map[string]any{"launch_run": result}, err)
	case r.Method == http.MethodPost && queueAction == "release":
		var req LaunchRunLeaseReleaseRequest
		if err := decodeHTTPRequestJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		item, err := s.service.ReleaseQueuedLaunchRunLease(r.Context(), queueID, req)
		writeResult(w, map[string]any{"queued_run": item}, err)
	case r.Method == http.MethodPost && queueAction == "cancel":
		item, err := s.service.CancelQueuedLaunchRun(r.Context(), queueID)
		writeResult(w, map[string]any{"queued_run": item}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "launch queue route not found"})
	}
}

// callTool decodes and invokes one Launchpad MCP tool.
func (s *HTTPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "launchpad_list":
		var req LaunchQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		ops, err := s.service.ListLaunchpad(ctx, req)
		return map[string]any{"launchpad": ops}, err
	case "launchpad_get":
		var req launchIDArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		op, err := s.service.GetLaunch(ctx, req.LaunchID)
		return map[string]any{"launch": op}, err
	case "launchpad_run_snapshot":
		var req launchRunIDArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		snapshot, err := s.service.GetLaunchRunSnapshot(ctx, req.RunID)
		return map[string]any{"snapshot": snapshot}, err
	case "launchpad_start":
		var req launchStartArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		result, err := s.service.StartLaunch(ctx, req.LaunchID, req.LaunchRunRequest)
		return map[string]any{"launch_run": result}, err
	case "launchpad_enqueue":
		var req launchStartArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		item, err := s.service.EnqueueLaunchRun(ctx, req.LaunchID, req.LaunchRunRequest)
		return map[string]any{"queued_run": item}, err
	case "launchpad_queue_list":
		var req LaunchRunQueueQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		items, err := s.service.ListQueuedLaunchRuns(ctx, req)
		return map[string]any{"queued_runs": items}, err
	default:
		return nil, fmt.Errorf("launchpad tool %q is not supported", name)
	}
}

// launchToolDefinitions returns Launchpad MCP tool descriptors.
func launchToolDefinitions() []map[string]any {
	return []map[string]any{
		tool("launchpad_list", "List saved Launchpad.", map[string]any{
			"runbook_id":  stringSchema("Filter by runbook id."),
			"codebase_id": stringSchema("Filter by codebase id."),
			"status":      stringSchema("Filter by launch status."),
		}, []string{}),
		tool("launchpad_get", "Load one saved Launch.", map[string]any{
			"launch_id": stringSchema("Launch id."),
		}, []string{"launch_id"}),
		tool("launchpad_run_snapshot", "Load immutable Launch audit data for a runbook run.", map[string]any{
			"run_id": stringSchema("Runbook run id."),
		}, []string{"run_id"}),
		tool("launchpad_start", "Start one saved Launch after shared input resolution.", map[string]any{
			"launch_id":     stringSchema("Launch id."),
			"input":         mapSchema("Run request input values."),
			"codebase_name": stringSchema("Optional codebase name, id, or alias for this run."),
			"source":        stringSchema("Start source such as slack, ui, api, schedule, or task."),
			"task":          mapSchema("Optional structured task context."),
		}, []string{"launch_id"}),
		tool("launchpad_enqueue", "Queue one saved Launch for a Computer or Server target.", map[string]any{
			"launch_id":     stringSchema("Launch id."),
			"input":         mapSchema("Run request input values."),
			"codebase_name": stringSchema("Optional codebase name, id, or alias for this run."),
			"source":        stringSchema("Start source such as schedule, task, api, or slack."),
			"task":          mapSchema("Optional structured task context."),
		}, []string{"launch_id"}),
		tool("launchpad_queue_list", "List queued Launch runs.", map[string]any{
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
	body := http.MaxBytesReader(w, r.Body, maxLaunchpadRequestBytes)
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

// splitLaunchPath returns the launch id and optional action suffix.
func splitLaunchPath(path string) (string, string) {
	tail := strings.Trim(strings.TrimPrefix(path, "/api/launchpad/"), "/")
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

// launchRunLeaseIDRequest stores one queue lease id request.
type launchRunLeaseIDRequest struct {
	LeaseID string `json:"lease_id"`
}

// launchScheduleEnqueueRequest stores an optional deterministic schedule clock.
type launchScheduleEnqueueRequest struct {
	Now string `json:"now,omitempty"`
}

// launchIDArgs stores one launch id MCP request.
type launchIDArgs struct {
	LaunchID string `json:"launch_id"`
}

// launchRunIDArgs stores one runbook run id MCP request.
type launchRunIDArgs struct {
	RunID string `json:"run_id"`
}

// launchStartArgs stores one generic Launch start MCP request.
type launchStartArgs struct {
	LaunchID string `json:"launch_id"`
	LaunchRunRequest
}
