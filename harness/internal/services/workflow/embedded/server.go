// This file starts workflow services inside a host process.
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

	"agentawesome/internal/services/workflow/runtime"
	"agentawesome/internal/services/workflow/transport"
)

const (
	defaultReadHeaderTimeout = 5 * time.Second
	defaultShutdownTimeout   = 5 * time.Second
)

// Config stores the host-owned workflow listener and runtime settings.
type Config struct {
	ListenAddress         string
	DefinitionsDir        string
	DatabasePath          string
	HarnessContextBaseURL string
	RequestTimeout        time.Duration
	ToolClient            runtime.ContextToolClient
	CommandClient         runtime.CommandClient
	MCPServerEndpoints    map[string]string
	ReadHeaderTimeout     time.Duration
	ShutdownTimeout       time.Duration
}

// Server owns one embedded workflow service and its HTTP listener.
type Server struct {
	service   *runtime.Service
	http      *http.Server
	closeOnce sync.Once
	closeErr  error
}

// Start opens workflow storage, starts scheduling, and serves workflow routes.
func Start(ctx context.Context, cfg Config) (*Server, error) {
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	service, err := runtime.Open(ctx, runtime.Config{
		DefinitionsDir:         cfg.DefinitionsDir,
		DatabasePath:           cfg.DatabasePath,
		HarnessContextBaseURL:  cfg.HarnessContextBaseURL,
		RequestTimeout:         cfg.RequestTimeout,
		ToolClient:             cfg.ToolClient,
		CommandClient:          cfg.CommandClient,
		MCPServerEndpoints:     cfg.MCPServerEndpoints,
		SkipInvalidDefinitions: true,
	})
	if err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp", strings.TrimSpace(cfg.ListenAddress))
	if err != nil {
		_ = service.Close()
		return nil, fmt.Errorf("listen embedded workflow: %w", err)
	}
	readHeaderTimeout := cfg.ReadHeaderTimeout
	if readHeaderTimeout <= 0 {
		readHeaderTimeout = defaultReadHeaderTimeout
	}
	server := &Server{
		service: service,
		http: &http.Server{
			Addr:              listener.Addr().String(),
			Handler:           transport.NewHTTPServer(service).Routes(),
			ReadHeaderTimeout: readHeaderTimeout,
		},
	}
	go service.StartScheduler(ctx)
	go server.shutdownWhenDone(ctx, cfg.ShutdownTimeout)
	go func() {
		if err := server.http.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			_ = service.Close()
		}
	}()
	return server, nil
}

// Close gracefully stops the embedded workflow listener and store.
func (s *Server) Close(ctx context.Context) error {
	if s == nil {
		return nil
	}
	s.closeOnce.Do(func() {
		var shutdownErr error
		if s.http != nil {
			shutdownErr = s.http.Shutdown(ctx)
		}
		closeErr := s.service.Close()
		if shutdownErr != nil {
			s.closeErr = shutdownErr
			return
		}
		s.closeErr = closeErr
	})
	return s.closeErr
}

// shutdownWhenDone closes workflow resources when the host context exits.
func (s *Server) shutdownWhenDone(ctx context.Context, timeout time.Duration) {
	<-ctx.Done()
	if timeout <= 0 {
		timeout = defaultShutdownTimeout
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	_ = s.Close(shutdownCtx)
}

// validateConfig reports incomplete embedded workflow settings.
func validateConfig(cfg Config) error {
	if strings.TrimSpace(cfg.ListenAddress) == "" {
		return fmt.Errorf("embedded workflow listen address is required")
	}
	if strings.TrimSpace(cfg.DefinitionsDir) == "" {
		return fmt.Errorf("embedded workflow definitions directory is required")
	}
	if strings.TrimSpace(cfg.DatabasePath) == "" {
		return fmt.Errorf("embedded workflow database path is required")
	}
	return nil
}
