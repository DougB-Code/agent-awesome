// This file wires gateway routes, proxy handlers, and channel adapters.
package gateway

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"html/template"
	"net/http"
	"strconv"
	"strings"
	"time"

	"agentgateway/internal/adk"
	"agentgateway/internal/config"
	"agentgateway/internal/policy"
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

// readinessView summarizes whether proxied dependency routes should accept traffic.
type readinessView struct {
	Ready   bool   `json:"ready"`
	State   string `json:"state"`
	Message string `json:"message"`
}

// betaStatusView is the sanitized operator-facing beta status snapshot.
type betaStatusView struct {
	GeneratedAt string              `json:"generated_at"`
	Gateway     betaComponentView   `json:"gateway"`
	Harness     betaComponentView   `json:"harness"`
	Memory      betaComponentView   `json:"memory"`
	Snapshot    betaSnapshotView    `json:"snapshot"`
	Slack       betaSlackView       `json:"slack"`
	Model       betaModelStatusView `json:"model"`
}

// betaComponentView stores one process or dependency health row.
type betaComponentView struct {
	Name      string `json:"name"`
	State     string `json:"state"`
	Ready     bool   `json:"ready"`
	Message   string `json:"message"`
	URL       string `json:"url,omitempty"`
	UpdatedAt string `json:"updated_at,omitempty"`
}

// betaSnapshotView stores private snapshot freshness without exposing tokens.
type betaSnapshotView struct {
	Enabled       bool   `json:"enabled"`
	State         string `json:"state"`
	Message       string `json:"message"`
	URL           string `json:"url,omitempty"`
	LastSaveAt    string `json:"last_save_at,omitempty"`
	LastRestoreAt string `json:"last_restore_at,omitempty"`
	ETag          string `json:"etag,omitempty"`
	SizeBytes     int64  `json:"size_bytes,omitempty"`
	CheckedAt     string `json:"checked_at,omitempty"`
}

// betaSlackView stores Slack channel readiness and scope without secrets.
type betaSlackView struct {
	Enabled          bool   `json:"enabled"`
	State            string `json:"state"`
	SocketMode       bool   `json:"socket_mode"`
	AllowedTeamID    string `json:"allowed_team_id,omitempty"`
	AllowedUserID    string `json:"allowed_user_id,omitempty"`
	AllowedChannelID string `json:"allowed_channel_id,omitempty"`
}

// betaModelStatusView stores the active non-secret model identifier.
type betaModelStatusView struct {
	Configured bool   `json:"configured"`
	ProviderID string `json:"provider_id,omitempty"`
	ModelID    string `json:"model_id,omitempty"`
	Identifier string `json:"identifier,omitempty"`
}

// memoryHealthView is the memoryd health payload subset consumed by status.
type memoryHealthView struct {
	Snapshot memorySnapshotHealthView `json:"snapshot"`
}

// memorySnapshotHealthView stores memoryd snapshot operation timestamps.
type memorySnapshotHealthView struct {
	Restore memorySnapshotOperationView `json:"restore"`
	Save    memorySnapshotOperationView `json:"save"`
}

// memorySnapshotOperationView stores one memoryd snapshot operation state.
type memorySnapshotOperationView struct {
	State       string `json:"state"`
	CompletedAt string `json:"completed_at"`
}

