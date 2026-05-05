package transport

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"memory/internal/memory/domain"
	"memory/internal/memory/service"
)

// MCPServer serves a small MCP-compatible JSON-RPC tool surface.
type MCPServer struct {
	service *service.Service
}

// NewMCPServer creates an MCP transport adapter.
func NewMCPServer(memoryService *service.Service) *MCPServer {
	return &MCPServer{service: memoryService}
}

// ServeHTTP handles JSON-RPC MCP requests over HTTP.
func (s *MCPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	defer r.Body.Close()
	var req rpcRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
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
				"name":    "agentawesome-memory",
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

// handleToolCall invokes a named memory tool.
func (s *MCPServer) handleToolCall(ctx context.Context, params json.RawMessage) (any, *rpcError) {
	if s.service == nil {
		return nil, &rpcError{Code: -32603, Message: errMissingService.Error()}
	}
	var call toolCallParams
	if err := json.Unmarshal(params, &call); err != nil {
		return nil, &rpcError{Code: -32602, Message: "invalid params", Data: err.Error()}
	}
	if call.Name == "" {
		return nil, &rpcError{Code: -32602, Message: "tool name is required"}
	}
	result, err := s.callTool(ctx, call.Name, call.Arguments)
	if err != nil {
		return toolResult(map[string]string{"error": err.Error()}, true), nil
	}
	return toolResult(result, false), nil
}

// callTool decodes tool arguments and calls the memory service.
func (s *MCPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	switch name {
	case "save_memory_candidate":
		var req domain.CaptureRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.Capture(ctx, req)
	case "search_memory":
		var req domain.RetrievalQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.SearchMemory(ctx, req)
	case "search_sources":
		var req domain.RetrievalQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.SearchSources(ctx, req)
	case "load_entity_page":
		var req loadEntityPageArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.LoadEntityPage(ctx, req.Scope, req.EntityID, req.Title)
	case "load_timeline":
		var req loadTimelineArgs
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.LoadTimeline(ctx, req.Scope, req.Topic, req.EntityID)
	case "refresh_compiled_page":
		var req domain.RefreshPageRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.RefreshCompiledPage(ctx, req)
	case "repair_memory_record":
		var req domain.RepairRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.RepairMemoryRecord(ctx, req)
	case "submit_memory_correction":
		var req domain.CorrectionRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.SubmitMemoryCorrection(ctx, req)
	case "query_context_graph":
		var req domain.GraphQueryRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.QueryContextGraph(ctx, req)
	case "create_task":
		var req domain.CreateTaskRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.CreateTask(ctx, req)
	case "get_task":
		var req domain.TaskIDRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.GetTask(ctx, req)
	case "list_tasks":
		var req domain.TaskQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.ListTasks(ctx, req)
	case "task_graph_projection":
		var req domain.TaskGraphProjectionQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.TaskGraphProjection(ctx, req)
	case "update_task":
		var req domain.UpdateTaskRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.UpdateTask(ctx, req)
	case "complete_task":
		var req domain.TaskIDRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.CompleteTask(ctx, req)
	case "cancel_task":
		var req domain.TaskIDRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.CancelTask(ctx, req)
	case "delete_task":
		var req domain.TaskIDRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		if err := s.service.DeleteTask(ctx, req); err != nil {
			return nil, err
		}
		return map[string]string{"status": "deleted", "task_id": string(req.TaskID)}, nil
	case "link_task_memory":
		var req domain.LinkTaskMemoryRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.LinkTaskMemory(ctx, req)
	case "list_task_relations":
		var req domain.TaskRelationQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.ListTaskRelations(ctx, req)
	case "traverse_task_relations":
		var req domain.TaskRelationTraversalQuery
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.TraverseTaskRelations(ctx, req)
	case "upsert_task_relation":
		var req domain.UpsertTaskRelationRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		return s.service.UpsertTaskRelation(ctx, req)
	case "delete_task_relation":
		var req domain.DeleteTaskRelationRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		if err := s.service.DeleteTaskRelation(ctx, req); err != nil {
			return nil, err
		}
		return map[string]string{"status": "deleted", "relation_id": string(req.RelationID)}, nil
	default:
		return nil, fmt.Errorf("unknown tool %q", name)
	}
}

// toolDefinitions returns the stable MCP tool schemas.
func toolDefinitions() []map[string]any {
	return []map[string]any{
		tool("save_memory_candidate", "Capture raw evidence, create a minimal memory record, and enqueue enrichment.", map[string]any{
			"content":         stringSchema("Raw text or serialized source content to preserve."),
			"title":           stringSchema("Human-readable title."),
			"media_type":      stringSchema("Media type for the source content."),
			"source":          objectSchema(map[string]any{"system": stringSchema("Source system."), "id": stringSchema("Source record id.")}, []string{}),
			"kind":            enumSchema("Memory kind.", []string{"conversation", "document", "tool_output", "artifact", "summary", "entity_page", "timeline", "profile_fact"}),
			"scope":           enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
			"trust_level":     enumSchema("Trust level.", []string{"source_original", "user_asserted", "model_extracted", "model_synthesized", "externally_verified"}),
			"sensitivity":     enumSchema("Sensitivity level.", []string{"public", "internal", "private", "restricted"}),
			"subjects":        arraySchema("Primary subjects.", stringSchema("Subject.")),
			"topics":          arraySchema("Controlled topics.", stringSchema("Topic.")),
			"entity_names":    arraySchema("Canonical entity names or aliases.", stringSchema("Entity name.")),
			"idempotency_key": stringSchema("Caller-provided idempotency key."),
			"actor":           stringSchema("Calling agent or user."),
		}, []string{"content"}),
		tool("search_memory", "Search memory metadata and compiled retrieval context.", retrievalSchema(), []string{}),
		tool("search_sources", "Search and return matching source evidence text.", retrievalSchema(), []string{}),
		tool("load_entity_page", "Load or build a compiled entity page.", map[string]any{
			"scope":     enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
			"entity_id": stringSchema("Canonical entity id."),
			"title":     stringSchema("Entity page title."),
		}, []string{}),
		tool("load_timeline", "Load or build a source-backed timeline.", map[string]any{
			"scope":     enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
			"topic":     stringSchema("Timeline topic."),
			"entity_id": stringSchema("Optional entity id."),
		}, []string{}),
		tool("refresh_compiled_page", "Rebuild an entity page or timeline from source-backed memory records.", map[string]any{
			"actor":     stringSchema("Calling agent or user."),
			"kind":      enumSchema("Compiled page kind.", []string{"entity_page", "timeline"}),
			"scope":     enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
			"title":     stringSchema("Page title."),
			"entity_id": stringSchema("Optional entity id."),
			"topic":     stringSchema("Optional topic."),
		}, []string{}),
		tool("repair_memory_record", "Apply explicit memory metadata corrections.", map[string]any{
			"actor":        stringSchema("Calling agent or user."),
			"memory_id":    stringSchema("Memory record id."),
			"kind":         enumSchema("Memory kind.", []string{"conversation", "document", "tool_output", "artifact", "summary", "entity_page", "timeline", "profile_fact"}),
			"sensitivity":  enumSchema("Sensitivity level.", []string{"public", "internal", "private", "restricted"}),
			"status":       enumSchema("Lifecycle status.", []string{"active", "superseded", "deprecated", "archived"}),
			"title":        stringSchema("Corrected title."),
			"summary":      stringSchema("Corrected summary."),
			"subjects":     arraySchema("Corrected subjects.", stringSchema("Subject.")),
			"topics":       arraySchema("Corrected topics.", stringSchema("Topic.")),
			"entity_names": arraySchema("Corrected entity names.", stringSchema("Entity name.")),
		}, []string{"memory_id"}),
		tool("submit_memory_correction", "Store a user correction as first-class source evidence.", map[string]any{
			"actor":     stringSchema("Calling agent or user."),
			"memory_id": stringSchema("Memory record id being corrected."),
			"scope":     enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
			"text":      stringSchema("Correction text."),
		}, []string{"memory_id", "text"}),
		tool("query_context_graph", "Execute a SQL-like graph query or audited mutation.", map[string]any{
			"actor":                 stringSchema("Calling agent or user."),
			"source_node_id":        stringSchema("Source graph node id required for mutations."),
			"query":                 stringSchema("Graph query, such as FIND task WHERE status != \"done\" AND risk_score >= 6 RETURN id, title LIMIT 10, FIND task GROUP BY status RETURN status, count ORDER BY count DESC LIMIT 10, MATCH task -[depends_on]-> task RETURN from.title, edge.type, to.title LIMIT 10, MATCH task -[depends_on*1..3]-> task WHERE path.depth >= 2 RETURN from.title, path.depth, to.title LIMIT 10, INSERT NODE task SET title = \"New task\" RETURN id, title, or INSERT EDGE node_1 -[depends_on]-> node_2 SET note = \"blocked\" RETURN edge.id, note."),
			"scope":                 enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
			"allowed_sensitivities": arraySchema("Allowed sensitivity levels; restricted must be requested explicitly.", enumSchema("Sensitivity.", []string{"public", "internal", "private", "restricted"})),
		}, []string{"query"}),
		tool("create_task", "Create a graph-backed operational task.", taskCreateSchema(), []string{"title"}),
		tool("get_task", "Load one graph-backed task by id.", map[string]any{"task_id": stringSchema("Task id.")}, []string{"task_id"}),
		tool("list_tasks", "List graph-backed tasks.", taskQuerySchema(), []string{}),
		tool("task_graph_projection", "Read a graph-backed task node and edge projection.", taskGraphProjectionSchema(), []string{}),
		tool("update_task", "Patch a graph-backed operational task.", taskUpdateSchema(), []string{"task_id"}),
		tool("complete_task", "Mark a graph-backed task done.", map[string]any{"task_id": stringSchema("Task id."), "actor": stringSchema("Calling agent or user.")}, []string{"task_id"}),
		tool("cancel_task", "Mark a graph-backed task canceled.", map[string]any{"task_id": stringSchema("Task id."), "actor": stringSchema("Calling agent or user.")}, []string{"task_id"}),
		tool("delete_task", "Lifecycle-delete a graph-backed task.", map[string]any{"task_id": stringSchema("Task id."), "actor": stringSchema("Calling agent or user.")}, []string{"task_id"}),
		tool("link_task_memory", "Attach contextual memory to a graph-backed task.", map[string]any{"task_id": stringSchema("Task id."), "link": memoryLinkSchema()}, []string{"task_id", "link"}),
		tool("list_task_relations", "List directed task-to-task graph relations.", taskRelationQuerySchema(), []string{}),
		tool("traverse_task_relations", "Traverse bounded paths through directed task-to-task graph relations.", taskRelationTraversalSchema(), []string{"root_task_id"}),
		tool("upsert_task_relation", "Create or update a directed task-to-task graph relation.", taskRelationUpsertSchema(), []string{"from_task_id", "to_task_id"}),
		tool("delete_task_relation", "Lifecycle-delete a directed task-to-task graph relation.", map[string]any{"relation_id": stringSchema("Task relation id."), "actor": stringSchema("Calling agent or user.")}, []string{"relation_id"}),
	}
}

// taskCreateSchema returns graph-backed create_task input properties.
func taskCreateSchema() map[string]any {
	return map[string]any{
		"actor":            stringSchema("Calling agent or user."),
		"title":            stringSchema("Task title."),
		"description":      stringSchema("Task notes."),
		"status":           enumSchema("Task status.", taskStatuses()),
		"priority":         enumSchema("Task priority.", taskPriorities()),
		"due_at":           stringSchema("RFC3339 due time."),
		"scheduled_at":     stringSchema("RFC3339 scheduled time."),
		"topics":           arraySchema("Task topics.", stringSchema("Topic.")),
		"estimate_minutes": map[string]any{"type": "integer", "description": "Estimated minutes."},
		"energy_required":  stringSchema("Required energy mode."),
		"effort":           map[string]any{"type": "number", "description": "Effort score from 0 to 1."},
		"value":            map[string]any{"type": "number", "description": "Value score from 0 to 1."},
		"urgency":          map[string]any{"type": "number", "description": "Urgency score from 0 to 1."},
		"risk":             map[string]any{"type": "number", "description": "Risk score from 0 to 1."},
		"context":          stringSchema("Execution context."),
		"view":             stringSchema("Cross-cutting task view."),
		"project":          stringSchema("Project name."),
		"location":         stringSchema("Location requirement."),
		"person":           stringSchema("Responsible person."),
		"source":           stringSchema("Task source."),
		"confidence":       map[string]any{"type": "number", "description": "Metadata confidence from 0 to 1."},
		"memory_links":     arraySchema("Contextual memory links.", memoryLinkSchema()),
		"work_breakdown":   objectSchema(taskWorkBreakdownSchema(), []string{}),
		"idempotency_key":  stringSchema("Caller-provided idempotency key."),
	}
}

// taskWorkBreakdownSchema returns WBS planning metadata properties.
func taskWorkBreakdownSchema() map[string]any {
	return map[string]any{
		"code":                stringSchema("WBS hierarchy code."),
		"deliverable":         stringSchema("Named deliverable or work package."),
		"start_criteria":      arraySchema("Conditions required before work starts.", stringSchema("Start criterion.")),
		"acceptance_criteria": arraySchema("Conditions required to accept the work.", stringSchema("Acceptance criterion.")),
		"requirement_refs":    arraySchema("Requirement references.", stringSchema("Requirement reference.")),
		"rubric_refs":         arraySchema("Rubric references.", stringSchema("Rubric reference.")),
		"resources":           arraySchema("Required WBS resources.", objectSchema(taskResourceRequirementSchema(), []string{})),
		"spend_cents":         map[string]any{"type": "integer", "description": "Estimated cost in cents."},
		"spend_currency":      stringSchema("Estimated cost currency."),
	}
}

// taskResourceRequirementSchema returns WBS resource requirement properties.
func taskResourceRequirementSchema() map[string]any {
	return map[string]any{
		"name":           stringSchema("Resource name."),
		"type":           stringSchema("Resource kind."),
		"quantity":       map[string]any{"type": "number", "description": "Resource quantity."},
		"unit":           stringSchema("Quantity unit."),
		"spend_cents":    map[string]any{"type": "integer", "description": "Estimated cost in cents."},
		"spend_currency": stringSchema("Estimated cost currency."),
		"notes":          stringSchema("Resource notes."),
	}
}

// taskQuerySchema returns graph-backed list_tasks input properties.
func taskQuerySchema() map[string]any {
	return map[string]any{
		"statuses":      arraySchema("Statuses to include.", enumSchema("Task status.", taskStatuses())),
		"priorities":    arraySchema("Priorities to include.", enumSchema("Task priority.", taskPriorities())),
		"topics":        arraySchema("Topics to include.", stringSchema("Topic.")),
		"search":        stringSchema("Title and description search."),
		"overdue_only":  map[string]any{"type": "boolean", "description": "Only overdue tasks."},
		"include_done":  map[string]any{"type": "boolean", "description": "Include done and canceled tasks."},
		"include_links": map[string]any{"type": "boolean", "description": "Include memory links."},
		"limit":         map[string]any{"type": "integer", "description": "Maximum tasks."},
	}
}

// taskGraphProjectionSchema returns task_graph_projection input properties.
func taskGraphProjectionSchema() map[string]any {
	return map[string]any{
		"tasks":          objectSchema(taskQuerySchema(), []string{}),
		"relation_types": arraySchema("Relation types to include.", enumSchema("Task relation type.", taskRelationTypes())),
		"include_facets": map[string]any{"type": "boolean", "description": "Include project, person, and topic facet nodes."},
	}
}

// taskUpdateSchema returns graph-backed update_task input properties.
func taskUpdateSchema() map[string]any {
	schema := taskCreateSchema()
	schema["task_id"] = stringSchema("Task id.")
	schema["clear_due_at"] = map[string]any{"type": "boolean", "description": "Clear due time."}
	schema["clear_scheduled_at"] = map[string]any{"type": "boolean", "description": "Clear scheduled time."}
	delete(schema, "memory_links")
	delete(schema, "idempotency_key")
	return schema
}

// taskRelationQuerySchema returns list_task_relations input properties.
func taskRelationQuerySchema() map[string]any {
	return map[string]any{
		"task_id":   stringSchema("Optional task id."),
		"types":     arraySchema("Relation types to include.", enumSchema("Task relation type.", taskRelationTypes())),
		"direction": enumSchema("Relation direction when task_id is set.", []string{"outgoing", "incoming", "either"}),
		"limit":     map[string]any{"type": "integer", "description": "Maximum relations."},
	}
}

// taskRelationTraversalSchema returns traverse_task_relations input properties.
func taskRelationTraversalSchema() map[string]any {
	schema := taskRelationQuerySchema()
	schema["root_task_id"] = stringSchema("Root task id.")
	schema["max_depth"] = map[string]any{"type": "integer", "description": "Maximum traversal depth."}
	schema["include_tasks"] = map[string]any{"type": "boolean", "description": "Include hydrated task DTOs in each path."}
	schema["include_links"] = map[string]any{"type": "boolean", "description": "Include task memory links when include_tasks is true."}
	delete(schema, "task_id")
	return schema
}

// taskRelationUpsertSchema returns upsert_task_relation input properties.
func taskRelationUpsertSchema() map[string]any {
	return map[string]any{
		"actor":        stringSchema("Calling agent or user."),
		"from_task_id": stringSchema("Source task id."),
		"type":         enumSchema("Task relation type.", taskRelationTypes()),
		"to_task_id":   stringSchema("Target task id."),
		"note":         stringSchema("Relation note."),
		"lag_minutes":  map[string]any{"type": "integer", "description": "Minimum lag minutes between source and target."},
		"confidence":   map[string]any{"type": "number", "description": "Relation confidence from 0 to 1."},
	}
}

// memoryLinkSchema returns task memory link input properties.
func memoryLinkSchema() map[string]any {
	return objectSchema(map[string]any{
		"memory_id":          stringSchema("Memory record id."),
		"memory_evidence_id": stringSchema("Memory evidence id."),
		"relationship":       enumSchema("Memory relationship.", []string{"originated_from", "context", "supporting", "related"}),
		"note":               stringSchema("Link note."),
	}, []string{})
}

// taskStatuses returns graph-backed task status values.
func taskStatuses() []string {
	return []string{"open", "waiting", "blocked", "done", "canceled"}
}

// taskPriorities returns graph-backed task priority values.
func taskPriorities() []string {
	return []string{"low", "normal", "high", "urgent"}
}

// taskRelationTypes returns graph-backed task relation values.
func taskRelationTypes() []string {
	return []string{"depends_on", "blocks", "enables", "part_of", "related_to"}
}

// retrievalSchema returns the shared retrieval input schema.
func retrievalSchema() map[string]any {
	return map[string]any{
		"actor":                 stringSchema("Calling agent or user."),
		"scope":                 enumSchema("Ownership scope.", []string{"session", "user", "household", "tenant", "project", "global"}),
		"text":                  stringSchema("Search text."),
		"kinds":                 arraySchema("Kinds to include.", enumSchema("Memory kind.", []string{"conversation", "document", "tool_output", "artifact", "summary", "entity_page", "timeline", "profile_fact"})),
		"topics":                arraySchema("Topics to include.", stringSchema("Topic.")),
		"entity_ids":            arraySchema("Entity ids to include.", stringSchema("Entity id.")),
		"allowed_sensitivities": arraySchema("Allowed sensitivity levels.", enumSchema("Sensitivity.", []string{"public", "internal", "private", "restricted"})),
		"limit":                 map[string]any{"type": "integer", "description": "Maximum records to return."},
	}
}

// tool creates a MCP tool definition.
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
	schema := map[string]any{
		"type":                 "object",
		"properties":           properties,
		"additionalProperties": false,
	}
	if len(required) > 0 {
		schema["required"] = required
	}
	return schema
}

