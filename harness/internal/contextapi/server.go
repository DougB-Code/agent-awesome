// This file serves normalized context tool operations from configured MCP tools.
package contextapi

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	platformjson "agentawesome.dev/platform/httpjson"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcpclient"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/rs/zerolog/log"
)

const contextAPIPrefix = "/api/context"
const maxContextAPIRequestBytes int64 = 1 << 20

// Server exposes harness-owned context operations for the gateway.
type Server struct {
	tools     *schema.Tools
	authToken string
	http      *http.Server
}

// Config stores the direct context API listener and optional bearer token.
type Config struct {
	Addr      string
	AuthToken string
}

// StartWithConfig begins serving the context API after validating bind safety.
func StartWithConfig(ctx context.Context, cfg Config, tools *schema.Tools) (*Server, error) {
	cfg.Addr = strings.TrimSpace(cfg.Addr)
	cfg.AuthToken = strings.TrimSpace(cfg.AuthToken)
	if cfg.Addr == "" {
		return nil, nil
	}
	if err := validateListenConfig(cfg); err != nil {
		return nil, err
	}
	server := &Server{tools: tools, authToken: cfg.AuthToken}
	server.http = &http.Server{
		Addr:              cfg.Addr,
		Handler:           server.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	listener, err := net.Listen("tcp", cfg.Addr)
	if err != nil {
		return nil, fmt.Errorf("listen context api: %w", err)
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.http.Shutdown(shutdownCtx); err != nil {
			log.Error().Err(err).Msg("shutdown context api")
		}
	}()
	go func() {
		if err := server.http.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error().Err(err).Msg("serve context api")
		}
	}()
	return server, nil
}

// List returns tool names available through configured MCP servers.
func (s *Server) List(ctx context.Context) ([]string, error) {
	if s == nil {
		return nil, fmt.Errorf("context API server is not configured")
	}
	return s.listToolNames(ctx)
}

// Call invokes one configured context tool and returns structured data.
func (s *Server) Call(ctx context.Context, name string, domainID string, arguments map[string]any) (any, error) {
	if s == nil {
		return nil, fmt.Errorf("context API server is not configured")
	}
	return s.callTool(ctx, name, domainID, arguments)
}

// routes builds the context API request multiplexer.
func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc(contextAPIPrefix+"/healthz", s.healthHandler)
	mux.HandleFunc(contextAPIPrefix+"/tools/list", s.authenticated(s.listToolsHandler))
	mux.HandleFunc(contextAPIPrefix+"/tools/call", s.authenticated(s.callToolHandler))
	return mux
}

// healthHandler reports context API liveness.
func (s *Server) healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// listToolsHandler returns tool names available through configured MCP servers.
func (s *Server) listToolsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	names, err := s.listToolNames(r.Context())
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tools": names})
}

// callToolHandler invokes one configured MCP tool and returns structured data.
func (s *Server) callToolHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req toolCallRequest
	if err := platformjson.DecodeBounded(w, r, maxContextAPIRequestBytes, &req); err != nil {
		if errors.Is(err, platformjson.ErrPayloadTooLarge) {
			writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"error": "payload too large"})
			return
		}
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "decode request: " + err.Error()})
		return
	}
	result, err := s.callTool(r.Context(), req.Name, req.DomainID, req.Arguments)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"structuredContent": result})
}

// listToolNames returns the union of configured MCP tool names.
func (s *Server) listToolNames(ctx context.Context) ([]string, error) {
	servers := configuredMCPServers(s.tools)
	names := make([]string, 0)
	seen := map[string]struct{}{}
	if memoryExportAvailable(s.tools) {
		seen[exportMemoryCopyToolName] = struct{}{}
		names = append(names, exportMemoryCopyToolName)
	}
	for _, server := range servers {
		session, err := connectMCP(ctx, server)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", server.Name, err)
		}
		result, err := session.ListTools(ctx, nil)
		_ = session.Close()
		if err != nil {
			return nil, fmt.Errorf("%s list tools: %w", server.Name, err)
		}
		allowed := allowedTools(server)
		for _, tool := range result.Tools {
			if tool == nil || !toolAllowed(tool.Name, allowed) {
				continue
			}
			if _, ok := seen[tool.Name]; ok {
				continue
			}
			seen[tool.Name] = struct{}{}
			names = append(names, tool.Name)
		}
	}
	return names, nil
}