var betaStatusPageTemplate = template.Must(template.New("beta-status").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Agent Awesome Beta Status</title>
<style>
body{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:2rem;line-height:1.4;color:#1f2937;background:#f8fafc}
main{max-width:960px;margin:0 auto}
h1{font-size:1.8rem;margin-bottom:.25rem}
table{width:100%;border-collapse:collapse;background:white;border:1px solid #d1d5db;margin:1rem 0}
th,td{text-align:left;padding:.65rem;border-bottom:1px solid #e5e7eb;vertical-align:top}
th{background:#f3f4f6}
.ok{color:#047857;font-weight:700}.bad{color:#b91c1c;font-weight:700}.muted{color:#6b7280}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
</style>
</head>
<body>
<main>
<h1>Agent Awesome Beta Status</h1>
<p class="muted">Generated {{.GeneratedAt}}</p>
<table>
<thead><tr><th>Component</th><th>State</th><th>Message</th><th>Updated</th></tr></thead>
<tbody>
{{template "component" .Gateway}}
{{template "component" .Harness}}
{{template "component" .Memory}}
</tbody>
</table>
<table>
<thead><tr><th>Snapshot</th><th>Value</th></tr></thead>
<tbody>
<tr><td>State</td><td>{{.Snapshot.State}}</td></tr>
<tr><td>Last save</td><td>{{or .Snapshot.LastSaveAt "unknown"}}</td></tr>
<tr><td>Last restore</td><td>{{or .Snapshot.LastRestoreAt "unknown"}}</td></tr>
<tr><td>Size</td><td>{{if .Snapshot.SizeBytes}}{{.Snapshot.SizeBytes}} bytes{{else}}unknown{{end}}</td></tr>
<tr><td>Message</td><td>{{.Snapshot.Message}}</td></tr>
</tbody>
</table>
<table>
<thead><tr><th>Channel</th><th>State</th><th>Scope</th></tr></thead>
<tbody><tr><td>Slack</td><td>{{.Slack.State}}</td><td>team <code>{{.Slack.AllowedTeamID}}</code>, user <code>{{.Slack.AllowedUserID}}</code>, channel <code>{{.Slack.AllowedChannelID}}</code></td></tr></tbody>
</table>
<p>Model: {{if .Model.Configured}}<code>{{.Model.Identifier}}</code>{{else}}<span class="muted">not configured</span>{{end}}</p>
</main>
</body>
</html>
{{define "component"}}<tr><td>{{.Name}}</td><td>{{if .Ready}}<span class="ok">{{.State}}</span>{{else}}<span class="bad">{{.State}}</span>{{end}}</td><td>{{.Message}}</td><td>{{.UpdatedAt}}</td></tr>{{end}}`))

// NewServer creates a configured gateway server.
func NewServer(cfg config.Config, manager *supervisor.Manager) (*Server, error) {
	runtimePolicy := policy.NewInjector(policy.Config{Text: cfg.RuntimePolicyText})
	apiProxy, err := proxy.New(
		cfg.HarnessBaseURL,
		"/api",
		cfg.RequestTimeout,
		proxy.WithRouteGroup("api"),
		proxy.WithBodyTransformer(runSSEBodyTransformer(runtimePolicy)),
	)
	if err != nil {
		return nil, err
	}
	contextProxy, err := proxy.New(cfg.ContextBaseURL, "/api/context", cfg.RequestTimeout, contextProxyOptions(cfg)...)
	if err != nil {
		return nil, err
	}
	memoryProxy, err := proxy.New(cfg.MemoryMCPURL, "/mcp", cfg.RequestTimeout, proxy.WithRouteGroup("mcp"))
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

// contextProxyOptions returns gateway-owned headers for the harness context API.
func contextProxyOptions(cfg config.Config) []proxy.Option {
	options := []proxy.Option{proxy.WithRouteGroup("context")}
	token := strings.TrimSpace(cfg.ContextAPIToken)
	if token == "" {
		return options
	}
	return append(options, proxy.WithUpstreamHeader("Authorization", "Bearer "+token))
}

// runSSEBodyTransformer applies optional operator policy to ADK run_sse requests.
func runSSEBodyTransformer(injector *policy.Injector) proxy.BodyTransformer {
	return func(r *http.Request, body []byte) ([]byte, error) {
		if r.Method != http.MethodPost || !strings.HasSuffix(r.URL.Path, adk.RunSSEPath()) {
			return body, nil
		}
		next, _, err := injector.Inject(body)
		return next, err
	}
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
	mux.HandleFunc("/api/gateway/beta-status", s.authenticated(s.betaStatusHandler))
	mux.HandleFunc("/api/gateway/beta-status.html", s.authenticated(s.betaStatusPageHandler))
	mux.HandleFunc("/api/gateway/channels", s.authenticated(s.channelsHandler))
	mux.HandleFunc("/slack/events", s.slack.EventsHandler)
	mux.HandleFunc("/mcp", s.authenticated(s.requireServiceReady(s.config.MemoryService.Name, s.memoryProxy.ServeHTTP)))
	mux.Handle("/api/context/", s.authenticated(s.requireServiceReady(s.config.HarnessService.Name, s.contextProxy.ServeHTTP)))
	mux.Handle("/api/", s.authenticated(s.requireServiceReady(s.config.HarnessService.Name, s.apiProxy.ServeHTTP)))
	return s.cors(mux)
}

// healthHandler reports gateway process liveness.
func (s *Server) healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// statusHandler returns sanitized gateway and dependency status.
func (s *Server) statusHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"gateway":   s.config.StatusView(),
		"readiness": s.readiness(),
		"services":  s.manager.Statuses(),
	})
}

// betaStatusHandler returns the private beta operator status snapshot.
func (s *Server) betaStatusHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.betaStatus(r.Context()))
}

// betaStatusPageHandler renders the private beta operator status page.
func (s *Server) betaStatusPageHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_ = betaStatusPageTemplate.Execute(w, s.betaStatus(r.Context()))
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

// betaStatus composes all safe operator-facing beta status sections.
func (s *Server) betaStatus(ctx context.Context) betaStatusView {
	return betaStatusView{
		GeneratedAt: time.Now().UTC().Format(time.RFC3339),
		Gateway: betaComponentView{
			Name:    "gateway",
			State:   "ok",
			Ready:   true,
			Message: "gateway process is serving",
		},
		Harness:  s.dependencyStatus(s.config.HarnessService.Name, config.DefaultHarnessServiceName),
		Memory:   s.dependencyStatus(s.config.MemoryService.Name, config.DefaultMemoryServiceName),
		Snapshot: s.snapshotStatus(ctx, s.memoryHealth(ctx)),
		Slack:    s.betaSlackStatus(),
		Model:    s.betaModelStatus(),
	}
}

// dependencyStatus returns one dependency row from the supervisor snapshot.
func (s *Server) dependencyStatus(serviceName string, fallbackName string) betaComponentView {
	name := strings.TrimSpace(serviceName)
	if name == "" {
		name = fallbackName
	}
	if status, ok := s.statusForService(name); ok {
		return betaComponentView{
			Name:      name,
			State:     status.State,
			Ready:     status.State == supervisor.StateConnected,
			Message:   status.Message,
			URL:       status.URL,
			UpdatedAt: status.UpdatedAt.UTC().Format(time.RFC3339),
		}
	}
	return betaComponentView{
		Name:    name,
		State:   "unmanaged",
		Ready:   true,
		Message: "gateway is not supervising this dependency",
	}
}

// betaSlackStatus returns Slack channel status without token fields.
func (s *Server) betaSlackStatus() betaSlackView {
	return betaSlackView{
		Enabled:          s.config.Slack.Enabled,
		State:            s.slackState(),
		SocketMode:       s.config.Slack.SocketMode,
		AllowedTeamID:    s.config.Slack.AllowedTeamID,
		AllowedUserID:    s.config.Slack.AllowedUserID,
		AllowedChannelID: s.config.Slack.AllowedChannelID,
	}
}

// betaModelStatus returns the configured non-secret model identifier.
func (s *Server) betaModelStatus() betaModelStatusView {
	providerID := strings.TrimSpace(s.config.ModelProviderID)
	modelID := strings.TrimSpace(s.config.ModelID)
	view := betaModelStatusView{
		ProviderID: providerID,
		ModelID:    modelID,
	}
	if providerID != "" && modelID != "" {
		view.Configured = true
		view.Identifier = providerID + ":" + modelID
	}
	return view
}

// memoryHealth reads memoryd health details when the dependency exposes them.
func (s *Server) memoryHealth(ctx context.Context) memoryHealthView {
	healthURL := strings.TrimSpace(s.config.MemoryService.HealthURL)
	if healthURL == "" {
		return memoryHealthView{}
	}
	reqCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, healthURL, nil)
	if err != nil {
		return memoryHealthView{}
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return memoryHealthView{}
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return memoryHealthView{}
	}
	var health memoryHealthView
	if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
		return memoryHealthView{}
	}
	return health
}

// snapshotStatus returns remote snapshot freshness plus memory restore status.
func (s *Server) snapshotStatus(ctx context.Context, memoryHealth memoryHealthView) betaSnapshotView {
	status := betaSnapshotView{
		Enabled:       strings.TrimSpace(s.config.SnapshotStatusURL) != "",
		State:         "disabled",
		Message:       "snapshot endpoint is not configured",
		URL:           s.config.SnapshotStatusURL,
		LastRestoreAt: memoryHealth.Snapshot.Restore.CompletedAt,
	}
	if !status.Enabled {
		return status
	}
	if strings.TrimSpace(s.config.SnapshotStatusToken) == "" {
		status.State = "unauthenticated"
		status.Message = "snapshot endpoint is configured without a status token"
		return status
	}
	reqCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(reqCtx, http.MethodHead, s.config.SnapshotStatusURL, nil)
	if err != nil {
		status.State = "unavailable"
		status.Message = "snapshot status request could not be created"
		return status
	}
	req.Header.Set("Authorization", "Bearer "+s.config.SnapshotStatusToken)
	resp, err := http.DefaultClient.Do(req)
	status.CheckedAt = time.Now().UTC().Format(time.RFC3339)
	if err != nil {
		status.State = "unavailable"
		status.Message = "snapshot endpoint did not respond"
		return status
	}
	defer resp.Body.Close()
	status.ETag = resp.Header.Get("ETag")
	status.LastSaveAt = resp.Header.Get("Last-Modified")
	if contentLength := resp.Header.Get("Content-Length"); contentLength != "" {
		if size, err := strconv.ParseInt(contentLength, 10, 64); err == nil {
			status.SizeBytes = size
		}
	}
	switch resp.StatusCode {
	case http.StatusOK, http.StatusNoContent:
		status.State = "available"
		status.Message = "latest snapshot metadata is available"
	case http.StatusNotFound:
		status.State = "missing"
		status.Message = "no snapshot has been saved yet"
	default:
		status.State = "unavailable"
		status.Message = "snapshot endpoint returned HTTP " + strconv.Itoa(resp.StatusCode)
	}
	return status
}

// requireServiceReady blocks proxied routes until their dependency is ready.
func (s *Server) requireServiceReady(serviceName string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.serviceReady(serviceName) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]any{
				"error":     "dependency not ready",
				"readiness": s.readiness(),
				"services":  s.manager.Statuses(),
			})
			return
		}
		next(w, r)
	}
}

// serviceReady reports whether one known dependency is connected.
func (s *Server) serviceReady(serviceName string) bool {
	if strings.TrimSpace(serviceName) == "" {
		return true
	}
	if status, ok := s.statusForService(serviceName); ok {
		return status.State == supervisor.StateConnected
	}
	return true
}

// statusForService returns the latest supervisor status by service name.
func (s *Server) statusForService(serviceName string) (supervisor.Status, bool) {
	name := strings.TrimSpace(serviceName)
	if name == "" {
		return supervisor.Status{}, false
	}
	for _, status := range s.manager.Statuses() {
		if status.Name == name {
			return status, true
		}
	}
	return supervisor.Status{}, false
}

// readiness reports aggregate dependency readiness for status responses.
func (s *Server) readiness() readinessView {
	statuses := s.manager.Statuses()
	if len(statuses) == 0 {
		return readinessView{Ready: true, State: "ready", Message: "no dependencies are pending"}
	}
	starting := false
	degraded := false
	for _, status := range statuses {
		switch status.State {
		case supervisor.StateConnected:
		case supervisor.StateChecking, supervisor.StateStarting:
			starting = true
		default:
			degraded = true
		}
	}
	if degraded {
		return readinessView{Ready: false, State: "degraded", Message: "one or more dependencies are unavailable"}
	}
	if starting {
		return readinessView{Ready: false, State: supervisor.StateStarting, Message: "dependencies are starting"}
	}
	return readinessView{Ready: true, State: "ready", Message: "dependencies are ready"}
}

// slackConfig maps gateway config into the Slack adapter config.
func slackConfig(cfg config.Config) slack.Config {
	return slack.Config{
		Enabled:           cfg.Slack.Enabled,
		SocketMode:        cfg.Slack.SocketMode,
		SigningSecret:     cfg.Slack.SigningSecret,
		BotToken:          cfg.Slack.BotToken,
		AppToken:          cfg.Slack.AppToken,
		AllowedTeamID:     cfg.Slack.AllowedTeamID,
		AllowedUserID:     cfg.Slack.AllowedUserID,
		AllowedChannelID:  cfg.Slack.AllowedChannelID,
		HarnessBaseURL:    cfg.HarnessBaseURL,
		AppName:           cfg.AppName,
		AgentUserID:       cfg.UserID,
		RuntimePolicyText: cfg.RuntimePolicyText,
		RequestTimeout:    cfg.RequestTimeout,
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
