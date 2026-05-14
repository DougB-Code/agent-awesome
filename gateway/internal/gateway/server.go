// This file wires gateway routes, proxy handlers, and channel adapters.
package gateway

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"net/url"
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
	config         config.Config
	manager        *supervisor.Manager
	apiProxy       *proxy.Proxy
	contextProxy   *proxy.Proxy
	apiProxies     map[string]*proxy.Proxy
	contextProxies map[string]*proxy.Proxy
	memoryProxies  map[string]*proxy.Proxy
	slack          *slack.Adapter
	httpServer     *http.Server
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
	Memory      []betaComponentView `json:"memory"`
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

const maxGatewayContextRequestBytes int64 = 1 << 20

const memoryDomainHeader = "X-Agent-Awesome-Memory-Domain"
const profileHeader = "X-Agent-Awesome-Profile"
const actorHeader = "X-Agent-Awesome-Actor"

var errGatewayBodyTooLarge = errors.New("gateway request body too large")

// memoryAccessKind describes the grant required for one memory operation.
type memoryAccessKind int

const (
	memoryReadAccess memoryAccessKind = iota
	memoryWriteAccess
)

// executionContext is the gateway-owned profile context for one request.
type executionContext struct {
	Profile config.AgentProfile
	Policy  config.MemoryPolicy
}

// contextToolCallRequest is the gateway-inspected context API request body.
type contextToolCallRequest struct {
	Name      string         `json:"name"`
	DomainID  string         `json:"domain_id"`
	Arguments map[string]any `json:"arguments"`
}

// mcpRPCRequest is the JSON-RPC envelope needed for MCP policy checks.
type mcpRPCRequest struct {
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
}

// mcpCallToolParams is the tools/call subset inspected before proxying.
type mcpCallToolParams struct {
	Name      string         `json:"name"`
	DomainID  string         `json:"domain_id"`
	Arguments map[string]any `json:"arguments"`
}

// policyError carries an HTTP status for gateway-owned policy denials.
type policyError struct {
	status  int
	message string
}

