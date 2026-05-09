// This file serves normalized context tool operations from configured MCP tools.
package contextapi

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcptransport"
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

// Start begins serving the context API on addr when addr is non-empty.
func Start(ctx context.Context, addr string, tools *schema.Tools) (*Server, error) {
	return StartWithConfig(ctx, Config{Addr: addr}, tools)
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
	body := http.MaxBytesReader(w, r.Body, maxContextAPIRequestBytes)
	defer body.Close()
	var req toolCallRequest
	if err := json.NewDecoder(body).Decode(&req); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"error": "payload too large"})
			return
		}
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "decode request: " + err.Error()})
		return
	}
	result, err := s.callTool(r.Context(), req.Name, req.Arguments)
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

// callTool invokes one configured MCP tool by name.
func (s *Server) callTool(ctx context.Context, name string, arguments map[string]any) (any, error) {
	server, err := serverForTool(ctx, configuredMCPServers(s.tools), name)
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

// connectMCP opens one MCP client session for a configured server.
func connectMCP(ctx context.Context, server schema.MCPServer) (*mcp.ClientSession, error) {
	transport, err := mcptransport.New(server)
	if err != nil {
		return nil, err
	}
	client := mcp.NewClient(&mcp.Implementation{Name: "agent-awesome-context-api", Version: "v1.0.0"}, nil)
	return client.Connect(ctx, transport, nil)
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
	Arguments map[string]any `json:"arguments"`
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(body)
}
