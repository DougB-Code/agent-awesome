// Package main starts the personal Agent Awesome gateway.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"agentgateway/internal/config"
	"agentgateway/internal/gateway"
	"agentgateway/internal/supervisor"
)

// main loads configuration, starts optional local services, and serves HTTP.
func main() {
	cfg, err := config.FromFlags(os.Args[1:])
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	manager := supervisor.New(cfg.ServiceStartTimeout)

	server, err := gateway.NewServer(cfg, manager)
	if err != nil {
		log.Fatalf("create gateway: %v", err)
	}
	go ensureServices(ctx, cfg, manager)
	if server.SlackSocketModeEnabled() {
		go func() {
			if err := server.RunSlackSocketMode(ctx); err != nil && !errors.Is(err, context.Canceled) {
				log.Printf("slack socket mode stopped: %v", err)
			}
		}()
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.HTTPServer().Shutdown(shutdownCtx); err != nil {
			log.Printf("shutdown gateway: %v", err)
		}
		if err := manager.Close(shutdownCtx); err != nil && !errors.Is(err, context.Canceled) {
			log.Printf("shutdown services: %v", err)
		}
	}()

	log.Printf("agent-gateway listening on http://%s", cfg.ListenAddress)
	if err := server.HTTPServer().ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve gateway: %v", err)
	}
}

// ensureServices checks or starts dependencies declared in gateway config.
func ensureServices(ctx context.Context, cfg config.Config, manager *supervisor.Manager) {
	started := time.Now()
	log.Printf("dependency startup begin")
	harness := supervisor.Service{
		Name:       cfg.HarnessService.Name,
		HealthURL:  cfg.HarnessService.HealthURL,
		Command:    cfg.HarnessService.Command,
		Arguments:  cfg.HarnessService.Arguments,
		WorkingDir: cfg.HarnessService.WorkingDir,
		AutoStart:  cfg.HarnessService.AutoStart,
	}
	memory := supervisor.Service{
		Name:       cfg.MemoryService.Name,
		HealthURL:  cfg.MemoryService.HealthURL,
		Command:    cfg.MemoryService.Command,
		Arguments:  cfg.MemoryService.Arguments,
		WorkingDir: cfg.MemoryService.WorkingDir,
		AutoStart:  cfg.MemoryService.AutoStart,
	}
	harnessStarted := time.Now()
	log.Printf("harness startup begin")
	log.Printf("harness status after %s: %+v", time.Since(harnessStarted).Round(time.Millisecond), manager.Ensure(ctx, harness))
	memoryStarted := time.Now()
	log.Printf("memory startup begin")
	log.Printf("memory status after %s: %+v", time.Since(memoryStarted).Round(time.Millisecond), manager.Ensure(ctx, memory))
	log.Printf("dependency startup complete after %s", time.Since(started).Round(time.Millisecond))
}
