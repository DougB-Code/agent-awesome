// Package main starts the Agent Awesome workflow orchestration service.
package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"workflow/internal/runtime"
	"workflow/internal/transport"
)

const shutdownTimeout = 5 * time.Second

// main loads config, opens workflow runtime, and serves HTTP/MCP endpoints.
func main() {
	cfg, err := parseConfig(os.Args[1:])
	if err != nil {
		panic(err)
	}
	if cfg.CheckConfig {
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	service, err := runtime.Open(ctx, cfg.RuntimeConfig())
	if err != nil {
		panic(err)
	}
	defer service.Close()
	go service.StartScheduler(ctx)

	httpServer := &http.Server{
		Addr:              cfg.ListenAddress,
		Handler:           transport.NewHTTPServer(service).Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		_ = httpServer.Shutdown(shutdownCtx)
	}()
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		panic(err)
	}
}