// stringSchema creates a JSON string schema.
func stringSchema(description string) map[string]any {
	return map[string]any{"type": "string", "description": description}
}

// enumSchema creates a JSON string enum schema.
func enumSchema(description string, values []string) map[string]any {
	return map[string]any{"type": "string", "description": description, "enum": values}
}

// arraySchema creates a JSON array schema.
func arraySchema(description string, item any) map[string]any {
	return map[string]any{"type": "array", "description": description, "items": item}
}

// decodeArgs decodes optional tool arguments into a request struct.
func decodeArgs(args json.RawMessage, dest any) error {
	if len(args) == 0 || string(args) == "null" {
		args = []byte("{}")
	}
	if err := json.Unmarshal(args, dest); err != nil {
		return fmt.Errorf("invalid arguments: %w", err)
	}
	return nil
}

// toolResult wraps structured data in an MCP tool result.
func toolResult(value any, isError bool) map[string]any {
	bytes, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		bytes = []byte(fmt.Sprintf(`{"error":%q}`, err.Error()))
		isError = true
	}
	return map[string]any{
		"content": []map[string]any{
			{"type": "text", "text": string(bytes)},
		},
		"structuredContent": value,
		"isError":           isError,
	}
}

// writeRPCResult writes a JSON-RPC success response.
func writeRPCResult(w http.ResponseWriter, id json.RawMessage, result any) {
	writeJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": json.RawMessage(id), "result": result})
}

