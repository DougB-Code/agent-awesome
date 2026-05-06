// Package main starts the standalone memory service process.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	graphrepo "memory/internal/memory/graph/repository"
	"memory/internal/memory/persistence"
	"memory/internal/memory/service"
	"memory/internal/memory/transport"
)

// main parses configuration, starts workers, and serves MCP plus health routes.
func main() {
	addr := flag.String("addr", "127.0.0.1:8090", "HTTP listen address")
	dbPath := flag.String("db", "memory.db", "SQLite database path")
	dataRoot := flag.String("data", "data", "filesystem artifact root")
	logFile := flag.String("log-file", "", "log file path")
	workers := flag.Int("workers", 2, "background worker count")
	snapshotURL := flag.String("snapshot-url", "", "optional authenticated HTTP snapshot endpoint")
	snapshotToken := flag.String("snapshot-token", "", "bearer token for the snapshot endpoint")
	snapshotTimeout := flag.Duration("snapshot-timeout", 30*time.Second, "snapshot restore and save timeout")
	flag.Parse()
	closeLog := configureLogging(*logFile)
	defer closeLog()

	ctx, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()

	snapshotStore := persistence.HTTPStore{
		URL:     *snapshotURL,
		Token:   *snapshotToken,
		Timeout: *snapshotTimeout,
	}
	if err := snapshotStore.Restore(ctx, *dbPath, *dataRoot); err != nil {
		log.Fatalf("restore memory snapshot: %v", err)
	}

	repo, err := graphrepo.Open(ctx, graphrepo.Config{DBPath: *dbPath, DataRoot: *dataRoot})
	if err != nil {
		log.Fatalf("open graph memory store: %v", err)
	}
	memoryService := service.New(repo, nil, service.Config{WorkerCount: *workers})
	memoryService.Start(ctx)
	defer func() {
		closeCtx, cancelClose := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancelClose()
		if err := memoryService.Close(closeCtx); err != nil {
			log.Printf("close memory service: %v", err)
		}
		snapshotCtx, cancelSnapshot := context.WithTimeout(context.Background(), *snapshotTimeout)
		defer cancelSnapshot()
		if err := snapshotStore.Save(snapshotCtx, *dbPath, *dataRoot); err != nil {
			log.Printf("save memory snapshot: %v", err)
		}
	}()

	mux := http.NewServeMux()
	mux.Handle("/mcp", transport.NewMCPServer(memoryService))
	mux.HandleFunc("/healthz", healthHandler)
	mux.HandleFunc("/metrics", metricsHandler(memoryService))

	server := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("shutdown server: %v", err)
		}
	}()

	log.Printf("memoryd listening on http://%s", *addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve memoryd: %v", err)
	}
}

// configureLogging routes standard logs to the supplied file when configured.
func configureLogging(path string) func() {
	if path == "" {
		return func() {}
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		log.Fatalf("create log directory: %v", err)
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		log.Fatalf("open log file: %v", err)
	}
	log.SetOutput(file)
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	return func() {
		_ = file.Close()
	}
}

// healthHandler reports service process liveness.
func healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
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
