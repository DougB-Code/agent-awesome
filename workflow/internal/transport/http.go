// This file exposes user-channel-safe workflow HTTP routes for the gateway.
package transport

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"workflow/internal/runtime"
)

const maxRequestBytes int64 = 1 << 20

// HTTPServer serves workflow REST routes and MCP JSON-RPC.
type HTTPServer struct {
	service *runtime.Service
	mcp     *MCPServer
}

// NewHTTPServer creates the workflow HTTP transport.
func NewHTTPServer(service *runtime.Service) *HTTPServer {
	return &HTTPServer{service: service, mcp: NewMCPServer(service)}
}

// Routes builds the workflowd HTTP route multiplexer.
func (s *HTTPServer) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.healthHandler)
	mux.Handle("/mcp", s.mcp)
	mux.HandleFunc("/api/workflows/action-types", s.actionTypesHandler)
	mux.HandleFunc("/api/workflows/definitions", s.definitionsHandler)
	mux.HandleFunc("/api/workflows/drafts", s.draftsHandler)
	mux.HandleFunc("/api/workflows/drafts/", s.draftHandler)
	mux.HandleFunc("/api/workflows/templates", s.templatesHandler)
	mux.HandleFunc("/api/workflows/templates/", s.templateHandler)
	mux.HandleFunc("/api/workflows/packages", s.packagesHandler)
	mux.HandleFunc("/api/workflows/packages/", s.packageHandler)
	mux.HandleFunc("/api/workflows/runs", s.runsHandler)
	mux.HandleFunc("/api/workflows/runs/", s.runHandler)
	mux.HandleFunc("/api/workflows/inbox", s.inboxHandler)
	return mux
}

// healthHandler reports workflowd liveness.
func (s *HTTPServer) healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// definitionsHandler lists installed workflow definitions.
func (s *HTTPServer) definitionsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	defs, err := s.service.ListDefinitions(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"definitions": defs})
}

// actionTypesHandler lists authoring actions that can be placed in drafts.
func (s *HTTPServer) actionTypesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"action_types": s.service.ActionTypes()})
}

// draftsHandler lists or creates workflow drafts.
func (s *HTTPServer) draftsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		drafts, err := s.service.ListDrafts(r.Context())
		writeResult(w, map[string]any{"drafts": drafts}, err)
	case http.MethodPost:
		var req runtime.DraftRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		draft, err := s.service.CreateDraft(r.Context(), req)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"draft": draft})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

// draftHandler routes draft read, update, delete, validation, compile, and publish.
func (s *HTTPServer) draftHandler(w http.ResponseWriter, r *http.Request) {
	draftID, action := splitTail(r.URL.Path, "/api/workflows/drafts/")
	if draftID == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "draft id is required"})
		return
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		draft, err := s.service.GetDraft(r.Context(), draftID)
		writeResult(w, map[string]any{"draft": draft}, err)
	case r.Method == http.MethodPut && action == "":
		var req runtime.DraftRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		draft, err := s.service.UpdateDraft(r.Context(), draftID, req)
		writeResult(w, map[string]any{"draft": draft}, err)
	case r.Method == http.MethodDelete && action == "":
		writeResult(w, map[string]any{"deleted": draftID}, s.service.DeleteDraft(r.Context(), draftID))
	case r.Method == http.MethodPost && action == "validate":
		result, err := s.service.ValidateDraft(r.Context(), draftID)
		writeResult(w, map[string]any{"validation": result}, err)
	case r.Method == http.MethodPost && action == "compile":
		result, err := s.service.CompileDraft(r.Context(), draftID)
		writeResult(w, map[string]any{"compiled": result}, err)
	case r.Method == http.MethodPost && action == "publish":
		definition, err := s.service.PublishDraft(r.Context(), draftID)
		writeResult(w, map[string]any{"definition": definition}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "workflow draft route not found"})
	}
}

// templatesHandler lists workflow templates.
func (s *HTTPServer) templatesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	templates, err := s.service.ListTemplates(r.Context())
	writeResult(w, map[string]any{"templates": templates}, err)
}

// templateHandler routes template describe and instantiate operations.
func (s *HTTPServer) templateHandler(w http.ResponseWriter, r *http.Request) {
	templateID, action := splitTail(r.URL.Path, "/api/workflows/templates/")
	if templateID == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "template id is required"})
		return
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		template, err := s.service.GetTemplate(r.Context(), templateID)
		writeResult(w, map[string]any{"template": template}, err)
	case r.Method == http.MethodPost && action == "instantiate":
		var req runtime.TemplateInstantiateRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		draft, err := s.service.InstantiateTemplate(r.Context(), templateID, req)
		writeResult(w, map[string]any{"draft": draft}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "workflow template route not found"})
	}
}

