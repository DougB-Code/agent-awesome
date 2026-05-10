// Package main starts the standalone memory service process.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rs/zerolog/log"

	"memory/internal/logging"
	graphrepo "memory/internal/memory/graph/repository"
	"memory/internal/memory/persistence"
	"memory/internal/memory/service"
	"memory/internal/memory/transport"
)

// main parses configuration, starts workers, and serves MCP plus health routes.
func main() {
	cfg, err := parseConfig(os.Args[1:])
	if err != nil {
		log.Fatal().Err(err).Msg("load config")
	}
	closeLog, err := logging.Configure(cfg.LogFile)
	if err != nil {
		log.Fatal().Err(err).Msg("configure logging")
	}
	defer closeLog()
	if cfg.CheckConfig {
		log.Info().Msg("memoryd config ok")
		return
	}

	ctx, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()

	snapshotStore := persistence.HTTPStore{
		URL:     cfg.SnapshotURL,
		Token:   cfg.SnapshotToken,
		Timeout: cfg.SnapshotTimeout,
	}
	snapshotRuntime := newSnapshotRuntimeStatus(snapshotStore.Enabled())
	if snapshotStore.Enabled() {
		log.Info().Msg("restore memory snapshot begin")
	} else {
		log.Info().Msg("restore memory snapshot skipped")
	}
	if err := snapshotStore.Restore(ctx, cfg.DBPath, cfg.DataRoot); err != nil {
		snapshotRuntime.restoreFailed(err)
		log.Fatal().Err(err).Msg("restore memory snapshot")
	}
	if snapshotStore.Enabled() {
		snapshotRuntime.restoreComplete()
		log.Info().Msg("restore memory snapshot complete")
	}

	repo, err := graphrepo.Open(ctx, graphrepo.Config{DBPath: cfg.DBPath, DataRoot: cfg.DataRoot})
	if err != nil {
		log.Fatal().Err(err).Msg("open graph memory store")
	}
	memoryService := service.New(repo, nil, service.Config{WorkerCount: cfg.WorkerCount})
	memoryService.Start(ctx)
	defer func() {
		closeCtx, cancelClose := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancelClose()
		if err := memoryService.Close(closeCtx); err != nil {
			log.Error().Err(err).Msg("close memory service")
		}
		snapshotCtx, cancelSnapshot := context.WithTimeout(context.Background(), cfg.SnapshotTimeout)
		defer cancelSnapshot()
		if snapshotStore.Enabled() {
			snapshotRuntime.saveBegin()
			log.Info().Msg("save memory snapshot begin")
		}
		if err := snapshotStore.Save(snapshotCtx, cfg.DBPath, cfg.DataRoot); err != nil {
			snapshotRuntime.saveFailed(err)
			log.Error().Err(err).Msg("save memory snapshot")
		} else if snapshotStore.Enabled() {
			snapshotRuntime.saveComplete()
			log.Info().Msg("save memory snapshot complete")
		}
	}()

	mux := http.NewServeMux()
	mux.Handle("/mcp", transport.NewMCPServer(memoryService))
	mux.HandleFunc("/healthz", healthHandler(snapshotRuntime))
	mux.HandleFunc("/metrics", metricsHandler(memoryService))

	server := &http.Server{
		Addr:              cfg.ListenAddress,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Error().Err(err).Msg("shutdown server")
		}
	}()

	log.Info().Str("addr", cfg.ListenAddress).Msg("memoryd listening")
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal().Err(err).Msg("serve memoryd")
	}
}

// healthHandler reports service process liveness and snapshot state.
func healthHandler(snapshotRuntime *snapshotRuntimeStatus) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":   "ok",
			"snapshot": snapshotRuntime.view(),
		})
	}
}

// metricsHandler returns operational memory service counters.
func metricsHandler(memoryService *service.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		metrics, err := memoryService.Metrics(r.Context())
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, metrics)
	}
}

// writeJSON writes a JSON HTTP response.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
