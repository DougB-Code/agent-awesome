// This file implements the cron-friendly Launchpad queue worker.
package queueworker

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"agentawesome/internal/services/launchpad"
	runbookstore "agentawesome/internal/services/runbook/store"
)

const (
	defaultLeaseSeconds = 300
	defaultPollInterval = 5 * time.Second
	defaultRunTimeout   = 12 * time.Hour
)

// Config stores one queue worker invocation.
type Config struct {
	BaseURL        string
	AuthToken      string
	Profile        string
	TargetID       string
	LeaseSeconds   int
	PollInterval   time.Duration
	RunTimeout     time.Duration
	EnqueueDue     bool
	RecoverExpired bool
	HTTPClient     *http.Client
}

// Result summarizes one queue worker invocation.
type Result struct {
	Recovered   int    `json:"recovered"`
	Enqueued    int    `json:"enqueued"`
	Skipped     int    `json:"skipped"`
	NoWork      bool   `json:"no_work"`
	QueueID     string `json:"queue_id,omitempty"`
	RunID       string `json:"run_id,omitempty"`
	RunStatus   string `json:"run_status,omitempty"`
	QueueStatus string `json:"queue_status,omitempty"`
}

// RunOnce performs one cron tick: recover, enqueue due schedules, lease, start, and release one run.
func RunOnce(ctx context.Context, cfg Config) (Result, error) {
	cfg = defaultConfig(cfg)
	if err := validateConfig(cfg); err != nil {
		return Result{}, err
	}
	client, err := newClient(cfg)
	if err != nil {
		return Result{}, err
	}
	result := Result{}
	if cfg.RecoverExpired {
		recovered, err := client.recover(ctx)
		if err != nil {
			return result, err
		}
		result.Recovered = recovered
	}
	if cfg.EnqueueDue {
		scheduled, err := client.enqueueDue(ctx)
		if err != nil {
			return result, err
		}
		result.Enqueued = scheduled.Enqueued
		result.Skipped = scheduled.Skipped
	}
	lease, ok, err := client.lease(ctx, cfg.TargetID, cfg.LeaseSeconds)
	if err != nil {
		return result, err
	}
	if !ok {
		result.NoWork = true
		return result, nil
	}
	result.QueueID = lease.Item.ID
	started, err := client.start(ctx, lease.Item.ID, lease.LeaseID)
	if err != nil {
		releaseErr := client.release(ctx, lease.Item.ID, releaseRequest{
			LeaseID: lease.LeaseID,
			Status:  launchpad.LaunchRunQueueStatusFailed,
			Error:   err.Error(),
		})
		if releaseErr != nil {
			return result, fmt.Errorf("start queued launch run: %w; release failed lease: %v", err, releaseErr)
		}
		result.QueueStatus = launchpad.LaunchRunQueueStatusFailed
		return result, err
	}
	result.RunID = started.LaunchRun.Run.ID
	finalRun, err := client.waitForRun(ctx, cfg, lease, result.RunID)
	if err != nil {
		releaseErr := client.release(ctx, lease.Item.ID, releaseRequest{
			LeaseID: lease.LeaseID,
			RunID:   result.RunID,
			Status:  launchpad.LaunchRunQueueStatusFailed,
			Error:   err.Error(),
		})
		if releaseErr != nil {
			return result, fmt.Errorf("wait for runbook run: %w; release failed lease: %v", err, releaseErr)
		}
		result.QueueStatus = launchpad.LaunchRunQueueStatusFailed
		return result, err
	}
	result.RunStatus = finalRun.Status
	queueStatus, queueError := queueStatusForRun(finalRun)
	if err := client.release(ctx, lease.Item.ID, releaseRequest{
		LeaseID: lease.LeaseID,
		RunID:   finalRun.ID,
		Status:  queueStatus,
		Error:   queueError,
	}); err != nil {
		return result, err
	}
	result.QueueStatus = queueStatus
	return result, nil
}

// defaultConfig fills operational defaults for one worker tick.
func defaultConfig(cfg Config) Config {
	if cfg.LeaseSeconds <= 0 {
		cfg.LeaseSeconds = defaultLeaseSeconds
	}
	if cfg.PollInterval <= 0 {
		cfg.PollInterval = defaultPollInterval
	}
	if cfg.RunTimeout <= 0 {
		cfg.RunTimeout = defaultRunTimeout
	}
	if cfg.HTTPClient == nil {
		cfg.HTTPClient = http.DefaultClient
	}
	return cfg
}

// validateConfig checks the required remote worker connection settings.
func validateConfig(cfg Config) error {
	if strings.TrimSpace(cfg.BaseURL) == "" {
		return fmt.Errorf("gateway base URL is required")
	}
	if strings.TrimSpace(cfg.TargetID) == "" {
		return fmt.Errorf("target id is required")
	}
	return nil
}