// Error returns the human-readable policy denial.
func (e policyError) Error() string {
	return e.message
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
{{range .Memory}}{{template "component" .}}{{end}}
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
	apiProxies, contextProxies, err := agentProfileProxies(cfg, runtimePolicy)
	if err != nil {
		return nil, err
	}
	memoryProxies, err := memoryDomainProxies(cfg)
	if err != nil {
		return nil, err
	}
	server := &Server{
		config:         cfg,
		manager:        manager,
		apiProxy:       apiProxy,
		contextProxy:   contextProxy,
		apiProxies:     apiProxies,
		contextProxies: contextProxies,
		memoryProxies:  memoryProxies,
		slack:          slack.NewAdapter(slackConfig(cfg)),
	}
	server.httpServer = &http.Server{
		Addr:              cfg.ListenAddress,
		Handler:           server.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	return server, nil
}

// memoryDomainProxies creates one upstream proxy for each configured domain.
func memoryDomainProxies(cfg config.Config) (map[string]*proxy.Proxy, error) {
	proxies := make(map[string]*proxy.Proxy, len(cfg.MemoryDomains))
	for _, domain := range cfg.MemoryDomains {
		id := strings.TrimSpace(domain.ID)
		memoryProxy, err := proxy.New(domain.Endpoint, "/mcp", cfg.RequestTimeout, proxy.WithRouteGroup("mcp:"+id))
		if err != nil {
			return nil, fmt.Errorf("memory domain %s: %w", id, err)
		}
		proxies[id] = memoryProxy
	}
	return proxies, nil
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

// agentProfileProxies creates profile-specific harness API and context proxies.
func agentProfileProxies(cfg config.Config, runtimePolicy *policy.Injector) (map[string]*proxy.Proxy, map[string]*proxy.Proxy, error) {
	apiProxies := make(map[string]*proxy.Proxy, len(cfg.AgentProfiles))
	contextProxies := make(map[string]*proxy.Proxy, len(cfg.AgentProfiles))
	for _, profile := range cfg.AgentProfiles {
		profileID := strings.TrimSpace(profile.ID)
		apiBaseURL := profileHarnessBaseURL(cfg, profile)
		apiProxy, err := proxy.New(
			apiBaseURL,
			"/api",
			cfg.RequestTimeout,
			proxy.WithRouteGroup("api:"+profileID),
			proxy.WithBodyTransformer(runSSEBodyTransformer(runtimePolicy)),
		)
		if err != nil {
			return nil, nil, fmt.Errorf("agent profile %s api proxy: %w", profileID, err)
		}
		contextBaseURL := profileContextBaseURL(cfg, profile)
		contextProxy, err := proxy.New(contextBaseURL, "/api/context", cfg.RequestTimeout, contextProxyOptions(cfg)...)
		if err != nil {
			return nil, nil, fmt.Errorf("agent profile %s context proxy: %w", profileID, err)
		}
		apiProxies[profileID] = apiProxy
		contextProxies[profileID] = contextProxy
	}
	return apiProxies, contextProxies, nil
}

// profileHarnessBaseURL returns the harness API URL assigned to a profile.
func profileHarnessBaseURL(cfg config.Config, profile config.AgentProfile) string {
	if value := strings.TrimSpace(profile.HarnessBaseURL); value != "" {
		return value
	}
	return cfg.HarnessBaseURL
}

// profileContextBaseURL returns the harness context API URL assigned to a profile.
func profileContextBaseURL(cfg config.Config, profile config.AgentProfile) string {
	if value := strings.TrimSpace(profile.ContextBaseURL); value != "" {
		return value
	}
	return cfg.ContextBaseURL
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
	mux.HandleFunc("/mcp", s.authenticated(s.memoryMCPHandler))
	mux.HandleFunc("/mcp/", s.authenticated(s.memoryMCPHandler))
	mux.HandleFunc("/api/context/", s.authenticated(s.requireServiceReady(s.config.HarnessService.Name, s.contextAPIHandler)))
	mux.HandleFunc("/api/", s.authenticated(s.requireServiceReady(s.config.HarnessService.Name, s.apiHandler)))
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
			{"name": "flutter", "state": "active", "description": "Assistant API traffic through /api/*"},
			{"name": "slack", "state": s.slackState(), "description": "Inbound message adapter for Slack Events API and Socket Mode"},
			{"name": "sms", "state": "planned", "description": "Inbound message adapter for future SMS provider webhooks"},
			{"name": "email", "state": "planned", "description": "Inbound message adapter for future email ingestion"},
		},
	})
}

// apiHandler applies profile context before proxying assistant API traffic.
func (s *Server) apiHandler(w http.ResponseWriter, r *http.Request) {
	exec, err := s.executionContextForRequest(r)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	if !s.profileMemoryDomainsReady(w, exec.Profile) {
		return
	}
	s.apiProxyForProfile(exec.Profile.ID).ServeHTTP(w, requestWithExecutionContext(r, exec))
}

// contextAPIHandler enforces gateway memory-domain policy before proxying calls.
func (s *Server) contextAPIHandler(w http.ResponseWriter, r *http.Request) {
	exec, err := s.executionContextForRequest(r)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	contextProxy := s.contextProxyForProfile(exec.Profile.ID)
	if r.Method != http.MethodPost || r.URL.Path != "/api/context/tools/call" {
		contextProxy.ServeHTTP(w, requestWithExecutionContext(r, exec))
		return
	}
	body, err := readLimitedBody(w, r, maxGatewayContextRequestBytes)
	if err != nil {
		writeBodyReadError(w, err)
		return
	}
	var call contextToolCallRequest
	if err := json.Unmarshal(body, &call); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "decode context tool call: " + err.Error()})
		return
	}
	if strings.TrimSpace(call.Name) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "context tool name is required"})
		return
	}
	if hasDomainOverride(call.Arguments) {
		writePolicyError(w, policyError{status: http.StatusForbidden, message: "memory domain overrides must use the gateway domain_id field"})
		return
	}
	domainID, err := s.authorizeMemoryTool(exec.Policy, call.Name, call.DomainID)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	if !s.memoryDomainReady(w, domainID) {
		return
	}
	call.DomainID = domainID
	nextBody, err := json.Marshal(call)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "encode context tool call"})
		return
	}
	contextProxy.ServeHTTP(w, requestWithExecutionContext(requestWithBody(r, r.URL.Path, nextBody), exec))
}

