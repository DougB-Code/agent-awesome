// This file serves the memory MCP JSON-RPC transport over HTTP.
package transport

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	platformmcp "agentawesome.dev/platform/mcptransport"

	"github.com/rs/zerolog/log"

	"memory/internal/memory/domain"
	"memory/internal/memory/service"
	"memory/internal/memory/toolargs"
)

const maxJSONRPCRequestBytes int64 = 2 << 20

// MCPServer serves a small MCP-compatible JSON-RPC tool surface.
type MCPServer struct {
	service *service.Service
	mcp     platformmcp.Server
}

// NewMCPServer creates an MCP transport adapter.
func NewMCPServer(memoryService *service.Service) *MCPServer {
	server := &MCPServer{service: memoryService}
	server.mcp = platformmcp.Server{
		Info:            platformmcp.ServerInfo{Name: "agentawesome-memory", Version: "0.1.0"},
		MaxRequestBytes: maxJSONRPCRequestBytes,
		Tools:           toolDefinitions,
		Call:            server.callTool,
		Ready:           server.ready,
		Validate:        validateToolCall,
		FormatResult:    platformmcp.IndentedToolResult,
		Hooks: platformmcp.Hooks{
			OnToolCallStart:    func(name string) { log.Info().Str("tool", name).Msg("memory mcp tool call begin") },
			OnToolCallError:    func(name string, err error) { log.Warn().Str("tool", name).Err(err).Msg("memory mcp tool call failed") },
			OnToolCallComplete: func(name string) { log.Info().Str("tool", name).Msg("memory mcp tool call complete") },
		},
	}
	return server
}

// ServeHTTP handles JSON-RPC MCP requests over HTTP.
func (s *MCPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if domainID := requestDomainID(r); domainID != "" {
		r = r.WithContext(context.WithValue(r.Context(), requestDomainIDKey{}, domainID))
	}
	s.mcp.ServeHTTP(w, r)
}

// ready verifies the memory tool server can call through to a service.
func (s *MCPServer) ready() *platformmcp.RPCError {
	if s.service == nil {
		return &platformmcp.RPCError{Code: -32603, Message: errMissingService.Error()}
	}
	return nil
}

// validateToolCall rejects incomplete memory tool call parameters.
func validateToolCall(call platformmcp.ToolCall) *platformmcp.RPCError {
	if call.Name == "" {
		return &platformmcp.RPCError{Code: -32602, Message: "tool name is required"}
	}
	return nil
}