// callTool invokes one configured MCP tool by name and optional memory domain.
func (s *Server) callTool(ctx context.Context, name string, domainID string, arguments map[string]any) (any, error) {
	if strings.TrimSpace(name) == exportMemoryCopyToolName {
		if strings.TrimSpace(domainID) != "" {
			return nil, fmt.Errorf("%s must not include a domain_id override", exportMemoryCopyToolName)
		}
		return s.exportMemoryCopy(ctx, arguments)
	}
	server, err := s.serverForControlTool(ctx, name, domainID)
	if err != nil {
		return nil, err
	}
	session, err := connectMCP(ctx, server)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", server.Name, err)
	}
	defer session.Close()
	result, err := session.CallTool(ctx, &mcp.CallToolParams{
		Name:      name,
		Arguments: arguments,
	})
	if err != nil {
		return nil, fmt.Errorf("%s call %s: %w", server.Name, name, err)
	}
	if result.IsError {
		return nil, fmt.Errorf("%s returned an MCP tool error", name)
	}
	if result.StructuredContent != nil {
		return result.StructuredContent, nil
	}
	return map[string]any{"content": result.Content}, nil
}

// memoryExportAvailable reports whether harness memory policy can evaluate exports.
func memoryExportAvailable(tools *schema.Tools) bool {
	return tools != nil &&
		len(tools.Memory.ReadDomains) > 0 &&
		len(tools.Memory.WriteDomains) > 0 &&
		strings.TrimSpace(tools.Memory.DefaultWriteDomain) != ""
}

// serverForControlTool returns the MCP server selected by control-plane policy.
func (s *Server) serverForControlTool(ctx context.Context, name string, domainID string) (schema.MCPServer, error) {
	if strings.TrimSpace(domainID) != "" {
		return memoryDomainServerForTool(s.tools, name, domainID)
	}
	return serverForTool(ctx, configuredMCPServers(s.tools), name)
}

// authenticated protects context tool surfaces when a direct API token is set.
func (s *Server) authenticated(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.authToken == "" {
			next(w, r)
			return
		}
		if !sameToken(r.Header.Get("Authorization"), "Bearer "+s.authToken) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		next(w, r)
	}
}

// validateListenConfig rejects public context API binds without bearer auth.
func validateListenConfig(cfg Config) error {
	if isLoopbackListenAddress(cfg.Addr) {
		return nil
	}
	if cfg.AuthToken == "" {
		return fmt.Errorf("context API token is required when listening on a non-loopback address")
	}
	return nil
}

// isLoopbackListenAddress reports whether a TCP listen address is loopback-only.
func isLoopbackListenAddress(address string) bool {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return false
	}
	return isLoopbackHost(host)
}