// memoryMCPHandler routes direct MCP traffic to an authorized memory domain.
func (s *Server) memoryMCPHandler(w http.ResponseWriter, r *http.Request) {
	exec, err := s.executionContextForRequest(r)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	requestedDomain, err := requestedMemoryDomain(r)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	body, err := readLimitedBody(w, r, maxGatewayContextRequestBytes)
	if err != nil {
		writeBodyReadError(w, err)
		return
	}
	access, err := memoryAccessFromMCPBody(body)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	domainID, err := s.authorizeMemoryAccess(exec.Policy, access, requestedDomain)
	if err != nil {
		writePolicyError(w, err)
		return
	}
	if !s.memoryDomainReady(w, domainID) {
		return
	}
	memoryProxy, ok := s.memoryProxies[domainID]
	if !ok {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "memory domain " + domainID + " is not routable"})
		return
	}
	memoryProxy.ServeHTTP(w, requestWithBody(r, "/mcp", body))
}

// authorizeMemoryTool selects a domain and checks read/write grants for one tool.
func (s *Server) authorizeMemoryTool(policy config.MemoryPolicy, name string, requestedDomain string) (string, error) {
	access, ok := memoryToolAccessFor(name)
	if !ok {
		return "", policyError{status: http.StatusForbidden, message: "memory tool " + strings.TrimSpace(name) + " is not allowed by gateway policy"}
	}
	return s.authorizeMemoryAccess(policy, access, requestedDomain)
}

// authorizeMemoryAccess selects a domain and checks grants for one access type.
func (s *Server) authorizeMemoryAccess(policy config.MemoryPolicy, access memoryAccessKind, requestedDomain string) (string, error) {
	allowed := allowedDomainsForAccess(policy, access)
	return selectAllowedDomain(strings.TrimSpace(requestedDomain), allowed, access)
}