// queueStatusForRun maps terminal runbook state onto durable queue state.
func queueStatusForRun(run runRecord) (string, string) {
	switch run.Status {
	case runbookstore.StatusSucceeded:
		return launchpad.LaunchRunQueueStatusCompleted, ""
	case runbookstore.StatusCanceled:
		return launchpad.LaunchRunQueueStatusCanceled, "runbook run canceled"
	default:
		return launchpad.LaunchRunQueueStatusFailed, "runbook run ended with status " + run.Status
	}
}

// client calls the Launchpad and runbook HTTP APIs.
type client struct {
	base       *url.URL
	authToken  string
	profile    string
	httpClient *http.Client
}

// newClient prepares one HTTP queue client.
func newClient(cfg Config) (*client, error) {
	base, err := url.Parse(strings.TrimRight(cfg.BaseURL, "/"))
	if err != nil {
		return nil, fmt.Errorf("parse gateway base URL: %w", err)
	}
	return &client{
		base:       base,
		authToken:  strings.TrimSpace(cfg.AuthToken),
		profile:    strings.TrimSpace(cfg.Profile),
		httpClient: cfg.HTTPClient,
	}, nil
}

// recover returns expired worker leases to the queue.
func (c *client) recover(ctx context.Context) (int, error) {
	var body recoverResponse
	if err := c.doJSON(ctx, http.MethodPost, "/launchpad/queue/recover", map[string]any{}, &body); err != nil {
		return 0, fmt.Errorf("recover launchpad queue leases: %w", err)
	}
	return body.Recovered, nil
}

// enqueueDue queues scheduled Launchpad entries that are due now.
func (c *client) enqueueDue(ctx context.Context) (scheduleSummary, error) {
	var body scheduleResponse
	if err := c.doJSON(ctx, http.MethodPost, "/launchpad/queue/enqueue-due", map[string]any{}, &body); err != nil {
		return scheduleSummary{}, fmt.Errorf("enqueue due launchpad schedules: %w", err)
	}
	return scheduleSummary{Enqueued: len(body.Schedule.Enqueued), Skipped: len(body.Schedule.Skipped)}, nil
}

// lease leases one queued Launch run for the target.
func (c *client) lease(ctx context.Context, targetID string, leaseSeconds int) (lease, bool, error) {
	var body leaseResponse
	err := c.doJSON(ctx, http.MethodPost, "/launchpad/queue/lease", map[string]any{
		"target_id":     targetID,
		"lease_seconds": leaseSeconds,
	}, &body)
	if isNoWorkError(err) {
		return lease{}, false, nil
	}
	if err != nil {
		return lease{}, false, fmt.Errorf("lease launchpad queue item: %w", err)
	}
	return body.Lease, true, nil
}

// start starts the runbook run bound to one queued Launch run.
func (c *client) start(ctx context.Context, queueID string, leaseID string) (startResponse, error) {
	var body startResponse
	if err := c.doJSON(ctx, http.MethodPost, "/launchpad/queue/"+url.PathEscape(queueID)+"/start", map[string]any{
		"lease_id": leaseID,
	}, &body); err != nil {
		return startResponse{}, fmt.Errorf("start launchpad queue item: %w", err)
	}
	return body, nil
}

// waitForRun polls until a started runbook reaches a terminal status.
func (c *client) waitForRun(ctx context.Context, cfg Config, lease lease, runID string) (runRecord, error) {
	waitCtx, cancel := context.WithTimeout(ctx, cfg.RunTimeout)
	defer cancel()
	ticker := time.NewTicker(cfg.PollInterval)
	defer ticker.Stop()
	renewEvery := time.Duration(cfg.LeaseSeconds) * time.Second / 2
	if renewEvery < cfg.PollInterval {
		renewEvery = cfg.PollInterval
	}
	nextRenew := time.Now().Add(renewEvery)
	for {
		run, err := c.runStatus(waitCtx, runID)
		if err != nil {
			return runRecord{}, err
		}
		if isTerminalRunStatus(run.Status) {
			return run, nil
		}
		if !time.Now().Before(nextRenew) {
			if err := c.renew(waitCtx, lease.Item.ID, lease.LeaseID, cfg.LeaseSeconds); err != nil {
				return runRecord{}, err
			}
			nextRenew = time.Now().Add(renewEvery)
		}
		select {
		case <-waitCtx.Done():
			return runRecord{}, fmt.Errorf("runbook run %q did not finish before worker timeout: %w", runID, waitCtx.Err())
		case <-ticker.C:
		}
	}
}

