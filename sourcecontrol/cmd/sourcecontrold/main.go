// Package main starts the Agent Awesome source-control daemon.
package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"sourcecontrol/internal/sourcecontrol"
	"sourcecontrol/internal/transport"
)

const shutdownTimeout = 5 * time.Second

// main loads configuration and serves source-control tools.
func main() {
	cfg, err := parseConfig(os.Args[1:])
	if err != nil {
		panic(err)
	}
	service, err := sourcecontrol.Open(cfg.SourceControl)
	if err != nil {
		panic(err)
	}
	if cfg.CheckConfig {
		return
	}
	mux := http.NewServeMux()
	mcpServer := transport.NewServer(service)
	mux.Handle("/mcp", mcpServer)
	mux.Handle("/mcp/", mcpServer)
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
		panic(err)
	}
}

// healthHandler reports sourcecontrold liveness.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