// allowedDomainsForAccess returns active profile grants for one memory access type.
func allowedDomainsForAccess(policy config.MemoryPolicy, access memoryAccessKind) []string {
	if access == memoryWriteAccess {
		return policy.WriteDomains
	}
	return policy.ReadDomains
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
		Memory:   s.memoryDependencyStatuses(),
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

// memoryDependencyStatuses returns one beta status row for each configured domain.
func (s *Server) memoryDependencyStatuses() []betaComponentView {
	rows := make([]betaComponentView, 0, len(s.config.MemoryDomains))
	for _, domain := range s.config.MemoryDomains {
		name := strings.TrimSpace(domain.Label)
		if name == "" {
			name = strings.TrimSpace(domain.ID)
		}
		service, ok := s.config.MemoryServiceForDomain(domain.ID)
		if !ok {
			rows = append(rows, betaComponentView{
				Name:    name,
				State:   "unmanaged",
				Ready:   true,
				Message: "gateway is not supervising this memory domain",
				URL:     domain.HealthURL,
			})
			continue
		}
		row := s.dependencyStatus(service.Name, name)
		row.Name = name
		if row.URL == "" {
			row.URL = domain.HealthURL
		}
		rows = append(rows, row)
	}
	if len(rows) == 0 {
		return []betaComponentView{{
			Name:    config.DefaultMemoryServiceName,
			State:   "unmanaged",
			Ready:   true,
			Message: "no memory domains are configured",
		}}
	}
	return rows
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
	healthURL := strings.TrimSpace(s.defaultWriteDomainHealthURL())
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

// defaultWriteDomainHealthURL returns the health URL most relevant to snapshot status.
func (s *Server) defaultWriteDomainHealthURL() string {
	if service, ok := s.config.MemoryServiceForDomain(s.config.MemoryPolicy.DefaultWriteDomain); ok {
		return service.HealthURL
	}
	if domain, ok := s.memoryDomainByID(s.config.MemoryPolicy.DefaultWriteDomain); ok {
		return domain.HealthURL
	}
	if len(s.config.MemoryServices) > 0 {
		return s.config.MemoryServices[0].HealthURL
	}
	if len(s.config.MemoryDomains) > 0 {
		return s.config.MemoryDomains[0].HealthURL
	}
	return ""
}

// memoryDomainByID returns one configured gateway memory domain.
func (s *Server) memoryDomainByID(domainID string) (config.MemoryDomain, bool) {
	domainID = strings.TrimSpace(domainID)
	for _, domain := range s.config.MemoryDomains {
		if strings.TrimSpace(domain.ID) == domainID {
			return domain, true
		}
	}
	return config.MemoryDomain{}, false
}

// snapshotStatus returns remote snapshot freshness plus memory restore status.
func (s *Server) snapshotStatus(ctx context.Context, memoryHealth memoryHealthView) betaSnapshotView {
	statusURL := s.snapshotStatusURL()
	status := betaSnapshotView{
		Enabled:       statusURL != "",
		State:         "disabled",
		Message:       "snapshot endpoint is not configured",
		URL:           statusURL,
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
	req, err := http.NewRequestWithContext(reqCtx, http.MethodHead, statusURL, nil)
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

// snapshotStatusURL returns the domain-specific snapshot URL for status checks.
func (s *Server) snapshotStatusURL() string {
	return snapshotStatusURLForDomain(s.config.SnapshotStatusURL, s.config.MemoryPolicy.DefaultWriteDomain)
}

// executionContextForRequest resolves the gateway-owned profile for a request.
func (s *Server) executionContextForRequest(r *http.Request) (executionContext, error) {
	requested := strings.TrimSpace(r.Header.Get(profileHeader))
	if requested == "" {
		if profile, ok := s.config.DefaultProfile(); ok && len(s.config.AgentProfiles) == 1 {
			return executionContext{Profile: profile, Policy: profile.MemoryPolicy()}, nil
		}
		return executionContext{}, policyError{status: http.StatusBadRequest, message: "agent profile is required"}
	}
	profile, ok := s.config.ProfileByID(requested)
	if !ok {
		return executionContext{}, policyError{status: http.StatusForbidden, message: "agent profile " + requested + " is not allowed"}
	}
	return executionContext{Profile: profile, Policy: profile.MemoryPolicy()}, nil
}

// apiProxyForProfile returns the harness API proxy assigned to a profile.
func (s *Server) apiProxyForProfile(profileID string) *proxy.Proxy {
	if proxy, ok := s.apiProxies[strings.TrimSpace(profileID)]; ok {
		return proxy
	}
	return s.apiProxy
}

// contextProxyForProfile returns the harness context proxy assigned to a profile.
func (s *Server) contextProxyForProfile(profileID string) *proxy.Proxy {
	if proxy, ok := s.contextProxies[strings.TrimSpace(profileID)]; ok {
		return proxy
	}
	return s.contextProxy
}

// snapshotStatusURLForDomain appends the memory domain to a snapshot base URL.
func snapshotStatusURLForDomain(base string, domainID string) string {
	base = strings.TrimSpace(base)
	domainID = strings.TrimSpace(domainID)
	if base == "" || domainID == "" {
		return base
	}
	parsed, err := url.Parse(base)
	if err != nil {
		return base
	}
	path := strings.TrimRight(parsed.Path, "/")
	if strings.HasSuffix(path, "/"+domainID) || path == domainID {
		return parsed.String()
	}
	parsed.Path = path + "/" + domainID
	parsed.RawPath = ""
	return parsed.String()
}

// requestedMemoryDomain reads the gateway-owned domain selector from a request.
func requestedMemoryDomain(r *http.Request) (string, error) {
	candidates := make([]string, 0, 3)
	pathDomain, err := memoryDomainFromPath(r.URL.Path)
	if err != nil {
		return "", err
	}
	if pathDomain != "" {
		candidates = append(candidates, pathDomain)
	}
	if queryDomain := strings.TrimSpace(r.URL.Query().Get("domain_id")); queryDomain != "" {
		candidates = append(candidates, queryDomain)
	}
	if headerDomain := strings.TrimSpace(r.Header.Get(memoryDomainHeader)); headerDomain != "" {
		candidates = append(candidates, headerDomain)
	}
	if len(candidates) == 0 {
		return "", nil
	}
	first := candidates[0]
	for _, candidate := range candidates[1:] {
		if candidate != first {
			return "", policyError{status: http.StatusBadRequest, message: "conflicting memory domain selectors"}
		}
	}
	return first, nil
}

// memoryDomainFromPath returns the domain encoded as /mcp/{domain}.
func memoryDomainFromPath(path string) (string, error) {
	if path == "/mcp" {
		return "", nil
	}
	const prefix = "/mcp/"
	if !strings.HasPrefix(path, prefix) {
		return "", nil
	}
	domain := strings.Trim(strings.TrimPrefix(path, prefix), "/")
	if domain == "" || strings.Contains(domain, "/") {
		return "", policyError{status: http.StatusBadRequest, message: "invalid memory domain route"}
	}
	return domain, nil
}

// memoryAccessFromMCPBody returns the most restrictive access in an MCP payload.
func memoryAccessFromMCPBody(body []byte) (memoryAccessKind, error) {
	if len(bytes.TrimSpace(body)) == 0 {
		return memoryReadAccess, nil
	}
	requests, err := decodeMCPRequests(body)
	if err != nil {
		return memoryReadAccess, err
	}
	access := memoryReadAccess
	for _, request := range requests {
		if strings.TrimSpace(request.Method) != "tools/call" {
			continue
		}
		callAccess, err := memoryAccessFromCallToolParams(request.Params)
		if err != nil {
			return memoryReadAccess, err
		}
		if callAccess == memoryWriteAccess {
			access = memoryWriteAccess
		}
	}
	return access, nil
}

// decodeMCPRequests decodes one JSON-RPC request or a batch request.
func decodeMCPRequests(body []byte) ([]mcpRPCRequest, error) {
	if bytes.HasPrefix(bytes.TrimSpace(body), []byte("[")) {
		var batch []mcpRPCRequest
		if err := json.Unmarshal(body, &batch); err != nil {
			return nil, policyError{status: http.StatusBadRequest, message: "decode MCP batch: " + err.Error()}
		}
		return batch, nil
	}
	var request mcpRPCRequest
	if err := json.Unmarshal(body, &request); err != nil {
		return nil, policyError{status: http.StatusBadRequest, message: "decode MCP request: " + err.Error()}
	}
	return []mcpRPCRequest{request}, nil
}

// memoryAccessFromCallToolParams validates a memory tools/call parameter object.
func memoryAccessFromCallToolParams(params json.RawMessage) (memoryAccessKind, error) {
	var call mcpCallToolParams
	if len(bytes.TrimSpace(params)) == 0 {
		return memoryReadAccess, policyError{status: http.StatusBadRequest, message: "MCP tools/call params are required"}
	}
	if err := json.Unmarshal(params, &call); err != nil {
		return memoryReadAccess, policyError{status: http.StatusBadRequest, message: "decode MCP tools/call params: " + err.Error()}
	}
	if strings.TrimSpace(call.DomainID) != "" || hasDomainOverride(call.Arguments) {
		return memoryReadAccess, policyError{status: http.StatusForbidden, message: "model-supplied memory domain overrides are not allowed"}
	}
	access, ok := memoryToolAccessFor(call.Name)
	if !ok {
		return memoryReadAccess, policyError{status: http.StatusForbidden, message: "memory tool " + strings.TrimSpace(call.Name) + " is not allowed by gateway policy"}
	}
	return access, nil
}

// hasDomainOverride reports whether tool arguments try to select a domain.
func hasDomainOverride(arguments map[string]any) bool {
	if len(arguments) == 0 {
		return false
	}
	_, ok := arguments["domain_id"]
	return ok
}

// memoryToolAccessFor classifies known memory tools by required grant type.
func memoryToolAccessFor(name string) (memoryAccessKind, bool) {
	name = strings.TrimSpace(name)
	if memoryReadOnlyTools()[name] {
		return memoryReadAccess, true
	}
	if memoryWriteTools()[name] {
		return memoryWriteAccess, true
	}
	return memoryReadAccess, false
}

// memoryReadOnlyTools returns memory tools that never mutate storage.
func memoryReadOnlyTools() map[string]bool {
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
		"list_commitments":               true,
		"suggest_task_relationships":     true,
		"suggest_task_metadata":          true,
		"suggest_commitments":            true,
		"get_task_work_breakdowns":       true,
	}
}

// memoryWriteTools returns memory tools that require write-domain grants.
func memoryWriteTools() map[string]bool {
	return map[string]bool{
		"remember":                 true,
		"save_memory_candidate":    true,
		"refresh_compiled_page":    true,
		"repair_memory_record":     true,
		"submit_memory_correction": true,
		"mutate_context_graph":     true,
		"create_task":              true,
		"update_task":              true,
		"complete_task":            true,
		"cancel_task":              true,
		"delete_task":              true,
		"link_task_memory":         true,
		"upsert_task_relation":     true,
		"delete_task_relation":     true,
	}
}

// selectAllowedDomain chooses or validates the domain for one access type.
func selectAllowedDomain(requestedDomain string, allowed []string, access memoryAccessKind) (string, error) {
	allowed = uniqueTrimmed(allowed)
	if requestedDomain != "" {
		if containsDomain(allowed, requestedDomain) {
			return requestedDomain, nil
		}
		return "", policyError{status: http.StatusForbidden, message: "memory domain " + requestedDomain + " is not allowed for " + access.String()}
	}
	if len(allowed) == 1 {
		return allowed[0], nil
	}
	if len(allowed) == 0 {
		return "", policyError{status: http.StatusForbidden, message: "no memory domains are allowed for " + access.String()}
	}
	return "", policyError{status: http.StatusBadRequest, message: "memory domain is required when multiple domains are allowed for " + access.String()}
}

// uniqueTrimmed returns a stable list of non-empty trimmed domain ids.
func uniqueTrimmed(values []string) []string {
	seen := map[string]struct{}{}
	unique := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		unique = append(unique, value)
	}
	return unique
}

// containsDomain reports whether a domain id is in an allowed grant list.
func containsDomain(allowed []string, domainID string) bool {
	domainID = strings.TrimSpace(domainID)
	for _, value := range allowed {
		if strings.TrimSpace(value) == domainID {
			return true
		}
	}
	return false
}

// readLimitedBody reads a request body and enforces a gateway-owned cap.
func readLimitedBody(w http.ResponseWriter, r *http.Request, limit int64) ([]byte, error) {
	if r.Body == nil {
		return nil, nil
	}
	reader := http.MaxBytesReader(w, r.Body, limit)
	defer reader.Close()
	body, err := io.ReadAll(reader)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return nil, errGatewayBodyTooLarge
		}
		return nil, fmt.Errorf("read request body: %w", err)
	}
	return body, nil
}

