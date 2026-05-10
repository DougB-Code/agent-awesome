// This file creates MCP transports with shared authentication behavior.
package mcptransport

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"agentawesome/internal/config/schema"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// New creates the configured MCP transport for one server.
func New(server schema.MCPServer) (mcp.Transport, error) {
	switch normalizeTransport(server.Transport) {
	case "stdio":
		command := exec.Command(strings.TrimSpace(server.Command), server.Args...)
		if len(server.Env) > 0 {
			command.Env = append(os.Environ(), envPairs(server.Env)...)
		}
		return &mcp.CommandTransport{Command: command}, nil
	case "streamable-http":
		client, err := httpClient(server)
		if err != nil {
			return nil, err
		}
		return &mcp.StreamableClientTransport{
			Endpoint:   endpoint(server),
			HTTPClient: client,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported transport %q", server.Transport)
	}
}

// normalizeTransport maps supported MCP transport aliases to canonical names.
func normalizeTransport(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "http", "streamable-http":
		return "streamable-http"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

// endpoint returns the preferred HTTP endpoint field for an MCP server.
func endpoint(server schema.MCPServer) string {
	if value := strings.TrimSpace(server.Endpoint); value != "" {
		return value
	}
	return strings.TrimSpace(server.URL)
}

// envPairs converts an environment map into KEY=value pairs.
func envPairs(values map[string]string) []string {
	pairs := make([]string, 0, len(values))
	for key, value := range values {
		pairs = append(pairs, key+"="+value)
	}
	return pairs
}

// httpClient returns a header-injecting HTTP client when auth headers exist.
func httpClient(server schema.MCPServer) (*http.Client, error) {
	headers, err := resolvedHeaders(server)
	if err != nil {
		return nil, err
	}
	if len(headers) == 0 {
		return nil, nil
	}
	return &http.Client{
		Transport: headerRoundTripper{
			base:    http.DefaultTransport,
			headers: headers,
		},
	}, nil
}

// resolvedHeaders combines literal and environment-backed headers.
func resolvedHeaders(server schema.MCPServer) (http.Header, error) {
	headers := make(http.Header)
	for key, value := range server.Headers {
		if strings.TrimSpace(key) == "" {
			continue
		}
		headers.Set(key, value)
	}
	for key, envName := range server.HeadersFromEnv {
		if strings.TrimSpace(key) == "" || strings.TrimSpace(envName) == "" {
			continue
		}
		name := strings.TrimSpace(envName)
		value, ok := os.LookupEnv(name)
		if !ok || strings.TrimSpace(value) == "" {
			return nil, fmt.Errorf("mcp header %q requires non-empty environment variable %s", key, name)
		}
		headers.Set(key, value)
	}
	return headers, nil
}

// headerRoundTripper injects configured headers into every MCP HTTP request.
type headerRoundTripper struct {
	base    http.RoundTripper
	headers http.Header
}

// RoundTrip sends one HTTP request with configured MCP auth headers.
func (r headerRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	next := req.Clone(req.Context())
	for key, values := range r.headers {
		next.Header.Del(key)
		for _, value := range values {
			next.Header.Add(key, value)
		}
	}
	return r.base.RoundTrip(next)
}
