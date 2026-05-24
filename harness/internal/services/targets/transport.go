// This file exposes Runtime Target HTTP routes.
package targets

import (
	"errors"
	"net/http"
	"strings"

	platformjson "agentawesome.dev/platform/httpjson"
)

const maxTargetsRequestBytes int64 = 1 << 20

// HTTPServer serves Runtime Target API routes.
type HTTPServer struct {
	service *Service
}

// NewHTTPServer creates a target route adapter.
func NewHTTPServer(service *Service) *HTTPServer {
	return &HTTPServer{service: service}
}

// Routes builds the Runtime Target route multiplexer.
func (s *HTTPServer) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/runtime-targets", s.targetsHandler)
	mux.HandleFunc("/api/runtime-targets/", s.targetHandler)
	return mux
}

// targetsHandler lists Runtime Targets.
func (s *HTTPServer) targetsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	targets, err := s.service.ListTargets(r.Context())
	writeResult(w, map[string]any{"targets": targets}, err)
}

// targetHandler routes target detail, update, health, logs, and secrets.
func (s *HTTPServer) targetHandler(w http.ResponseWriter, r *http.Request) {
	id, action := splitTargetPath(r.URL.Path)
	if id == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "runtime target id is required"})
		return
	}
	if id == "pairing-tokens" && action == "" {
		s.pairingTokenHandler(w, r)
		return
	}
	if id == "pair" && action == "" {
		s.pairingRegistrationHandler(w, r)
		return
	}
	switch {
	case r.Method == http.MethodGet && action == "":
		target, err := s.service.GetTarget(r.Context(), id)
		writeResult(w, map[string]any{"target": target}, err)
	case r.Method == http.MethodPut && action == "":
		var req TargetUpdateRequest
		if err := decodeJSON(w, r, &req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		target, err := s.service.UpdateTarget(r.Context(), id, req)
		writeResult(w, map[string]any{"target": target}, err)
	case r.Method == http.MethodGet && action == "health":
		health, err := s.service.Health(r.Context(), id)
		writeResult(w, map[string]any{"health": health}, err)
	case r.Method == http.MethodGet && action == "logs":
		logs, err := s.service.Logs(r.Context(), id)
		writeResult(w, map[string]any{"logs": logs}, err)
	case r.Method == http.MethodGet && action == "secrets":
		secrets, err := s.service.SecretMetadata(r.Context(), id)
		writeResult(w, map[string]any{"secrets": secrets}, err)
	default:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "runtime target route not found"})
	}
}

// pairingTokenHandler issues signed target pairing invites.
func (s *HTTPServer) pairingTokenHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req PairingTokenRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	token, err := s.service.IssuePairingToken(r.Context(), req)
	writeResult(w, map[string]any{"pairing_token": token}, err)
}

// pairingRegistrationHandler registers a target with a signed invite token.
func (s *HTTPServer) pairingRegistrationHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	var req PairedRegistration
	if err := decodeJSON(w, r, &req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	target, err := s.service.RegisterPairedTarget(r.Context(), req)
	writeResult(w, map[string]any{"target": target}, err)
}

// decodeJSON reads one bounded JSON request body.
func decodeJSON(w http.ResponseWriter, r *http.Request, target any) error {
	if err := platformjson.DecodeBounded(w, r, maxTargetsRequestBytes, target); err != nil {
		if errors.Is(err, platformjson.ErrPayloadTooLarge) {
			return errors.New("payload too large")
		}
		return err
	}
	return nil
}

// writeResult writes a success response or target error.
func writeResult(w http.ResponseWriter, body map[string]any, err error) {
	if err != nil {
		status := http.StatusBadRequest
		if isNotFound(err) {
			status = http.StatusNotFound
		}
		writeJSON(w, status, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, body)
}

// writeJSON writes one JSON response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	platformjson.Write(w, status, body)
}

// splitTargetPath returns the target id and optional action suffix.
func splitTargetPath(path string) (string, string) {
	tail := strings.Trim(strings.TrimPrefix(path, "/api/runtime-targets/"), "/")
	parts := strings.Split(tail, "/")
	if len(parts) == 0 {
		return "", ""
	}
	action := ""
	if len(parts) > 1 {
		action = parts[1]
	}
	return parts[0], action
}