// requestWithBody clones a request with a rewritten path and restored body.
func requestWithBody(r *http.Request, path string, body []byte) *http.Request {
	next := r.Clone(r.Context())
	nextURL := *r.URL
	nextURL.Path = path
	if path == "/mcp" {
		query := nextURL.Query()
		query.Del("domain_id")
		nextURL.RawQuery = query.Encode()
	}
	next.URL = &nextURL
	next.Body = io.NopCloser(bytes.NewReader(body))
	next.ContentLength = int64(len(body))
	next.GetBody = func() (io.ReadCloser, error) {
		return io.NopCloser(bytes.NewReader(body)), nil
	}
	next.Header = r.Header.Clone()
	next.Header.Del(memoryDomainHeader)
	return next
}

// requestWithExecutionContext annotates proxied traffic with verified profile data.
func requestWithExecutionContext(r *http.Request, exec executionContext) *http.Request {
	next := r.Clone(r.Context())
	next.Header = r.Header.Clone()
	next.Header.Set(profileHeader, exec.Profile.ID)
	next.Header.Set(actorHeader, exec.Policy.Actor)
	return next
}

// writeBodyReadError writes a safe body decode error to the caller.
func writeBodyReadError(w http.ResponseWriter, err error) {
	if errors.Is(err, errGatewayBodyTooLarge) {
		writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"error": "payload too large"})
		return
	}
	writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
}

