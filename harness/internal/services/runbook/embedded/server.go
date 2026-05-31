// This file starts runbook services inside a host process.
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

	"agentawesome/internal/services/capabilities"
	"agentawesome/internal/services/launchpad"
	"agentawesome/internal/services/targets"
	"agentawesome/internal/services/runbook/runtime"
	"agentawesome/internal/services/runbook/transport"
)

const (
	defaultReadHeaderTimeout = 5 * time.Second
	defaultShutdownTimeout   = 5 * time.Second
)

// Config stores the host-owned runbook listener and runtime settings.
type Config struct {
	ListenAddress              string
	DefinitionsDir             string
	DatabasePath               string
	LaunchpadDatabasePath     string
	RuntimeTargetsDatabasePath string
	HarnessContextBaseURL      string
	RequestTimeout             time.Duration
	ToolClient                 runtime.ContextToolClient
	CommandClient              runtime.CommandClient
	MCPServerEndpoints         map[string]string
	Capabilities               *capabilities.Registry
	ReadHeaderTimeout          time.Duration
	ShutdownTimeout            time.Duration
}

// Server owns one embedded runbook service and its HTTP listener.
type Server struct {
	service         *runtime.Service
	operations      *launchpad.Service
	operationsStore *launchpad.Store
	targetsStore    *targets.Store
	http            *http.Server
	closeOnce       sync.Once
	closeErr        error
}

// Start opens runbook storage, starts scheduling, and serves runbook routes.
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
		Capabilities:           cfg.Capabilities,
		SkipInvalidDefinitions: true,
	})
	if err != nil {
		return nil, err
	}
	operationsStore, err := launchpad.OpenStore(ctx, defaulted(cfg.LaunchpadDatabasePath, cfg.DatabasePath))
	if err != nil {
		_ = service.Close()
		return nil, err
	}
	targetsStore, err := targets.OpenStore(ctx, defaulted(cfg.RuntimeTargetsDatabasePath, cfg.DatabasePath))
	if err != nil {
		_ = operationsStore.Close()
		_ = service.Close()
		return nil, err
	}
	targetsService := targets.NewService(targetsStore)
	if _, err := targetsService.RegisterLocalTarget(ctx, targets.LocalRegistration{
		Version:      "0.1.0",
		Capabilities: capabilityIDs(cfg.Capabilities),
	}); err != nil {
		_ = targetsStore.Close()
		_ = operationsStore.Close()
		_ = service.Close()
		return nil, err
	}
	var codebases launchpad.CodebaseCatalog
	if endpoint := strings.TrimSpace(cfg.MCPServerEndpoints["memory"]); endpoint != "" {
		codebases = launchpad.NewMemoryCodebaseClient(endpoint, cfg.RequestTimeout)
	}
	operationsService := launchpad.NewService(operationsStore, launchpad.NewRuntimeRunbookExecutor(service), codebases)
	listener, err := net.Listen("tcp", strings.TrimSpace(cfg.ListenAddress))
	if err != nil {
		_ = targetsStore.Close()
		_ = operationsStore.Close()
		_ = service.Close()
		return nil, fmt.Errorf("listen embedded runbook: %w", err)
	}
	readHeaderTimeout := cfg.ReadHeaderTimeout
	if readHeaderTimeout <= 0 {
		readHeaderTimeout = defaultReadHeaderTimeout
	}
	server := &Server{
		service:         service,
		operations:      operationsService,
		operationsStore: operationsStore,
		targetsStore:    targetsStore,
		http: &http.Server{
			Addr:              listener.Addr().String(),
			Handler:           combinedRoutes(service, operationsService, targetsService, cfg.Capabilities),
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

// Close gracefully stops the embedded runbook listener and store.
func (s *Server) Close(ctx context.Context) error {
	if s == nil {
		return nil
	}
	s.closeOnce.Do(func() {
		var shutdownErr error
		if s.http != nil {
			shutdownErr = s.http.Shutdown(ctx)
		}
		if s.operationsStore != nil {
			_ = s.operationsStore.Close()
		}
		if s.targetsStore != nil {
			_ = s.targetsStore.Close()
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

// shutdownWhenDone closes runbook resources when the host context exits.
func (s *Server) shutdownWhenDone(ctx context.Context, timeout time.Duration) {
	<-ctx.Done()
	if timeout <= 0 {
		timeout = defaultShutdownTimeout
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	_ = s.Close(shutdownCtx)
}

// validateConfig reports incomplete embedded runbook settings.
func validateConfig(cfg Config) error {
	if strings.TrimSpace(cfg.ListenAddress) == "" {
		return fmt.Errorf("embedded runbook listen address is required")
	}
	if strings.TrimSpace(cfg.DefinitionsDir) == "" {
		return fmt.Errorf("embedded runbook definitions directory is required")
	}
	if strings.TrimSpace(cfg.DatabasePath) == "" {
		return fmt.Errorf("embedded runbook database path is required")
	}
	return nil
}

// combinedRoutes serves runbook and operations routes from one listener.
func combinedRoutes(runbook *runtime.Service, operationsService *launchpad.Service, targetsService *targets.Service, capabilityRegistry *capabilities.Registry) http.Handler {
	mux := http.NewServeMux()
	if targetsService != nil {
		targetRoutes := targets.NewHTTPServer(targetsService).Routes()
		mux.Handle("/api/runtime-targets", targetRoutes)
		mux.Handle("/api/runtime-targets/", targetRoutes)
	}
	if capabilityRegistry != nil {
		capabilityRoutes := capabilities.NewHTTPServer(capabilityRegistry).Routes()
		mux.Handle("/api/capabilities", capabilityRoutes)
		mux.Handle("/api/capabilities/", capabilityRoutes)
	}
	if operationsService != nil {
		operationsRoutes := launchpad.NewHTTPServer(operationsService).Routes()
		mux.Handle("/api/launchpad", operationsRoutes)
		mux.Handle("/api/launchpad/", operationsRoutes)
	}
	mux.Handle("/", transport.NewHTTPServer(runbook).Routes())
	return mux
}

// defaulted returns fallback when value is blank.
func defaulted(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

// capabilityIDs extracts stable ids from the registry for target heartbeat inventory.
func capabilityIDs(registry *capabilities.Registry) []string {
	if registry == nil {
		return nil
	}
	records := registry.List(capabilities.Query{})
	ids := make([]string, 0, len(records))
	for _, record := range records {
		ids = append(ids, record.ID)
	}
	return ids
}