// writeRPCError writes a JSON-RPC error response.
func writeRPCError(w http.ResponseWriter, id json.RawMessage, code int, message string, data any) {
	body := map[string]any{"jsonrpc": "2.0", "error": map[string]any{"code": code, "message": message}}
	if len(id) > 0 {
		body["id"] = json.RawMessage(id)
	}
	if data != nil {
		body["error"].(map[string]any)["data"] = data
	}
	writeJSON(w, http.StatusOK, body)
}

// writeJSON writes a JSON response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// rpcRequest represents a JSON-RPC request.
type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// rpcError represents a JSON-RPC error body.
type rpcError struct {
	Code    int
	Message string
	Data    any
}

// toolCallParams represents MCP tools/call parameters.
type toolCallParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

// loadEntityPageArgs contains load_entity_page arguments.
type loadEntityPageArgs struct {
	Scope    domain.Scope    `json:"scope"`
	EntityID domain.EntityID `json:"entity_id"`
	Title    string          `json:"title"`
}

// loadTimelineArgs contains load_timeline arguments.
type loadTimelineArgs struct {
	Scope    domain.Scope    `json:"scope"`
	Topic    string          `json:"topic"`
	EntityID domain.EntityID `json:"entity_id"`
}

// errMissingService documents construction failures for tests.
var errMissingService = errors.New("memory service is required")