// writePolicyError writes a policy error without proxying to dependencies.
func writePolicyError(w http.ResponseWriter, err error) {
	var policyErr policyError
	if errors.As(err, &policyErr) {
		writeJSON(w, policyErr.status, map[string]string{"error": policyErr.message})
		return
	}
	writeJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
}

// String returns the label used in access-denied messages.
func (a memoryAccessKind) String() string {
	if a == memoryWriteAccess {
		return "write"
	}
	return "read"
}

// memoryDomainReady reports whether a supervised domain dependency is ready.
func (s *Server) memoryDomainReady(w http.ResponseWriter, domainID string) bool {
	service, ok := s.config.MemoryServiceForDomain(domainID)
	if !ok || strings.TrimSpace(service.Name) == "" {
		return true
	}
	if s.serviceReady(service.Name) {
		return true
	}
	writeJSON(w, http.StatusServiceUnavailable, map[string]any{
		"error":     "memory domain dependency not ready",
		"domain_id": domainID,
		"readiness": s.readiness(),
		"services":  s.manager.Statuses(),
	})
	return false
}

// profileMemoryDomainsReady reports whether a profile's memory dependencies are usable.
func (s *Server) profileMemoryDomainsReady(w http.ResponseWriter, profile config.AgentProfile) bool {
	for _, domainID := range profileMemoryDomainIDs(profile) {
		if !s.memoryDomainReady(w, domainID) {
			return false
		}
	}
	return true
}

