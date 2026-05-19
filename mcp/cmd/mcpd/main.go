// Package main starts the Agent Awesome local MCP manager daemon.
package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"mcp/internal/mcp"
	"mcp/internal/transport"
)

const shutdownTimeout = 5 * time.Second

// main loads configuration and serves MCP manager tools.
func main() {
	cfg, err := parseConfig(os.Args[1:])
	if err != nil {
		panic(err)
	}
	service, err := mcp.Open(cfg.MCP)
	if err != nil {
		panic(err)
	}
	if cfg.CheckConfig {
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := service.AutoStart(ctx); err != nil {
		panic(err)
	}
	mux := http.NewServeMux()
	mcpServer := transport.NewServer(service)
	mux.Handle("/mcp", mcpServer)
	mux.Handle("/mcp/", mcpServer)
	mux.HandleFunc("/healthz", healthHandler)
	server := &http.Server{Addr: cfg.ListenAddress, Handler: mux}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		panic(err)
	}
}

// healthHandler reports mcpd liveness.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
