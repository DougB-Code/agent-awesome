// This file exposes Capability Registry records over a small HTTP surface.
package capabilities

import (
	"net/http"
	"strings"

	platformjson "agentawesome.dev/platform/httpjson"
)

// HTTPServer serves capability registry routes.
type HTTPServer struct {
	registry *Registry
}

// NewHTTPServer creates a route adapter for a registry.
func NewHTTPServer(registry *Registry) *HTTPServer {
	return &HTTPServer{registry: registry}
}

// Routes builds the capability HTTP route multiplexer.
func (s *HTTPServer) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/capabilities", s.capabilitiesHandler)
	mux.HandleFunc("/api/capabilities/", s.capabilityHandler)
	return mux
}

// capabilitiesHandler lists capability records with optional filters.
func (s *HTTPServer) capabilitiesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	query := Query{Kind: r.URL.Query().Get("kind")}
	if value, ok := boolQuery(r, "usable_in_chat"); ok {
		query.UsableInChat = &value
	}
	if value, ok := boolQuery(r, "usable_in_workflows"); ok {
		query.UsableInWorkflows = &value
	}
	writeJSON(w, http.StatusOK, map[string]any{"capabilities": s.registry.List(query)})
}

// capabilityHandler returns one capability by stable id.
func (s *HTTPServer) capabilityHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/capabilities/"), "/")
	if id == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "capability id is required"})
		return
	}
	record, ok := s.registry.Get(id)
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "capability not found"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"capability": record})
}

// boolQuery decodes a permissive boolean query parameter.
func boolQuery(r *http.Request, key string) (bool, bool) {
	switch strings.ToLower(strings.TrimSpace(r.URL.Query().Get(key))) {
	case "true", "1", "yes":
		return true, true
	case "false", "0", "no":
		return false, true
	default:
		return false, false
	}
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	platformjson.Write(w, status, body)
}