// callTool decodes tool arguments and calls the memory service.
func (s *MCPServer) callTool(ctx context.Context, name string, args json.RawMessage) (any, error) {
	args = argsWithRequestDomain(ctx, args)
	switch name {
	case "remember":
		return decodeAndCall(ctx, args, func(ctx context.Context, req toolargs.RememberArgs) (any, error) {
			return s.service.Capture(ctx, req.CaptureRequest())
		})
	case "save_memory_candidate":
		return decodeAndCall(ctx, args, s.service.Capture)
	case "search_memory":
		return decodeAndCall(ctx, args, s.service.SearchMemory)
	case "search_sources":
		return decodeAndCall(ctx, args, s.service.SearchSources)
	case "organize_memory":
		return decodeAndCall(ctx, args, s.service.OrganizeMemory)
	case "list_memory_domains":
		return decodeAndCall(ctx, args, s.service.ListMemoryDomains)
	case "create_memory_domain":
		return decodeAndCall(ctx, args, s.service.CreateMemoryDomain)
	case "remove_memory_domain":
		return decodeAndCall(ctx, args, s.service.RemoveMemoryDomain)
	case "load_entity_page":
		return decodeAndCall(ctx, args, func(ctx context.Context, req loadEntityPageArgs) (any, error) {
			domainID, err := domain.NormalizeDomainID(req.DomainID, req.Firewall)
			if err != nil {
				return nil, err
			}
			return s.service.LoadEntityPageForActor(ctx, req.Actor, domainID, req.EntityID, req.Title)
		})
	case "load_timeline":
		return decodeAndCall(ctx, args, func(ctx context.Context, req loadTimelineArgs) (any, error) {
			domainID, err := domain.NormalizeDomainID(req.DomainID, req.Firewall)
			if err != nil {
				return nil, err
			}
			return s.service.LoadTimelineForActor(ctx, req.Actor, domainID, req.Topic, req.EntityID)
		})
	case "refresh_compiled_page":
		return decodeAndCall(ctx, args, s.service.RefreshCompiledPage)
	case "repair_memory_record":
		return decodeAndCall(ctx, args, s.service.RepairMemoryRecord)
	case "submit_memory_correction":
		return decodeAndCall(ctx, args, s.service.SubmitMemoryCorrection)
	case "query_context_graph":
		return decodeValidateAndCall(ctx, args, toolargs.EnsureReadOnlyGraphQuery, s.service.QueryContextGraph)
	case "mutate_context_graph":
		return decodeValidateAndCall(ctx, args, toolargs.EnsureMutatingGraphQuery, s.service.QueryContextGraph)
	case "create_task":
		req, err := toolargs.DecodeCreateTaskRequest(args)
		if err != nil {
			return nil, err
		}
		return s.service.CreateTask(ctx, req)
	case "get_task":
		return decodeAndCall(ctx, args, s.service.GetTask)
	case "list_tasks":
		return decodeAndCall(ctx, args, s.service.ListTasks)
	case "task_graph_projection":
		return decodeAndCall(ctx, args, s.service.TaskGraphProjection)
	case "project_executive_summary":
		return decodeAndCall(ctx, args, s.service.ProjectExecutiveSummary)
	case "explain_executive_summary_item":
		return decodeAndCall(ctx, args, s.service.ExplainExecutiveSummaryItem)
	case "upsert_codebase":
		return decodeAndCall(ctx, args, s.service.UpsertCodebase)
	case "get_codebase":
		return decodeAndCall(ctx, args, s.service.GetCodebase)
	case "list_codebases":
		return decodeAndCall(ctx, args, s.service.ListCodebases)
	case "resolve_codebase":
		return decodeAndCall(ctx, args, s.service.ResolveCodebase)
	case "delete_codebase":
		var req domain.CodebaseIDRequest
		if err := decodeArgs(args, &req); err != nil {
			return nil, err
		}
		if err := s.service.DeleteCodebase(ctx, req); err != nil {
			return nil, err
		}
		return map[string]string{"status": "deleted", "id": req.ID}, nil
	case "update_task":
		return decodeAndCall(ctx, args, s.service.UpdateTask)
	case "complete_task":
		return decodeAndCall(ctx, args, s.service.CompleteTask)
	case "cancel_task":
		return decodeAndCall(ctx, args, s.service.CancelTask)
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
		return decodeAndCall(ctx, args, s.service.LinkTaskMemory)
	case "list_task_relations":
		return decodeAndCall(ctx, args, s.service.ListTaskRelations)
	case "traverse_task_relations":
		return decodeAndCall(ctx, args, s.service.TraverseTaskRelations)
	case "upsert_task_relation":
		return decodeAndCall(ctx, args, s.service.UpsertTaskRelation)
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

// requestDomainIDKey stores HTTP-level routing metadata for downstream tool calls.
type requestDomainIDKey struct{}

// requestDomainID extracts optional routing metadata from gateway and harness calls.
func requestDomainID(r *http.Request) string {
	if r == nil {
		return ""
	}
	if value := strings.TrimSpace(r.URL.Query().Get("domain_id")); value != "" {
		return value
	}
	return strings.TrimSpace(r.Header.Get("X-Memory-Domain"))
}

// argsWithRequestDomain injects request routing metadata when tool arguments omit it.
func argsWithRequestDomain(ctx context.Context, args json.RawMessage) json.RawMessage {
	domainID, _ := ctx.Value(requestDomainIDKey{}).(string)
	domainID = strings.TrimSpace(domainID)
	if domainID == "" {
		return args
	}
	if len(args) == 0 || string(args) == "null" {
		args = []byte("{}")
	}
	var payload map[string]any
	if err := json.Unmarshal(args, &payload); err != nil {
		return args
	}
	if _, ok := payload["domain_id"]; !ok {
		payload["domain_id"] = domainID
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return args
	}
	return encoded
}

// decodeAndCall decodes arguments before calling a typed service method.
func decodeAndCall[T any, R any](ctx context.Context, args json.RawMessage, call func(context.Context, T) (R, error)) (any, error) {
	var req T
	if err := decodeArgs(args, &req); err != nil {
		return nil, err
	}
	return call(ctx, req)
}

// decodeValidateAndCall decodes, validates, and then calls a typed service method.
func decodeValidateAndCall[T any, R any](ctx context.Context, args json.RawMessage, validate func(T) error, call func(context.Context, T) (R, error)) (any, error) {
	var req T
	if err := decodeArgs(args, &req); err != nil {
		return nil, err
	}
	if err := validate(req); err != nil {
		return nil, err
	}
	return call(ctx, req)
}

// toolDefinitions returns the stable MCP tool schemas.
func toolDefinitions() []map[string]any {
	return []map[string]any{
		tool("remember", "Store one small memory nugget. Use this for user facts, preferences, notes, and things to recall later. Use create_task only for operational todos.", rememberSchema(), []string{"text"}),
		tool("save_memory_candidate", "Advanced memory capture for raw source content. Prefer remember for a single small fact, preference, or note.", map[string]any{
			"content":         stringSchema("Raw text or serialized source content to preserve."),
			"title":           stringSchema("Human-readable title."),
			"media_type":      stringSchema("Media type for the source content."),
			"source":          objectSchema(map[string]any{"system": stringSchema("Source system."), "id": stringSchema("Source record id.")}, []string{}),
			"kind":            enumSchema("Memory kind.", domain.KindStrings()),
			"domain_id":       stringSchema("Memory domain id."),
			"trust_level":     enumSchema("Trust level.", domain.TrustLevelStrings()),
			"sensitivity":     enumSchema("Sensitivity level.", domain.SensitivityStrings()),
			"subjects":        arraySchema("Primary subjects.", stringSchema("Subject.")),
			"topics":          arraySchema("Controlled topics.", stringSchema("Topic.")),
			"entity_names":    arraySchema("Canonical entity names or aliases.", stringSchema("Entity name.")),
			"idempotency_key": stringSchema("Caller-provided idempotency key."),
			"actor":           stringSchema("Calling agent or user."),
		}, []string{"content"}),
		tool("search_memory", "Search memory metadata and compiled retrieval context.", retrievalSchema(), []string{}),
		tool("search_sources", "Search and return matching source content text.", retrievalSchema(), []string{}),
		tool("organize_memory", "Run bounded memory maintenance, fill safe summaries, and create follow-up tasks for records that need human detail.", organizeMemorySchema(), []string{}),
		tool("list_memory_domains", "List SQLite databases currently known to the memory pool.", memoryDomainListSchema(), []string{}),
		tool("create_memory_domain", "Create or open one SQLite database in the live memory pool.", memoryDomainPoolSchema(false), []string{}),
		tool("remove_memory_domain", "Detach one SQLite database from the live memory pool, optionally deleting files.", memoryDomainPoolSchema(true), []string{}),
		tool("load_entity_page", "Load or build a compiled entity page.", map[string]any{
			"actor":     stringSchema("Calling agent or user."),
			"domain_id": stringSchema("Memory domain id."),
			"entity_id": stringSchema("Canonical entity id."),
			"title":     stringSchema("Entity page title."),
		}, []string{}),
		tool("load_timeline", "Load or build a source-backed timeline.", map[string]any{
			"actor":     stringSchema("Calling agent or user."),
			"domain_id": stringSchema("Memory domain id."),
			"topic":     stringSchema("Timeline topic."),
			"entity_id": stringSchema("Optional entity id."),
		}, []string{}),
		tool("refresh_compiled_page", "Rebuild an entity page or timeline from source-backed memory records.", map[string]any{
			"actor":     stringSchema("Calling agent or user."),
			"kind":      enumSchema("Compiled page kind.", domain.CompiledPageKindStrings()),
			"domain_id": stringSchema("Memory domain id."),
			"title":     stringSchema("Page title."),
			"entity_id": stringSchema("Optional entity id."),
			"topic":     stringSchema("Optional topic."),
		}, []string{}),
		tool("repair_memory_record", "Apply explicit memory metadata corrections.", map[string]any{
			"actor":        stringSchema("Calling agent or user."),
			"memory_id":    stringSchema("Memory record id."),
			"domain_id":    stringSchema("Memory domain id."),
			"kind":         enumSchema("Memory kind.", domain.KindStrings()),
			"sensitivity":  enumSchema("Sensitivity level.", domain.SensitivityStrings()),
			"status":       enumSchema("Lifecycle status.", domain.StatusStrings()),
			"title":        stringSchema("Corrected title."),
			"summary":      stringSchema("Corrected summary."),
			"subjects":     arraySchema("Corrected subjects.", stringSchema("Subject.")),
			"topics":       arraySchema("Corrected topics.", stringSchema("Topic.")),
			"entity_names": arraySchema("Corrected entity names.", stringSchema("Entity name.")),
		}, []string{"memory_id"}),
		tool("submit_memory_correction", "Store a user correction as first-class source content.", map[string]any{
			"actor":     stringSchema("Calling agent or user."),
			"memory_id": stringSchema("Memory record id being corrected."),
			"domain_id": stringSchema("Memory domain id."),
			"text":      stringSchema("Correction text."),
		}, []string{"memory_id", "text"}),
		tool("query_context_graph", "Execute a read-only SQL-like graph query.", graphQuerySchema("Read-only graph query, such as FIND task WHERE status != \"done\" RETURN id, title, due_at LIMIT 10, FIND task GROUP BY status RETURN status, count ORDER BY count DESC LIMIT 10, MATCH task -[depends_on]-> task RETURN from.title, edge.type, to.title LIMIT 10, or MATCH task -[depends_on*1..3]-> task WHERE path.depth >= 2 RETURN from.title, path.depth, to.title LIMIT 10."), []string{"query"}),
		tool("mutate_context_graph", "Execute an audited SQL-like graph mutation.", graphQuerySchema("Graph mutation, such as INSERT NODE task SET title = \"New task\" RETURN id, title, SET NODE node_1 SET title = \"Updated\" RETURN id, title, DELETE EDGE edge_1 RETURN edge.id, or INSERT EDGE node_1 -[depends_on]-> node_2 SET note = \"blocked\" RETURN edge.id, note."), []string{"query"}),
		tool("create_task", "Create a graph-backed operational task or todo. Do not use for user facts, preferences, or notes to remember.", taskCreateSchema(), []string{"title"}),
		tool("get_task", "Load one graph-backed task by id.", map[string]any{"task_id": stringSchema("Task id."), "domain_id": stringSchema("Memory domain id.")}, []string{"task_id"}),
		tool("list_tasks", "List graph-backed tasks.", taskQuerySchema(), []string{}),
		tool("task_graph_projection", "Read a graph-backed task node and edge projection.", taskGraphProjectionSchema(), []string{}),
		tool("project_executive_summary", "Read the canonical Today executive summary projection.", executiveSummarySchema(), []string{}),
		tool("explain_executive_summary_item", "Explain why one Today projection item was surfaced.", explainExecutiveSummaryItemSchema(), []string{"item_id"}),
		tool("upsert_codebase", "Create or update a durable codebase catalog entry for runbook operations.", map[string]any{
			"actor":    stringSchema("Calling agent or user."),
			"codebase": codebaseSchema(),
		}, []string{"codebase"}),
		tool("get_codebase", "Load one durable codebase catalog entry by id.", map[string]any{"id": stringSchema("Codebase id."), "actor": stringSchema("Calling agent or user.")}, []string{"id"}),
		tool("list_codebases", "List durable codebase catalog entries.", map[string]any{
			"text":  stringSchema("Optional search text."),
			"limit": map[string]any{"type": "integer", "description": "Maximum codebases to return."},
			"actor": stringSchema("Calling agent or user."),
		}, []string{}),
		tool("resolve_codebase", "Resolve a human codebase name or alias to one catalog entry or an ambiguity result.", map[string]any{
			"query": stringSchema("Codebase name, id, alias, or search phrase."),
			"actor": stringSchema("Calling agent or user."),
		}, []string{"query"}),
		tool("delete_codebase", "Lifecycle-delete one durable codebase catalog entry.", map[string]any{"id": stringSchema("Codebase id."), "actor": stringSchema("Calling agent or user.")}, []string{"id"}),
		tool("update_task", "Patch a graph-backed operational task.", taskUpdateSchema(), []string{"task_id"}),
		tool("complete_task", "Mark a graph-backed task done.", map[string]any{"task_id": stringSchema("Task id."), "domain_id": stringSchema("Memory domain id."), "actor": stringSchema("Calling agent or user.")}, []string{"task_id"}),
		tool("cancel_task", "Mark a graph-backed task canceled.", map[string]any{"task_id": stringSchema("Task id."), "domain_id": stringSchema("Memory domain id."), "actor": stringSchema("Calling agent or user.")}, []string{"task_id"}),
		tool("delete_task", "Lifecycle-delete a graph-backed task.", map[string]any{"task_id": stringSchema("Task id."), "domain_id": stringSchema("Memory domain id."), "actor": stringSchema("Calling agent or user.")}, []string{"task_id"}),
		tool("link_task_memory", "Attach contextual memory to a graph-backed task.", map[string]any{"task_id": stringSchema("Task id."), "domain_id": stringSchema("Memory domain id."), "link": memoryLinkSchema()}, []string{"task_id", "link"}),
		tool("list_task_relations", "List directed task-to-task graph relations.", taskRelationQuerySchema(), []string{}),
		tool("traverse_task_relations", "Traverse bounded paths through directed task-to-task graph relations.", taskRelationTraversalSchema(), []string{"root_task_id"}),
		tool("upsert_task_relation", "Create or update a directed task-to-task graph relation.", taskRelationUpsertSchema(), []string{"from_task_id", "to_task_id"}),
		tool("delete_task_relation", "Lifecycle-delete a directed task-to-task graph relation.", map[string]any{"relation_id": stringSchema("Task relation id."), "domain_id": stringSchema("Memory domain id."), "actor": stringSchema("Calling agent or user.")}, []string{"relation_id"}),
	}
}

// graphQuerySchema returns the shared graph query and mutation input schema.
func graphQuerySchema(queryDescription string) map[string]any {
	return map[string]any{
		"actor":                 stringSchema("Calling agent or user."),
		"source_node_id":        stringSchema("Source graph node id required for mutations."),
		"query":                 stringSchema(queryDescription),
		"domain_id":             stringSchema("Memory domain id."),
		"include_global":        boolSchema("When true, also include globally shared records. Default false."),
		"allowed_sensitivities": arraySchema("Allowed sensitivity levels; restricted must be requested explicitly.", enumSchema("Sensitivity.", domain.SensitivityStrings())),
	}
}

// rememberSchema returns the small model-facing memory nugget schema.
func rememberSchema() map[string]any {
	return map[string]any{
		"text":            stringSchema("The single memory nugget to preserve."),
		"title":           stringSchema("Optional short display title."),
		"topics":          arraySchema("Optional connective topic tags.", stringSchema("Topic.")),
		"entities":        arraySchema("Optional people, projects, places, or things this memory mentions.", stringSchema("Entity name.")),
		"domain_id":       stringSchema("Optional memory domain id; default is user."),
		"sensitivity":     enumSchema("Optional sensitivity; default is private.", domain.SensitivityStrings()),
		"idempotency_key": stringSchema("Optional stable key to avoid duplicate nuggets."),
		"actor":           stringSchema("Optional calling agent or user."),
	}
}

// taskCreateSchema returns a small model-facing create_task payload.
func taskCreateSchema() map[string]any {
	return map[string]any{
		"actor":           stringSchema("Optional calling agent or user."),
		"domain_id":       stringSchema("Optional memory domain id; default is user."),
		"title":           stringSchema("Short task title, such as buy milk."),
		"description":     stringSchema("Optional note only when the user provides one."),
		"priority":        enumSchema("Optional task priority; default is normal.", domain.TaskPriorityStrings()),
		"due_at":          stringSchema("Optional RFC3339 due time when the user gave a deadline."),
		"scheduled_at":    stringSchema("Optional RFC3339 scheduled time when the user gave a start or reminder time."),
		"topics":          arraySchema("Optional task topics.", stringSchema("Topic.")),
		"idempotency_key": stringSchema("Optional caller-provided idempotency key."),
	}
}

// taskAdvancedSchema returns richer graph task metadata for clients and updates.
func taskAdvancedSchema() map[string]any {
	return map[string]any{
		"actor":            stringSchema("Calling agent or user."),
		"domain_id":        stringSchema("Memory domain id."),
		"title":            stringSchema("Task title."),
		"description":      stringSchema("Task notes."),
		"status":           enumSchema("Task status.", domain.TaskStatusStrings()),
		"priority":         enumSchema("Task priority.", domain.TaskPriorityStrings()),
		"due_at":           stringSchema("RFC3339 due time."),
		"scheduled_at":     stringSchema("RFC3339 scheduled time."),
		"follow_up_at":     stringSchema("RFC3339 stale-review time."),
		"topics":           arraySchema("Task topics.", stringSchema("Topic.")),
		"estimate_minutes": map[string]any{"type": "integer", "description": "Estimated minutes."},
		"urgency":          map[string]any{"type": "number", "description": "Urgency score from 0 to 1."},
		"project":          stringSchema("Project name."),
		"location":         stringSchema("Location requirement."),
		"person":           stringSchema("Responsible person."),
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
		"domain_id":     stringSchema("Memory domain id."),
		"statuses":      arraySchema("Statuses to include.", enumSchema("Task status.", domain.TaskStatusStrings())),
		"priorities":    arraySchema("Priorities to include.", enumSchema("Task priority.", domain.TaskPriorityStrings())),
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
		"relation_types": arraySchema("Relation types to include.", enumSchema("Task relation type.", domain.TaskRelationTypeStrings())),
		"include_facets": map[string]any{"type": "boolean", "description": "Include project, person, and topic facet nodes."},
	}
}

// executiveSummarySchema returns project_executive_summary input properties.
func executiveSummarySchema() map[string]any {
	return map[string]any{
		"domain_id":        stringSchema("Memory domain id."),
		"horizon":          enumSchema("Projection horizon.", domain.ExecutiveSummaryHorizonStrings()),
		"now":              stringSchema("Optional RFC3339 clock override."),
		"max_items":        map[string]any{"type": "integer", "description": "Maximum visible items across primary sections."},
		"include_evidence": map[string]any{"type": "boolean", "description": "Include concise source handles."},
		"include_actions":  map[string]any{"type": "boolean", "description": "Include safe action hints."},
		"channel":          enumSchema("Presentation channel.", domain.ExecutiveSummaryChannelStrings()),
	}
}

// explainExecutiveSummaryItemSchema returns explanation input properties.
func explainExecutiveSummaryItemSchema() map[string]any {
	return map[string]any{
		"item_id":         stringSchema("Executive summary item id."),
		"include_sources": map[string]any{"type": "boolean", "description": "Include source handles when available."},
	}
}

// taskUpdateSchema returns graph-backed update_task input properties.
func taskUpdateSchema() map[string]any {
	schema := taskAdvancedSchema()
	schema["task_id"] = stringSchema("Task id.")
	schema["clear_due_at"] = map[string]any{"type": "boolean", "description": "Clear due time."}
	schema["clear_scheduled_at"] = map[string]any{"type": "boolean", "description": "Clear scheduled time."}
	schema["clear_follow_up_at"] = map[string]any{"type": "boolean", "description": "Clear stale-review time."}
	delete(schema, "memory_links")
	delete(schema, "idempotency_key")
	return schema
}

// taskRelationQuerySchema returns list_task_relations input properties.
func taskRelationQuerySchema() map[string]any {
	return map[string]any{
		"domain_id": stringSchema("Memory domain id."),
		"task_id":   stringSchema("Optional task id."),
		"types":     arraySchema("Relation types to include.", enumSchema("Task relation type.", domain.TaskRelationTypeStrings())),
		"direction": enumSchema("Relation direction when task_id is set.", domain.TaskRelationDirectionStrings()),
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
		"domain_id":    stringSchema("Memory domain id."),
		"from_task_id": stringSchema("Source task id."),
		"type":         enumSchema("Task relation type.", domain.TaskRelationTypeStrings()),
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
		"memory_evidence_id": stringSchema("Memory source record id."),
		"relationship":       enumSchema("Memory relationship.", domain.TaskMemoryRelationshipStrings()),
		"note":               stringSchema("Link note."),
	}, []string{})
}

// retrievalSchema returns the shared retrieval input schema.
func retrievalSchema() map[string]any {
	return map[string]any{
		"actor":                 stringSchema("Calling agent or user."),
		"domain_id":             stringSchema("Memory domain id."),
		"include_global":        boolSchema("When true, also include globally shared records. Default false."),
		"text":                  stringSchema("Search text."),
		"kinds":                 arraySchema("Kinds to include.", enumSchema("Memory kind.", domain.KindStrings())),
		"topics":                arraySchema("Topics to include.", stringSchema("Topic.")),
		"entity_ids":            arraySchema("Entity ids to include.", stringSchema("Entity id.")),
		"allowed_sensitivities": arraySchema("Allowed sensitivity levels.", enumSchema("Sensitivity.", domain.SensitivityStrings())),
		"limit":                 map[string]any{"type": "integer", "description": "Maximum records to return."},
	}
}

// organizeMemorySchema returns the maintenance batch input schema.
func organizeMemorySchema() map[string]any {
	return map[string]any{
		"actor":                 stringSchema("Calling agent or user."),
		"domain_id":             stringSchema("Memory domain id."),
		"include_global":        boolSchema("When true, also include globally shared records. Default false."),
		"allowed_sensitivities": arraySchema("Allowed sensitivity levels.", enumSchema("Sensitivity.", domain.SensitivityStrings())),
		"limit":                 map[string]any{"type": "integer", "description": "Maximum records to review."},
		"dry_run":               boolSchema("Preview summary repairs and follow-up questions without writing tasks or memory changes."),
	}
}

// memoryDomainPoolSchema returns live pool management input properties.
func memoryDomainPoolSchema(includeDeleteFiles bool) map[string]any {
	schema := map[string]any{
		"actor":     stringSchema("Calling agent or user."),
		"domain_id": stringSchema("Memory domain id."),
	}
	if includeDeleteFiles {
		schema["delete_files"] = boolSchema("When true, delete the domain database directory from disk. Default false.")
	}
	return schema
}

// memoryDomainListSchema returns live pool list input properties.
func memoryDomainListSchema() map[string]any {
	return map[string]any{
		"actor":     stringSchema("Calling agent or user."),
		"domain_id": stringSchema("Optional memory domain id used to scope the listing."),
	}
}

// codebaseSchema returns the typed codebase catalog input schema.
func codebaseSchema() map[string]any {
	return objectSchema(map[string]any{
		"id":                  stringSchema("Stable codebase id. Derived from name when omitted."),
		"name":                stringSchema("Human-readable codebase name."),
		"aliases":             arraySchema("Normalized lookup aliases.", stringSchema("Codebase alias.")),
		"repository_path":     stringSchema("Local repository path for local codebases."),
		"default_remote":      stringSchema("Default Git remote name."),
		"default_branch":      stringSchema("Default Git branch or ref."),
		"provider":            stringSchema("Repository provider such as github."),
		"provider_repository": stringSchema("Provider repository id, normalized as owner/name for GitHub."),
		"runtime_target_id":   stringSchema("Default runtime target id."),
		"agent_profile_id":    stringSchema("Default agent profile id."),
	}, []string{"name"})
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

// boolSchema creates a JSON boolean schema.
func boolSchema(description string) map[string]any {
	return map[string]any{"type": "boolean", "description": description}
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

// loadEntityPageArgs contains load_entity_page arguments.
type loadEntityPageArgs struct {
	Actor    string          `json:"actor"`
	DomainID domain.DomainID `json:"domain_id,omitempty"`
	Firewall domain.Firewall `json:"firewall,omitempty"`
	EntityID domain.EntityID `json:"entity_id"`
	Title    string          `json:"title"`
}

// loadTimelineArgs contains load_timeline arguments.
type loadTimelineArgs struct {
	Actor    string          `json:"actor"`
	DomainID domain.DomainID `json:"domain_id,omitempty"`
	Firewall domain.Firewall `json:"firewall,omitempty"`
	Topic    string          `json:"topic"`
	EntityID domain.EntityID `json:"entity_id"`
}

// errMissingService documents construction failures for tests.
var errMissingService = errors.New("memory service is required")
