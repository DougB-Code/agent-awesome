// This file starts command MCP services inside a host process.
package embedded

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"agentawesome/internal/services/command/command"
	"agentawesome/internal/services/command/transport"
)

const (
	defaultReadHeaderTimeout = 5 * time.Second
	defaultShutdownTimeout   = 5 * time.Second
)

// Config stores the host-owned command listener and runtime settings.
type Config struct {
	ListenAddress     string
	DataDir           string
	AllowedWorkdirs   []string
	AllowedEnv        []string
	TemplatesJSON     string
	ParserDir         string
	DefaultTimeout    time.Duration
	DefaultMaxOutput  int64
	ApprovalTTL       time.Duration
	RequireApproval   bool
	AllowArbitrary    bool
	ReadHeaderTimeout time.Duration
	ShutdownTimeout   time.Duration
}

// Server owns one embedded command service and its HTTP listener.
type Server struct {
	service   *command.Service
	http      *http.Server
	address   string
	closeOnce sync.Once
	closeErr  error
}

// Start opens command storage and serves command MCP routes.
func Start(ctx context.Context, cfg Config) (*Server, error) {
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	service, err := openService(cfg)
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp", strings.TrimSpace(cfg.ListenAddress))
	if err != nil {
		service.Close()
		return nil, fmt.Errorf("listen embedded command: %w", err)
	}
	readHeaderTimeout := cfg.ReadHeaderTimeout
	if readHeaderTimeout <= 0 {
		readHeaderTimeout = defaultReadHeaderTimeout
	}
	mux := http.NewServeMux()
	mcp := transport.NewMCPServer(service)
	mux.Handle("/mcp", mcp)
	mux.Handle("/mcp/", mcp)
	mux.HandleFunc("/healthz", healthHandler)
	server := &Server{
		service: service,
		address: listener.Addr().String(),
		http: &http.Server{
			Addr:              strings.TrimSpace(cfg.ListenAddress),
			Handler:           mux,
			ReadHeaderTimeout: readHeaderTimeout,
		},
	}
	go server.shutdownWhenDone(ctx, cfg.ShutdownTimeout)
	go func() {
		if err := server.http.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			service.Close()
		}
	}()
	return server, nil
}

// Address returns the bound command listener address.
func (s *Server) Address() string {
	if s == nil {
		return ""
	}
	return s.address
}

// Close gracefully stops the embedded command listener and active jobs.
func (s *Server) Close(ctx context.Context) error {
	if s == nil {
		return nil
	}
	s.closeOnce.Do(func() {
		if s.http != nil {
			s.closeErr = s.http.Shutdown(ctx)
		}
		if s.service != nil {
			s.service.Close()
		}
	})
	return s.closeErr
}

// openService translates embedded host config into command service config.
func openService(cfg Config) (*command.Service, error) {
	templates, err := command.ParseTemplatesJSON(cfg.TemplatesJSON)
	if err != nil {
		return nil, err
	}
	return command.Open(command.Config{
		DataDir:          cfg.DataDir,
		AllowedWorkdirs:  append([]string(nil), cfg.AllowedWorkdirs...),
		AllowedEnv:       append([]string(nil), cfg.AllowedEnv...),
		Templates:        templates,
		DefaultTimeout:   cfg.DefaultTimeout,
		DefaultMaxOutput: cfg.DefaultMaxOutput,
		ApprovalTTL:      cfg.ApprovalTTL,
		RequireApproval:  cfg.RequireApproval,
		AllowArbitrary:   cfg.AllowArbitrary,
		ParserDir:        cfg.ParserDir,
	})
}

// shutdownWhenDone closes command resources when the host context exits.
func (s *Server) shutdownWhenDone(ctx context.Context, timeout time.Duration) {
	<-ctx.Done()
	if timeout <= 0 {
		timeout = defaultShutdownTimeout
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	_ = s.Close(shutdownCtx)
}

// healthHandler reports embedded command liveness.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// validateConfig reports incomplete embedded command settings.
func validateConfig(cfg Config) error {
	if strings.TrimSpace(cfg.ListenAddress) == "" {
		return fmt.Errorf("embedded command listen address is required")
	}
	if strings.TrimSpace(cfg.DataDir) == "" {
		return fmt.Errorf("embedded command data directory is required")
	}
	return nil
}