// runStatus loads one runbook run state.
func (c *client) runStatus(ctx context.Context, runID string) (runRecord, error) {
	var body runStatusResponse
	if err := c.doJSON(ctx, http.MethodGet, "/runbooks/runs/"+url.PathEscape(runID), nil, &body); err != nil {
		return runRecord{}, fmt.Errorf("get runbook run status: %w", err)
	}
	return body.Run, nil
}

// renew extends the worker lease while the runbook is active.
func (c *client) renew(ctx context.Context, queueID string, leaseID string, leaseSeconds int) error {
	var body map[string]any
	if err := c.doJSON(ctx, http.MethodPost, "/launchpad/queue/"+url.PathEscape(queueID)+"/renew", map[string]any{
		"lease_id":      leaseID,
		"lease_seconds": leaseSeconds,
	}, &body); err != nil {
		return fmt.Errorf("renew launchpad queue lease: %w", err)
	}
	return nil
}

// release marks a queue lease completed, failed, or canceled.
func (c *client) release(ctx context.Context, queueID string, req releaseRequest) error {
	var body map[string]any
	if err := c.doJSON(ctx, http.MethodPost, "/launchpad/queue/"+url.PathEscape(queueID)+"/release", req, &body); err != nil {
		return fmt.Errorf("release launchpad queue lease: %w", err)
	}
	return nil
}

// doJSON sends one JSON request and decodes a JSON response.
func (c *client) doJSON(ctx context.Context, method string, path string, payload any, target any) error {
	var body io.Reader
	if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		body = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.url(path), body)
	if err != nil {
		return err
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Accept", "application/json")
	if c.authToken != "" {
		req.Header.Set("Authorization", "Bearer "+c.authToken)
	}
	if c.profile != "" {
		req.Header.Set("X-Agent-Awesome-Profile", c.profile)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return httpError{StatusCode: resp.StatusCode, Body: string(data)}
	}
	if target == nil || len(bytes.TrimSpace(data)) == 0 {
		return nil
	}
	return json.Unmarshal(data, target)
}

// url returns one API path below the configured gateway base URL.
func (c *client) url(path string) string {
	base := *c.base
	prefix := strings.TrimRight(base.Path, "/")
	base.Path = prefix + path
	base.RawQuery = ""
	base.Fragment = ""
	return base.String()
}

// isTerminalRunStatus reports whether a runbook run no longer needs polling.
func isTerminalRunStatus(status string) bool {
	return status == runbookstore.StatusSucceeded || status == runbookstore.StatusFailed || status == runbookstore.StatusCanceled
}

// isNoWorkError reports whether lease failure means no queued item exists.
func isNoWorkError(err error) bool {
	var httpErr httpError
	if !errors.As(err, &httpErr) {
		return false
	}
	return httpErr.StatusCode == http.StatusBadRequest && strings.Contains(strings.ToLower(httpErr.Body), "no rows")
}

// httpError stores a non-2xx HTTP response.
type httpError struct {
	StatusCode int
	Body       string
}

// Error formats one HTTP API failure.
func (e httpError) Error() string {
	return fmt.Sprintf("http %d: %s", e.StatusCode, strings.TrimSpace(e.Body))
}

// scheduleSummary stores schedule enqueue counts.
type scheduleSummary struct {
	Enqueued int
	Skipped  int
}

// recoverResponse decodes queue recovery output.
type recoverResponse struct {
	Recovered int `json:"recovered"`
}

// scheduleResponse decodes due schedule output.
type scheduleResponse struct {
	Schedule struct {
		Enqueued []launchpad.LaunchRunQueueItem `json:"enqueued"`
		Skipped  []any                          `json:"skipped"`
	} `json:"schedule"`
}

// leaseResponse decodes one queue lease response.
type leaseResponse struct {
	Lease lease `json:"lease"`
}

// lease stores one leased queue item.
type lease struct {
	Item           launchpad.LaunchRunQueueItem `json:"item"`
	LeaseID        string                       `json:"lease_id"`
	LeaseExpiresAt string                       `json:"lease_expires_at"`
}

// startResponse decodes one queued Launch start response.
type startResponse struct {
	LaunchRun struct {
		Run  runRecord                    `json:"run"`
		Item launchpad.LaunchRunQueueItem `json:"item"`
	} `json:"launch_run"`
}

// runStatusResponse decodes one runbook status response.
type runStatusResponse struct {
	Run runRecord `json:"run"`
}

// runRecord stores fields needed from a runbook run.
type runRecord struct {
	ID     string `json:"id"`
	Status string `json:"status"`
	State  string `json:"state"`
}

// releaseRequest stores one queue lease release payload.
type releaseRequest struct {
	LeaseID string `json:"lease_id"`
	Status  string `json:"status"`
	RunID   string `json:"run_id,omitempty"`
	Error   string `json:"error,omitempty"`
}