// packagesHandler lists or imports workflow packages.
func (s *HTTPServer) packagesHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		packages, err := s.service.ListPackages(r.Context())
		writeResult(w, map[string]any{"packages": packages}, err)
	case http.MethodPost:
		var req runtime.PackageImportRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		pkg, err := s.service.ImportPackage(r.Context(), req)
		writeResult(w, map[string]any{"package": pkg}, err)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

// packageHandler exports one workflow package.
func (s *HTTPServer) packageHandler(w http.ResponseWriter, r *http.Request) {
	packageID, action := splitTail(r.URL.Path, "/api/workflows/packages/")
	if packageID == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "package id is required"})
		return
	}
	if r.Method == http.MethodPost && packageID == "import" && action == "" {
		var req runtime.PackageImportRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		pkg, err := s.service.ImportPackage(r.Context(), req)
		writeResult(w, map[string]any{"package": pkg}, err)
		return
	}
	if r.Method == http.MethodPost && action == "export" {
		pkg, err := s.service.ExportPackage(r.Context(), packageID)
		writeResult(w, map[string]any{"package": pkg}, err)
		return
	}
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "workflow package route not found"})
}

// runsHandler lists or starts workflow runs.
func (s *HTTPServer) runsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		runs, err := s.service.ListRuns(r.Context(), runtime.RunQuery{
			Status:       r.URL.Query().Get("status"),
			DefinitionID: r.URL.Query().Get("definition_id"),
			Limit:        intQuery(r, "limit", 100),
		})
		writeResult(w, map[string]any{"runs": runs}, err)
		return
	}
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req startRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	run, err := s.service.StartWorkflow(r.Context(), req.DefinitionID, req.Input)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{"run": run})
}

// runHandler routes status, history, signal, and cancel for one run.
func (s *HTTPServer) runHandler(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/workflows/runs/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "run id is required"})
		return
	}
	runID := parts[0]
	action := ""
	if len(parts) > 1 {
		action = parts[1]
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		run, err := s.service.Status(r.Context(), runID)
		writeResult(w, map[string]any{"run": run}, err)
	case r.Method == http.MethodGet && action == "history":
		events, err := s.service.History(r.Context(), runID)
		writeResult(w, map[string]any{"events": events}, err)
	case r.Method == http.MethodPost && action == "signal":
		s.signalHandler(w, r, runID)
	case r.Method == http.MethodPost && action == "cancel":
		run, err := s.service.Cancel(r.Context(), runID)
		writeResult(w, map[string]any{"run": run}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "workflow route not found"})
	}
}

// signalHandler decodes and applies one workflow signal.
func (s *HTTPServer) signalHandler(w http.ResponseWriter, r *http.Request, runID string) {
	var req signalRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	run, err := s.service.Signal(r.Context(), runID, req.Signal, req.Payload)
	writeResult(w, map[string]any{"run": run}, err)
}

// inboxHandler lists workflow items waiting for user/channel input.
func (s *HTTPServer) inboxHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	items, err := s.service.Inbox(r.Context())
	writeResult(w, map[string]any{"items": items}, err)
}

// writeResult writes an OK result or a bad request error.
func writeResult(w http.ResponseWriter, body map[string]any, err error) {
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, body)
}

// decodeJSON reads one bounded JSON request body.
func decodeJSON(w http.ResponseWriter, r *http.Request, target any) error {
	body := http.MaxBytesReader(w, r.Body, maxRequestBytes)
	defer body.Close()
	decoder := json.NewDecoder(body)
	if err := decoder.Decode(target); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return errors.New("payload too large")
		}
		return err
	}
	return nil
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(body)
}

// startRequest is the REST payload for creating a workflow run.
type startRequest struct {
	DefinitionID string         `json:"definition_id"`
	Input        map[string]any `json:"input"`
}

// signalRequest is the REST payload for signaling a workflow run.
type signalRequest struct {
	Signal  string         `json:"signal"`
	Payload map[string]any `json:"payload"`
}

// splitTail returns the first path segment and optional operation segment.
func splitTail(path string, prefix string) (string, string) {
	trimmed := strings.Trim(strings.TrimPrefix(path, prefix), "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) == 0 || parts[0] == "" {
		return "", ""
	}
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], parts[1]
}

// intQuery parses a bounded integer query parameter.
func intQuery(r *http.Request, key string, fallback int) int {
	value := strings.TrimSpace(r.URL.Query().Get(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}
