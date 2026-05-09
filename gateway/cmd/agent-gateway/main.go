// Package main starts the personal Agent Awesome gateway.
package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"agentgateway/internal/config"
	"agentgateway/internal/gateway"
	"agentgateway/internal/logging"
	"agentgateway/internal/supervisor"
	"github.com/rs/zerolog/log"
)

// main loads configuration, starts optional local services, and serves HTTP.
func main() {
	closeLog, err := logging.Configure("")
	if err != nil {
		log.Fatal().Err(err).Msg("configure logging")
	}
	defer closeLog()

	cfg, err := config.FromFlags(os.Args[1:])
	if err != nil {
		log.Fatal().Err(err).Msg("load config")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	manager := supervisor.New(cfg.ServiceStartTimeout)
	services := dependencyServices(cfg)
	manager.Expect(services...)

	server, err := gateway.NewServer(cfg, manager)
	if err != nil {
		log.Fatal().Err(err).Msg("create gateway")
	}
	go ensureServices(ctx, manager, services)
	if server.SlackSocketModeEnabled() {
		go func() {
			if err := server.RunSlackSocketMode(ctx); err != nil && !errors.Is(err, context.Canceled) {
				log.Error().Err(err).Msg("slack socket mode stopped")
			}
		}()
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.HTTPServer().Shutdown(shutdownCtx); err != nil {
			log.Error().Err(err).Msg("shutdown gateway")
		}
		if err := manager.Close(shutdownCtx); err != nil && !errors.Is(err, context.Canceled) {
			log.Error().Err(err).Msg("shutdown services")
		}
	}()

	log.Info().Str("addr", cfg.ListenAddress).Msg("agent-gateway listening")
	if err := server.HTTPServer().ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal().Err(err).Msg("serve gateway")
	}
}

// dependencyServices maps gateway config to supervised dependency declarations.
func dependencyServices(cfg config.Config) []supervisor.Service {
	return []supervisor.Service{
		{
			Name:       cfg.HarnessService.Name,
			HealthURL:  cfg.HarnessService.HealthURL,
			Command:    cfg.HarnessService.Command,
			Arguments:  cfg.HarnessService.Arguments,
			WorkingDir: cfg.HarnessService.WorkingDir,
			AutoStart:  cfg.HarnessService.AutoStart,
		},
		{
			Name:       cfg.MemoryService.Name,
			HealthURL:  cfg.MemoryService.HealthURL,
			Command:    cfg.MemoryService.Command,
			Arguments:  cfg.MemoryService.Arguments,
			WorkingDir: cfg.MemoryService.WorkingDir,
			AutoStart:  cfg.MemoryService.AutoStart,
		},
	}
}

// ensureServices checks or starts dependencies declared in gateway config.
func ensureServices(ctx context.Context, manager *supervisor.Manager, services []supervisor.Service) {
	started := time.Now()
	log.Info().Msg("dependency startup begin")
	for _, service := range services {
		serviceStarted := time.Now()
		log.Info().Str("service", service.Name).Msg("dependency startup begin")
		status := manager.Ensure(ctx, service)
		log.Info().
			Str("service", service.Name).
			Dur("duration", time.Since(serviceStarted).Round(time.Millisecond)).
			Any("status", status).
			Msg("dependency startup complete")
	}
	log.Info().
		Dur("duration", time.Since(started).Round(time.Millisecond)).
		Msg("dependency startup complete")
}