// isLoopbackHost reports whether a host name or IP address is local-only.
func isLoopbackHost(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// sameToken compares bearer tokens without data-dependent early returns.
func sameToken(actual string, expected string) bool {
	actualHash := sha256.Sum256([]byte(actual))
	expectedHash := sha256.Sum256([]byte(expected))
	return subtle.ConstantTimeCompare(actualHash[:], expectedHash[:]) == 1
}

// serverForTool finds the configured MCP server that exposes a tool.
func serverForTool(ctx context.Context, servers []schema.MCPServer, name string) (schema.MCPServer, error) {
	for _, server := range servers {
		if allowed := allowedTools(server); len(allowed) > 0 && !toolAllowed(name, allowed) {
			continue
		}
		session, err := connectMCP(ctx, server)
		if err != nil {
			return schema.MCPServer{}, fmt.Errorf("%s: %w", server.Name, err)
		}
		result, err := session.ListTools(ctx, nil)
		_ = session.Close()
		if err != nil {
			return schema.MCPServer{}, fmt.Errorf("%s list tools: %w", server.Name, err)
		}
		allowed := allowedTools(server)
		for _, tool := range result.Tools {
			if tool != nil && tool.Name == name && toolAllowed(name, allowed) {
				return server, nil
			}
		}
	}
	return schema.MCPServer{}, fmt.Errorf("tool %q is not exposed by harness MCP configuration", name)
}

// memoryDomainServerForTool resolves a memory domain through agent grants.
func memoryDomainServerForTool(tools *schema.Tools, name string, domainID string) (schema.MCPServer, error) {
	if tools == nil {
		return schema.MCPServer{}, fmt.Errorf("memory domains are not configured")
	}
	domainID = strings.TrimSpace(domainID)
	if domainID == "" {
		return schema.MCPServer{}, fmt.Errorf("memory domain id is required")
	}
	domain, ok := memoryDomainByID(tools.Memory.ReadDomains, domainID)
	if !ok {
		return schema.MCPServer{}, fmt.Errorf("memory domain %q is not readable by the active profile", domainID)
	}
	if !memoryToolAllowedForDomain(tools.Memory, name, domainID) {
		return schema.MCPServer{}, fmt.Errorf("tool %q is not allowed for memory domain %q", name, domainID)
	}
	return schema.MCPServer{
		Name:           memoryServerName(domainID),
		Transport:      "streamable-http",
		Endpoint:       strings.TrimSpace(domain.Endpoint),
		HeadersFromEnv: domain.HeadersFromEnv,
		Tools:          schema.MCPToolFilter{Allow: []string{name}},
	}, nil
}

// memoryDomainByID returns one configured readable memory domain.
func memoryDomainByID(domains []schema.MemoryDomain, domainID string) (schema.MemoryDomain, bool) {
	for _, domain := range domains {
		if strings.TrimSpace(domain.ID) == domainID {
			return domain, true
		}
	}
	return schema.MemoryDomain{}, false
}

// memoryToolAllowedForDomain applies read/write grants to a domain tool call.
func memoryToolAllowedForDomain(memory schema.Memory, name string, domainID string) bool {
	if contextReadOnlyMemoryTools()[strings.TrimSpace(name)] {
		return containsString(memoryDomainIDs(memory.ReadDomains), domainID)
	}
	return containsString(memory.WriteDomains, domainID)
}

// memoryDomainIDs returns ids from configured memory domain endpoints.
func memoryDomainIDs(domains []schema.MemoryDomain) []string {
	ids := make([]string, 0, len(domains))
	for _, domain := range domains {
		ids = append(ids, strings.TrimSpace(domain.ID))
	}
	return ids
}

// contextReadOnlyMemoryTools names domain tools that never mutate storage.
func contextReadOnlyMemoryTools() map[string]bool {
	return map[string]bool{
		"search_memory":                  true,
		"search_sources":                 true,
		"load_entity_page":               true,
		"load_timeline":                  true,
		"query_context_graph":            true,
		"get_task":                       true,
		"list_tasks":                     true,
		"task_graph_projection":          true,
		"project_executive_summary":      true,
		"explain_executive_summary_item": true,
		"list_task_relations":            true,
		"traverse_task_relations":        true,
	}
}

// memoryServerName returns a deterministic server name for a domain endpoint.
func memoryServerName(domainID string) string {
	normalized := strings.NewReplacer("-", "_").Replace(strings.TrimSpace(domainID))
	if normalized == "" {
		return "memory"
	}
	return "memory_" + normalized
}

// containsString reports whether values contains target after trimming.
func containsString(values []string, target string) bool {
	target = strings.TrimSpace(target)
	for _, value := range values {
		if strings.TrimSpace(value) == target {
			return true
		}
	}
	return false
}

// connectMCP opens one MCP client session for a configured server.
func connectMCP(ctx context.Context, server schema.MCPServer) (*mcp.ClientSession, error) {
	return mcpclient.Connect(ctx, server, "agent-awesome-context-api", "v1.0.0")
}

// configuredMCPServers returns enabled MCP servers from tool configuration.
func configuredMCPServers(tools *schema.Tools) []schema.MCPServer {
	if tools == nil || !tools.MCP.Enabled {
		return nil
	}
	return tools.MCP.Servers
}

// allowedTools returns one server's explicit allow list.
func allowedTools(server schema.MCPServer) map[string]struct{} {
	if len(server.Tools.Allow) == 0 {
		return nil
	}
	allowed := make(map[string]struct{}, len(server.Tools.Allow))
	for _, name := range server.Tools.Allow {
		allowed[name] = struct{}{}
	}
	return allowed
}

// toolAllowed reports whether a tool passes an optional allow list.
func toolAllowed(name string, allowed map[string]struct{}) bool {
	if len(allowed) == 0 {
		return true
	}
	_, ok := allowed[name]
	return ok
}

// toolCallRequest is the request body for one context tool call.
type toolCallRequest struct {
	Name      string         `json:"name"`
	DomainID  string         `json:"domain_id"`
	Arguments map[string]any `json:"arguments"`
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	platformjson.Write(w, status, body)
}
