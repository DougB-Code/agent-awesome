// This file starts MCP manager services inside a host process.
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

	mcpconfig "agentawesome/internal/services/mcp/config"
	"agentawesome/internal/services/mcp/mcp"
	"agentawesome/internal/services/mcp/transport"
)

const (
	defaultReadHeaderTimeout = 5 * time.Second
	defaultShutdownTimeout   = 5 * time.Second
)

// Config stores the host-owned MCP manager listener and runtime settings.
type Config struct {
	ListenAddress     string
	ServersJSON       string
	RequestTimeout    time.Duration
	ReadHeaderTimeout time.Duration
	ShutdownTimeout   time.Duration
}

// Server owns one embedded MCP manager service and its HTTP listener.
type Server struct {
	service   *mcp.Service
	http      *http.Server
	address   string
	closeOnce sync.Once
	closeErr  error
}

// Start opens MCP manager state, starts configured servers, and serves routes.
func Start(ctx context.Context, cfg Config) (*Server, error) {
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	service, err := openService(cfg)
	if err != nil {
		return nil, err
	}
	if err := service.AutoStart(ctx); err != nil {
		_ = service.Close(context.Background())
		return nil, err
	}
	listener, err := net.Listen("tcp", strings.TrimSpace(cfg.ListenAddress))
	if err != nil {
		_ = service.Close(context.Background())
		return nil, fmt.Errorf("listen embedded MCP manager: %w", err)
	}
	readHeaderTimeout := cfg.ReadHeaderTimeout
	if readHeaderTimeout <= 0 {
		readHeaderTimeout = defaultReadHeaderTimeout
	}
	mux := http.NewServeMux()
	manager := transport.NewServer(service)
	mux.Handle("/mcp", manager)
	mux.Handle("/mcp/", manager)
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
			_ = service.Close(context.Background())
		}
	}()
	return server, nil
}

// Address returns the bound MCP manager listener address.
func (s *Server) Address() string {
	if s == nil {
		return ""
	}
	return s.address
}

// Close gracefully stops the embedded MCP manager listener and processes.
func (s *Server) Close(ctx context.Context) error {
	if s == nil {
		return nil
	}
	s.closeOnce.Do(func() {
		var shutdownErr error
		if s.http != nil {
			shutdownErr = s.http.Shutdown(ctx)
		}
		var closeErr error
		if s.service != nil {
			closeErr = s.service.Close(ctx)
		}
		if shutdownErr != nil {
			s.closeErr = shutdownErr
			return
		}
		s.closeErr = closeErr
	})
	return s.closeErr
}

// openService translates embedded config into MCP manager service config.
func openService(cfg Config) (*mcp.Service, error) {
	servers, err := mcpconfig.ParseServersJSON(cfg.ServersJSON)
	if err != nil {
		return nil, err
	}
	return mcp.Open(mcp.Config{
		Servers:        servers,
		RequestTimeout: cfg.RequestTimeout,
	})
}

// shutdownWhenDone closes MCP manager resources when the host context exits.
func (s *Server) shutdownWhenDone(ctx context.Context, timeout time.Duration) {
	<-ctx.Done()
	if timeout <= 0 {
		timeout = defaultShutdownTimeout
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	_ = s.Close(shutdownCtx)
}

// healthHandler reports embedded MCP manager liveness.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// validateConfig reports incomplete embedded MCP manager settings.
func validateConfig(cfg Config) error {
	if strings.TrimSpace(cfg.ListenAddress) == "" {
		return fmt.Errorf("embedded MCP manager listen address is required")
	}
	return nil
}
