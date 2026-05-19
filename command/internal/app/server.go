// This file starts the command daemon HTTP server.
package app

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"command/internal/command"
	"command/internal/transport"
)

const shutdownTimeout = 5 * time.Second

// Main loads configuration and serves the command MCP endpoint.
func Main(processName string, args []string) error {
	cfg, err := ParseConfig(args, processName)
	if err != nil {
		return err
	}
	service, err := command.Open(cfg.Command)
	if err != nil {
		return err
	}
	if cfg.CheckConfig {
		return nil
	}
	mux := http.NewServeMux()
	mcp := transport.NewMCPServer(service)
	mux.Handle("/mcp", mcp)
	mux.Handle("/mcp/", mcp)
	mux.HandleFunc("/healthz", healthHandler)
	server := &http.Server{Addr: cfg.ListenAddress, Handler: mux}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// healthHandler reports command daemon liveness.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