// profileMemoryDomainIDs returns the profile domain set needed by one agent turn.
func profileMemoryDomainIDs(profile config.AgentProfile) []string {
	seen := make(map[string]struct{})
	var ids []string
	add := func(domainID string) {
		domainID = strings.TrimSpace(domainID)
		if domainID == "" {
			return
		}
		if _, ok := seen[domainID]; ok {
			return
		}
		seen[domainID] = struct{}{}
		ids = append(ids, domainID)
	}
	for _, domainID := range profile.ReadDomains {
		add(domainID)
	}
	for _, domainID := range profile.WriteDomains {
		add(domainID)
	}
	add(profile.DefaultWriteDomain)
	return ids
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
	slackCfg := slack.Config{
		Enabled:           cfg.Slack.Enabled,
		SocketMode:        cfg.Slack.SocketMode,
		SigningSecret:     cfg.Slack.SigningSecret,
		BotToken:          cfg.Slack.BotToken,
		AppToken:          cfg.Slack.AppToken,
		AllowedTeamID:     cfg.Slack.AllowedTeamID,
		AllowedUserID:     cfg.Slack.AllowedUserID,
		AllowedChannelID:  cfg.Slack.AllowedChannelID,
		GatewayBaseURL:    cfg.GatewayBaseURL,
		GatewayAuthToken:  cfg.AuthToken,
		AppName:           cfg.AppName,
		AgentUserID:       cfg.UserID,
		RuntimePolicyText: cfg.RuntimePolicyText,
		ProfileBindings:   slackProfileBindings(cfg.AgentProfiles),
		RequestTimeout:    cfg.RequestTimeout,
	}
	if profile, ok := cfg.DefaultProfile(); ok {
		slackCfg.DefaultProfileID = profile.ID
		slackCfg.AppName = profile.AppName
		slackCfg.AgentUserID = profile.UserID
	}
	return slackCfg
}

// slackProfileBindings maps gateway profile config into Slack adapter config.
func slackProfileBindings(profiles []config.AgentProfile) []slack.ProfileBinding {
	var bindings []slack.ProfileBinding
	for _, profile := range profiles {
		for _, binding := range profile.SlackBindings {
			bindings = append(bindings, slack.ProfileBinding{
				ProfileID:      profile.ID,
				AppName:        profile.AppName,
				AgentUserID:    profile.UserID,
				TeamID:         binding.TeamID,
				ChannelID:      binding.ChannelID,
				AllowedUserIDs: append([]string(nil), binding.AllowedUserIDs...),
			})
		}
	}
	return bindings
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
			w.Header().Set("Access-Control-Allow-Headers", "authorization, content-type, x-agent-awesome-memory-domain, x-agent-awesome-profile")
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
