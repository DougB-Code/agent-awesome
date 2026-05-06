package gateway

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"time"

	"agentgateway/internal/config"
	"agentgateway/internal/proxy"
	"agentgateway/internal/slack"
	"agentgateway/internal/supervisor"
)

// Server routes gateway-owned endpoints and harness proxy traffic.
type Server struct {
	config       config.Config
	manager      *supervisor.Manager
	apiProxy     *proxy.Proxy
	contextProxy *proxy.Proxy
	memoryProxy  *proxy.Proxy
	slack        *slack.Adapter
	httpServer   *http.Server
}

// NewServer creates a configured gateway server.
func NewServer(cfg config.Config, manager *supervisor.Manager) (*Server, error) {
	apiProxy, err := proxy.New(cfg.HarnessBaseURL, "/api", cfg.RequestTimeout)
	if err != nil {
		return nil, err
	}
	contextProxy, err := proxy.New(cfg.ContextBaseURL, "/api/context", cfg.RequestTimeout)
	if err != nil {
		return nil, err
	}
	memoryProxy, err := proxy.New(cfg.MemoryMCPURL, "/mcp", cfg.RequestTimeout)
	if err != nil {
		return nil, err
	}
	server := &Server{
		config:       cfg,
		manager:      manager,
		apiProxy:     apiProxy,
		contextProxy: contextProxy,
		memoryProxy:  memoryProxy,
		slack:        slack.NewAdapter(slackConfig(cfg)),
	}
	server.httpServer = &http.Server{
		Addr:              cfg.ListenAddress,
		Handler:           server.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	return server, nil
}

// HTTPServer returns the configured net/http server.
func (s *Server) HTTPServer() *http.Server {
	return s.httpServer
}

// routes builds the gateway request multiplexer.
func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.healthHandler)
	mux.HandleFunc("/api/gateway/status", s.authenticated(s.statusHandler))
	mux.HandleFunc("/api/gateway/channels", s.authenticated(s.channelsHandler))
	mux.HandleFunc("/slack/events", s.slack.EventsHandler)
	mux.HandleFunc("/mcp", s.authenticated(s.memoryProxy.ServeHTTP))
	mux.Handle("/api/context/", s.authenticated(s.contextProxy.ServeHTTP))
	mux.Handle("/api/", s.authenticated(s.apiProxy.ServeHTTP))
	return s.cors(mux)
}

// healthHandler reports gateway process liveness.
func (s *Server) healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// statusHandler returns sanitized gateway and dependency status.
func (s *Server) statusHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"gateway":  s.config.StatusView(),
		"services": s.manager.Statuses(),
	})
}

// channelsHandler lists installed channel adapter capabilities.
func (s *Server) channelsHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"channels": []map[string]any{
			{"name": "flutter", "state": "active", "description": "ADK-compatible API traffic through /api/*"},
			{"name": "slack", "state": s.slackState(), "description": "Inbound message adapter for Slack Events API and Socket Mode"},
			{"name": "sms", "state": "planned", "description": "Inbound message adapter for future SMS provider webhooks"},
			{"name": "email", "state": "planned", "description": "Inbound message adapter for future email ingestion"},
		},
	})
}

// RunSlackSocketMode runs the Slack Socket Mode loop when configured.
func (s *Server) RunSlackSocketMode(ctx context.Context) error {
	return s.slack.RunSocketMode(ctx)
}

// SlackSocketModeEnabled reports whether Slack Socket Mode should start.
func (s *Server) SlackSocketModeEnabled() bool {
	return s.slack.SocketModeEnabled()
}

// slackState reports the Slack channel status shown in gateway metadata.
func (s *Server) slackState() string {
	if s.slack.Enabled() {
		return "active"
	}
	return "planned"
}

// slackConfig maps gateway config into the Slack adapter config.
func slackConfig(cfg config.Config) slack.Config {
	return slack.Config{
		Enabled:          cfg.Slack.Enabled,
		SocketMode:       cfg.Slack.SocketMode,
		SigningSecret:    cfg.Slack.SigningSecret,
		BotToken:         cfg.Slack.BotToken,
		AppToken:         cfg.Slack.AppToken,
		AllowedTeamID:    cfg.Slack.AllowedTeamID,
		AllowedUserID:    cfg.Slack.AllowedUserID,
		AllowedChannelID: cfg.Slack.AllowedChannelID,
		HarnessBaseURL:   cfg.HarnessBaseURL,
		AppName:          cfg.AppName,
		AgentUserID:      cfg.UserID,
		RequestTimeout:   cfg.RequestTimeout,
	}
}

// authenticated wraps API handlers with optional bearer token checks.
func (s *Server) authenticated(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if s.config.AuthToken == "" {
			next(w, r)
			return
		}
		if !sameToken(r.Header.Get("Authorization"), "Bearer "+s.config.AuthToken) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		next(w, r)
	}
}

// cors adds optional CORS response headers for browser-hosted clients.
func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.config.AllowedOrigin != "" {
			w.Header().Set("Access-Control-Allow-Origin", s.config.AllowedOrigin)
			w.Header().Set("Access-Control-Allow-Headers", "authorization, content-type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		}
		next.ServeHTTP(w, r)
	})
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(body)
}

// sameToken compares bearer tokens without data-dependent early returns.
func sameToken(actual string, expected string) bool {
	actualHash := sha256.Sum256([]byte(actual))
	expectedHash := sha256.Sum256([]byte(expected))
	return subtle.ConstantTimeCompare(actualHash[:], expectedHash[:]) == 1
}
