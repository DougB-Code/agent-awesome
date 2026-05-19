// This file implements the policy-managed command execution service.
package command

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	commandparser "command/internal/parser"
)

const (
	statusPending   = "pending"
	statusApproved  = "approved"
	statusRunning   = "running"
	statusSucceeded = "succeeded"
	statusFailed    = "failed"
	statusCanceled  = "canceled"
)

var safeIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)
var templateParameterPattern = regexp.MustCompile(`\{\{\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}`)

// Config stores command service policy and durable paths.
type Config struct {
	DataDir          string
	AllowedWorkdirs  []string
	AllowedEnv       []string
	Templates        []Template
	DefaultTimeout   time.Duration
	DefaultMaxOutput int64
	ApprovalTTL      time.Duration
	RequireApproval  bool
	AllowArbitrary   bool
	ParserDir        string
}

// Template stores one configured named command shape.
type Template struct {
	ID                     string            `json:"id"`
	Description            string            `json:"description"`
	Executable             string            `json:"executable"`
	Args                   []string          `json:"args"`
	Stdin                  string            `json:"stdin,omitempty"`
	WorkingDir             string            `json:"working_dir,omitempty"`
	Env                    map[string]string `json:"env,omitempty"`
	Timeout                time.Duration     `json:"timeout,omitempty"`
	MaxOutputBytes         int64             `json:"max_output_bytes,omitempty"`
	RequireApproval        bool              `json:"require_approval,omitempty"`
	ParameterSchema        map[string]any    `json:"parameter_schema,omitempty"`
	OutputContract         OutputContract    `json:"output_contract,omitempty"`
	ParserID               string            `json:"parser_id,omitempty"`
	OutputSource           string            `json:"output_source,omitempty"`
	ArtifactGlobs          []string          `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any    `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string            `json:"working_directory_policy,omitempty"`
	ValidationSchema       map[string]any    `json:"validation_schema,omitempty"`
}

// TemplateSummary describes a configured command template without secret-bearing fields.
type TemplateSummary struct {
	ID                     string         `json:"id"`
	Description            string         `json:"description"`
	Parameters             []string       `json:"parameters,omitempty"`
	ApprovalRequired       bool           `json:"approval_required"`
	Timeout                string         `json:"timeout,omitempty"`
	MaxOutputBytes         int64          `json:"max_output_bytes,omitempty"`
	ParameterSchema        map[string]any `json:"parameter_schema,omitempty"`
	OutputContract         OutputContract `json:"output_contract,omitempty"`
	ParserID               string         `json:"parser_id,omitempty"`
	OutputSource           string         `json:"output_source,omitempty"`
	ArtifactGlobs          []string       `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string         `json:"working_directory_policy,omitempty"`
}

// Request stores one command proposal request.
type Request struct {
	TemplateID string            `json:"template_id,omitempty"`
	Parameters map[string]any    `json:"parameters,omitempty"`
	Executable string            `json:"executable,omitempty"`
	Args       []string          `json:"args,omitempty"`
	Stdin      string            `json:"stdin,omitempty"`
	WorkingDir string            `json:"cwd,omitempty"`
	Reason     string            `json:"reason,omitempty"`
	Risk       string            `json:"risk,omitempty"`
	Actor      string            `json:"actor,omitempty"`
	SessionID  string            `json:"session_id,omitempty"`
	Env        map[string]string `json:"env,omitempty"`
}

// RequestResult stores the frozen proposal returned for approval.
type RequestResult struct {
	ApprovalID       string   `json:"approval_id"`
	ApprovalRequired bool     `json:"approval_required"`
	Status           string   `json:"status"`
	Summary          string   `json:"summary"`
	Executable       string   `json:"executable"`
	Args             []string `json:"args"`
	WorkingDir       string   `json:"cwd"`
	ExpiresAt        string   `json:"expires_at"`
	EnvNames         []string `json:"env_names,omitempty"`
	HasStdin         bool     `json:"has_stdin,omitempty"`
}

// RunRequest stores a command execution request.
type RunRequest struct {
	ApprovalID string `json:"approval_id"`
}

// RunResult stores the job id returned after command launch.
type RunResult struct {
	JobID  string `json:"job_id"`
	Status string `json:"status"`
}

// StatusResult stores observable command job state.
type StatusResult struct {
	JobID       string           `json:"job_id"`
	Status      string           `json:"status"`
	ExitCode    int              `json:"exit_code"`
	StdoutTail  string           `json:"stdout_tail"`
	StderrTail  string           `json:"stderr_tail"`
	Truncated   bool             `json:"truncated"`
	TimedOut    bool             `json:"timed_out"`
	Error       string           `json:"error,omitempty"`
	StartedAt   string           `json:"started_at"`
	EndedAt     string           `json:"ended_at,omitempty"`
	Output      any              `json:"output,omitempty"`
	Diagnostics []Diagnostic     `json:"diagnostics,omitempty"`
	Artifacts   []Artifact       `json:"artifacts,omitempty"`
	Validation  ValidationResult `json:"validation,omitempty"`
}

// ExecuteRequest stores one workflow-friendly command execution request.
type ExecuteRequest struct {
	TemplateID string         `json:"template_id"`
	Parameters map[string]any `json:"parameters,omitempty"`
	WorkingDir string         `json:"cwd,omitempty"`
	Reason     string         `json:"reason,omitempty"`
	Actor      string         `json:"actor,omitempty"`
	SessionID  string         `json:"session_id,omitempty"`
}

// Service validates command requests, records approvals, and tracks jobs.
type Service struct {
	cfg       Config
	roots     []string
	templates map[string]Template
	parsers   *commandparser.Catalog
	mu        sync.Mutex
	jobs      map[string]context.CancelFunc
}

// Open validates policy paths and creates a command service.
func Open(cfg Config) (*Service, error) {
	normalized, err := normalizeConfig(cfg)
	if err != nil {
		return nil, err
	}
	roots, err := cleanRoots(normalized.AllowedWorkdirs)
	if err != nil {
		return nil, err
	}
	templates := map[string]Template{}
	for _, template := range normalized.Templates {
		id := strings.TrimSpace(template.ID)
		if id == "" {
			return nil, fmt.Errorf("command template id is required")
		}
		if strings.TrimSpace(template.Executable) == "" {
			return nil, fmt.Errorf("command template %q executable is required", id)
		}
		templates[id] = template
	}
	if err := os.MkdirAll(filepath.Join(normalized.DataDir, "approvals"), 0o700); err != nil {
		return nil, fmt.Errorf("create approvals directory: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(normalized.DataDir, "jobs"), 0o700); err != nil {
		return nil, fmt.Errorf("create jobs directory: %w", err)
	}
	parserCatalog, err := commandparser.NewCatalog(normalized.ParserDir)
	if err != nil {
		return nil, err
	}
	return &Service{cfg: normalized, roots: roots, templates: templates, parsers: parserCatalog, jobs: map[string]context.CancelFunc{}}, nil
}

// Templates returns sanitized configured command templates in stable order.
func (s *Service) Templates() []TemplateSummary {
	templates := make([]TemplateSummary, 0, len(s.templates))
	for _, template := range s.templates {
		templates = append(templates, s.templateSummary(template))
	}
	sort.Slice(templates, func(i, j int) bool {
		return templates[i].ID < templates[j].ID
	})
	return templates
}

// templateSummary strips executable, arguments, stdin body, and env values from a template.
func (s *Service) templateSummary(template Template) TemplateSummary {
	timeout := template.Timeout
	if timeout <= 0 {
		timeout = s.cfg.DefaultTimeout
	}
	maxOutput := template.MaxOutputBytes
	if maxOutput <= 0 {
		maxOutput = s.cfg.DefaultMaxOutput
	}
	return TemplateSummary{
		ID:                     template.ID,
		Description:            template.Description,
		Parameters:             templateParameters(template),
		ApprovalRequired:       s.cfg.RequireApproval || template.RequireApproval,
		Timeout:                timeout.String(),
		MaxOutputBytes:         maxOutput,
		ParameterSchema:        cloneMap(template.ParameterSchema),
		OutputContract:         template.OutputContract,
		ParserID:               template.ParserID,
		OutputSource:           template.OutputSource,
		ArtifactGlobs:          append([]string(nil), template.ArtifactGlobs...),
		EnvironmentPolicy:      cloneMap(template.EnvironmentPolicy),
		WorkingDirectoryPolicy: template.WorkingDirectoryPolicy,
	}
}

// Request freezes one command proposal and returns its approval id.
func (s *Service) Request(ctx context.Context, req Request) (RequestResult, error) {
	proposal, err := s.resolveRequest(req)
	if err != nil {
		return RequestResult{}, err
	}
	id, err := randomID("approval")
	if err != nil {
		return RequestResult{}, err
	}
	now := time.Now().UTC()
	proposal.ApprovalID = id
	proposal.Status = statusPending
	proposal.CreatedAt = now.Format(time.RFC3339Nano)
	proposal.ExpiresAt = now.Add(s.cfg.ApprovalTTL).Format(time.RFC3339Nano)
	if !proposal.ApprovalRequired {
		proposal.Status = statusApproved
	}
	if err := s.saveApproval(ctx, proposal); err != nil {
		return RequestResult{}, err
	}
	return proposal.requestResult(), nil
}

// Run starts an approved command job asynchronously.
func (s *Service) Run(ctx context.Context, req RunRequest) (RunResult, error) {
	proposal, err := s.loadApproval(ctx, req.ApprovalID)
	if err != nil {
		return RunResult{}, err
	}
	if err := proposal.canRun(); err != nil {
		return RunResult{}, err
	}
	jobID, err := randomID("job")
	if err != nil {
		return RunResult{}, err
	}
	proposal.Status = statusRunning
	if err := s.saveApproval(ctx, proposal); err != nil {
		return RunResult{}, err
	}
	record := jobRecord{
		JobID:      jobID,
		ApprovalID: proposal.ApprovalID,
		Status:     statusRunning,
		ExitCode:   -1,
		StartedAt:  time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err := s.saveJob(ctx, record); err != nil {
		return RunResult{}, err
	}
	runCtx, cancel := context.WithTimeout(context.Background(), proposal.Timeout)
	s.mu.Lock()
	s.jobs[jobID] = cancel
	s.mu.Unlock()
	go s.execute(runCtx, jobID, proposal)
	return RunResult{JobID: jobID, Status: statusRunning}, nil
}

// Execute requests, runs, polls, and returns one completed command result.
func (s *Service) Execute(ctx context.Context, req ExecuteRequest) (StatusResult, error) {
	proposal, err := s.Request(ctx, Request{
		TemplateID: req.TemplateID,
		Parameters: req.Parameters,
		WorkingDir: req.WorkingDir,
		Reason:     req.Reason,
		Actor:      req.Actor,
		SessionID:  req.SessionID,
	})
	if err != nil {
		return StatusResult{}, err
	}
	if proposal.ApprovalRequired {
		return StatusResult{}, fmt.Errorf("command.execute cannot run approval-required command %q", req.TemplateID)
	}
	run, err := s.Run(ctx, RunRequest{ApprovalID: proposal.ApprovalID})
	if err != nil {
		return StatusResult{}, err
	}
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	for {
		status, err := s.Status(ctx, run.JobID)
		if err != nil {
			return StatusResult{}, err
		}
		if status.Status != statusPending && status.Status != statusRunning {
			return status, commandExecuteResultError(status)
		}
		select {
		case <-ctx.Done():
			_, _ = s.Cancel(context.Background(), run.JobID)
			return StatusResult{}, ctx.Err()
		case <-ticker.C:
		}
	}
}

// commandExecuteResultError converts unsuccessful workflow command results into errors.
func commandExecuteResultError(status StatusResult) error {
	if status.Status != statusSucceeded {
		return commandExecuteTerminalError(status)
	}
	if status.Validation.Checked && !status.Validation.Valid {
		return fmt.Errorf("command.execute job %s output validation failed: %s", status.JobID, strings.Join(status.Validation.Errors, "; "))
	}
	for _, diagnostic := range status.Diagnostics {
		if strings.EqualFold(diagnostic.Severity, "error") {
			return fmt.Errorf("command.execute job %s output contract failed: %s", status.JobID, diagnostic.Message)
		}
	}
	return nil
}

// commandExecuteTerminalError converts unsuccessful terminal jobs into workflow errors.
func commandExecuteTerminalError(status StatusResult) error {
	detail := strings.TrimSpace(status.Error)
	if detail == "" && status.ExitCode >= 0 {
		detail = fmt.Sprintf("exit code %d", status.ExitCode)
	}
	if detail == "" {
		detail = fmt.Sprintf("terminal status %s", status.Status)
	}
	return fmt.Errorf("command.execute job %s %s: %s", status.JobID, status.Status, detail)
}

// Approve marks one exact command proposal as externally approved.
func (s *Service) Approve(ctx context.Context, approvalID string) (RequestResult, error) {
	proposal, err := s.loadApproval(ctx, approvalID)
	if err != nil {
		return RequestResult{}, err
	}
	if err := proposal.canApprove(); err != nil {
		return RequestResult{}, err
	}
	proposal.Status = statusApproved
	if err := s.saveApproval(ctx, proposal); err != nil {
		return RequestResult{}, err
	}
	return proposal.requestResult(), nil
}

// Status loads one command job status.
func (s *Service) Status(ctx context.Context, jobID string) (StatusResult, error) {
	record, err := s.loadJob(ctx, jobID)
	if err != nil {
		return StatusResult{}, err
	}
	return record.statusResult(), nil
}

// Cancel requests termination of a running command job.
func (s *Service) Cancel(ctx context.Context, jobID string) (StatusResult, error) {
	id := strings.TrimSpace(jobID)
	s.mu.Lock()
	cancel := s.jobs[id]
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	record, err := s.loadJob(ctx, id)
	if err != nil {
		return StatusResult{}, err
	}
	if record.Status == statusRunning {
		record.Status = statusCanceled
		record.EndedAt = time.Now().UTC().Format(time.RFC3339Nano)
		if err := s.saveJob(ctx, record); err != nil {
			return StatusResult{}, err
		}
	}
	return record.statusResult(), nil
}

// execute runs one frozen command proposal and stores bounded output.
func (s *Service) execute(ctx context.Context, jobID string, proposal approvalRecord) {
	defer func() {
		s.mu.Lock()
		delete(s.jobs, jobID)
		s.mu.Unlock()
	}()
	stdout := newLimitedBuffer(proposal.MaxOutputBytes)
	stderr := newLimitedBuffer(proposal.MaxOutputBytes)
	cmd := exec.CommandContext(ctx, proposal.Executable, proposal.Args...)
	cmd.Dir = proposal.WorkingDir
	cmd.Env = s.environment(proposal.Env)
	cmd.Stdin = strings.NewReader(proposal.Stdin)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	err := cmd.Run()
	record, loadErr := s.loadJob(context.Background(), jobID)
	if loadErr != nil {
		return
	}
	record.StdoutTail = stdout.String()
	record.StderrTail = stderr.String()
	record.Truncated = stdout.Truncated() || stderr.Truncated()
	record.EndedAt = time.Now().UTC().Format(time.RFC3339Nano)
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		record.Status = statusFailed
		record.TimedOut = true
		record.Error = ctx.Err().Error()
	} else if errors.Is(ctx.Err(), context.Canceled) {
		record.Status = statusCanceled
		record.Error = ctx.Err().Error()
	} else if err != nil {
		record.Status = statusFailed
		record.Error = err.Error()
		record.ExitCode = exitCode(err)
	} else {
		record.Status = statusSucceeded
		record.ExitCode = 0
	}
	output, diagnostics, artifacts, validation := s.completedOutput(context.Background(), proposal, record)
	record.Output = output
	record.Diagnostics = diagnostics
	record.Artifacts = artifacts
	record.Validation = validation
	_ = s.saveJob(context.Background(), record)
	proposal.Status = record.Status
	_ = s.saveApproval(context.Background(), proposal)
}

// completedOutput derives structured output, diagnostics, artifacts, and validation.
func (s *Service) completedOutput(ctx context.Context, proposal approvalRecord, record jobRecord) (any, []Diagnostic, []Artifact, ValidationResult) {
	var output any
	var diagnostics []Diagnostic
	if strings.TrimSpace(proposal.ParserID) != "" {
		parsed, err := s.parsers.Parse(ctx, proposal.ParserID, commandparser.Input{
			Stdout:   record.StdoutTail,
			Stderr:   record.StderrTail,
			ExitCode: record.ExitCode,
			Status:   record.Status,
		})
		if err != nil {
			diagnostics = append(diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
		} else {
			output = parsed["output"]
			if output == nil {
				output = parsed
			}
			diagnostics = append(diagnostics, diagnosticsFromAny(parsed["diagnostics"])...)
		}
	} else {
		parsed, err := parseContractOutput(proposal, record)
		if err != nil {
			diagnostics = append(diagnostics, Diagnostic{Severity: "error", Message: err.Error()})
		} else {
			output = parsed
		}
	}
	artifacts, artifactDiagnostics := discoverArtifacts(proposal.WorkingDir, proposal.ArtifactGlobs)
	diagnostics = append(diagnostics, artifactDiagnostics...)
	validation := validateOutput(output, proposal.ValidationSchema)
	for _, message := range validation.Errors {
		diagnostics = append(diagnostics, Diagnostic{Severity: "error", Message: message})
	}
	return output, diagnostics, artifacts, validation
}

// parseContractOutput parses raw output directly when no parser is configured.
func parseContractOutput(proposal approvalRecord, record jobRecord) (any, error) {
	format := normalizeOutputFormat(proposal.OutputContract.Format)
	source := outputText(record, normalizeOutputSource(proposal.OutputSource, proposal.OutputContract))
	switch format {
	case "":
		return nil, nil
	case outputFormatJSON:
		var output any
		if err := json.Unmarshal([]byte(source), &output); err != nil {
			return nil, fmt.Errorf("parse JSON output: %w", err)
		}
		return output, nil
	case outputFormatText, outputFormatPlain:
		return map[string]any{"text": source}, nil
	default:
		return nil, fmt.Errorf("output format %q requires a configured parser", format)
	}
}

// outputText selects a raw output stream for parsing.
func outputText(record jobRecord, source string) string {
	switch source {
	case outputSourceStderr:
		return record.StderrTail
	case outputSourceCombined:
		return strings.TrimSpace(record.StdoutTail + "\n" + record.StderrTail)
	default:
		return record.StdoutTail
	}
}

// diagnosticsFromAny decodes generic parser diagnostics into public diagnostics.
func diagnosticsFromAny(value any) []Diagnostic {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	diagnostics := make([]Diagnostic, 0, len(items))
	for _, item := range items {
		switch typed := item.(type) {
		case string:
			if strings.TrimSpace(typed) != "" {
				diagnostics = append(diagnostics, Diagnostic{Severity: "info", Message: typed})
			}
		case map[string]any:
			message, _ := typed["message"].(string)
			if strings.TrimSpace(message) == "" {
				continue
			}
			severity, _ := typed["severity"].(string)
			diagnostics = append(diagnostics, Diagnostic{Severity: severity, Message: message})
		}
	}
	return diagnostics
}

// resolveRequest normalizes a raw request into one exact command proposal.
func (s *Service) resolveRequest(req Request) (approvalRecord, error) {
	if strings.TrimSpace(req.TemplateID) != "" {
		return s.resolveTemplateRequest(req)
	}
	if !s.cfg.AllowArbitrary {
		return approvalRecord{}, fmt.Errorf("arbitrary commands are disabled")
	}
	return s.resolveArbitraryRequest(req)
}

// resolveTemplateRequest expands one named command template.
func (s *Service) resolveTemplateRequest(req Request) (approvalRecord, error) {
	template, ok := s.templates[strings.TrimSpace(req.TemplateID)]
	if !ok {
		return approvalRecord{}, fmt.Errorf("command template %q not found", req.TemplateID)
	}
	if err := validateTemplateParameters(req.Parameters, template.ParameterSchema); err != nil {
		return approvalRecord{}, err
	}
	args := renderStrings(template.Args, req.Parameters)
	stdin := renderString(template.Stdin, req.Parameters)
	cwd, err := s.safeWorkdir(firstNonEmpty(req.WorkingDir, template.WorkingDir))
	if err != nil {
		return approvalRecord{}, err
	}
	timeout := template.Timeout
	if timeout <= 0 {
		timeout = s.cfg.DefaultTimeout
	}
	maxOutput := template.MaxOutputBytes
	if maxOutput <= 0 {
		maxOutput = s.cfg.DefaultMaxOutput
	}
	return approvalRecord{
		TemplateID:             template.ID,
		ApprovalRequired:       s.cfg.RequireApproval || template.RequireApproval,
		Executable:             template.Executable,
		Args:                   args,
		Stdin:                  stdin,
		WorkingDir:             cwd,
		Env:                    template.Env,
		Timeout:                timeout,
		MaxOutputBytes:         maxOutput,
		ParameterSchema:        cloneMap(template.ParameterSchema),
		OutputContract:         template.OutputContract,
		ParserID:               template.ParserID,
		OutputSource:           template.OutputSource,
		ArtifactGlobs:          append([]string(nil), template.ArtifactGlobs...),
		EnvironmentPolicy:      cloneMap(template.EnvironmentPolicy),
		WorkingDirectoryPolicy: template.WorkingDirectoryPolicy,
		ValidationSchema:       cloneMap(template.ValidationSchema),
		Reason:                 req.Reason,
		Risk:                   req.Risk,
		Actor:                  req.Actor,
		SessionID:              req.SessionID,
	}, nil
}

// validateTemplateParameters enforces a template's input schema before rendering.
func validateTemplateParameters(parameters map[string]any, schema map[string]any) error {
	if len(schema) == 0 {
		return nil
	}
	if parameters == nil {
		parameters = map[string]any{}
	}
	result := validateOutput(parameters, schema)
	if result.Valid {
		return nil
	}
	return fmt.Errorf("template parameters invalid: %s", strings.Join(result.Errors, "; "))
}

// resolveArbitraryRequest normalizes one arbitrary command request.
func (s *Service) resolveArbitraryRequest(req Request) (approvalRecord, error) {
	if strings.TrimSpace(req.Executable) == "" {
		return approvalRecord{}, fmt.Errorf("command executable is required")
	}
	cwd, err := s.safeWorkdir(req.WorkingDir)
	if err != nil {
		return approvalRecord{}, err
	}
	return approvalRecord{
		ApprovalRequired: true,
		Executable:       strings.TrimSpace(req.Executable),
		Args:             append([]string(nil), req.Args...),
		Stdin:            req.Stdin,
		WorkingDir:       cwd,
		Env:              req.Env,
		Timeout:          s.cfg.DefaultTimeout,
		MaxOutputBytes:   s.cfg.DefaultMaxOutput,
		Reason:           req.Reason,
		Risk:             req.Risk,
		Actor:            req.Actor,
		SessionID:        req.SessionID,
	}, nil
}

// safeWorkdir resolves and validates a requested working directory.
func (s *Service) safeWorkdir(value string) (string, error) {
	cwd := strings.TrimSpace(value)
	if cwd == "" {
		cwd = s.roots[0]
	}
	abs, err := filepath.Abs(cwd)
	if err != nil {
		return "", fmt.Errorf("resolve cwd: %w", err)
	}
	clean := filepath.Clean(abs)
	for _, root := range s.roots {
		rel, err := filepath.Rel(root, clean)
		if err == nil && (rel == "." || (!strings.HasPrefix(rel, ".."+string(os.PathSeparator)) && rel != "..")) {
			return clean, nil
		}
	}
	return "", fmt.Errorf("cwd %q is outside allowed roots", clean)
}

// environment returns the allowlisted process environment plus configured values.
func (s *Service) environment(extra map[string]string) []string {
	seen := map[string]string{}
	for _, name := range s.cfg.AllowedEnv {
		if value, ok := os.LookupEnv(name); ok {
			seen[name] = value
		}
	}
	for name, value := range extra {
		if containsString(s.cfg.AllowedEnv, name) {
			seen[name] = value
		}
	}
	names := make([]string, 0, len(seen))
	for name := range seen {
		names = append(names, name)
	}
	sort.Strings(names)
	env := make([]string, 0, len(names))
	for _, name := range names {
		env = append(env, name+"="+seen[name])
	}
	return env
}

// saveApproval writes one proposal record to durable disk.
func (s *Service) saveApproval(ctx context.Context, record approvalRecord) error {
	path, err := s.approvalPath(record.ApprovalID)
	if err != nil {
		return err
	}
	return writeJSONFile(ctx, path, record)
}

// loadApproval reads one proposal record from durable disk.
func (s *Service) loadApproval(ctx context.Context, approvalID string) (approvalRecord, error) {
	var record approvalRecord
	path, err := s.approvalPath(approvalID)
	if err != nil {
		return approvalRecord{}, err
	}
	if err := readJSONFile(ctx, path, &record); err != nil {
		return approvalRecord{}, err
	}
	return record, nil
}

// saveJob writes one job record to durable disk.
func (s *Service) saveJob(ctx context.Context, record jobRecord) error {
	path, err := s.jobPath(record.JobID)
	if err != nil {
		return err
	}
	return writeJSONFile(ctx, path, record)
}

// loadJob reads one job record from durable disk.
func (s *Service) loadJob(ctx context.Context, jobID string) (jobRecord, error) {
	var record jobRecord
	path, err := s.jobPath(jobID)
	if err != nil {
		return jobRecord{}, err
	}
	if err := readJSONFile(ctx, path, &record); err != nil {
		return jobRecord{}, err
	}
	return record, nil
}

// approvalPath returns the private record path for one validated approval id.
func (s *Service) approvalPath(approvalID string) (string, error) {
	id, err := validateRecordID(approvalID, "approval id")
	if err != nil {
		return "", err
	}
	return filepath.Join(s.cfg.DataDir, "approvals", id+".json"), nil
}

// jobPath returns the private record path for one validated job id.
func (s *Service) jobPath(jobID string) (string, error) {
	id, err := validateRecordID(jobID, "job id")
	if err != nil {
		return "", err
	}
	return filepath.Join(s.cfg.DataDir, "jobs", id+".json"), nil
}

// approvalRecord stores one frozen command approval proposal.
type approvalRecord struct {
	ApprovalID             string            `json:"approval_id"`
	TemplateID             string            `json:"template_id,omitempty"`
	Status                 string            `json:"status"`
	ApprovalRequired       bool              `json:"approval_required"`
	Executable             string            `json:"executable"`
	Args                   []string          `json:"args"`
	Stdin                  string            `json:"stdin,omitempty"`
	WorkingDir             string            `json:"cwd"`
	Env                    map[string]string `json:"env,omitempty"`
	Timeout                time.Duration     `json:"timeout"`
	MaxOutputBytes         int64             `json:"max_output_bytes"`
	ParameterSchema        map[string]any    `json:"parameter_schema,omitempty"`
	Reason                 string            `json:"reason,omitempty"`
	Risk                   string            `json:"risk,omitempty"`
	Actor                  string            `json:"actor,omitempty"`
	SessionID              string            `json:"session_id,omitempty"`
	CreatedAt              string            `json:"created_at"`
	ExpiresAt              string            `json:"expires_at"`
	OutputContract         OutputContract    `json:"output_contract,omitempty"`
	ParserID               string            `json:"parser_id,omitempty"`
	OutputSource           string            `json:"output_source,omitempty"`
	ArtifactGlobs          []string          `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any    `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string            `json:"working_directory_policy,omitempty"`
	ValidationSchema       map[string]any    `json:"validation_schema,omitempty"`
}

// requestResult returns the public approval proposal shape.
func (r approvalRecord) requestResult() RequestResult {
	return RequestResult{
		ApprovalID:       r.ApprovalID,
		ApprovalRequired: r.ApprovalRequired,
		Status:           r.Status,
		Summary:          commandSummary(r.Executable, r.Args),
		Executable:       r.Executable,
		Args:             append([]string(nil), r.Args...),
		WorkingDir:       r.WorkingDir,
		ExpiresAt:        r.ExpiresAt,
		EnvNames:         sortedMapKeys(r.Env),
		HasStdin:         strings.TrimSpace(r.Stdin) != "",
	}
}

// canApprove validates whether an approval record can receive an external grant.
func (r approvalRecord) canApprove() error {
	expires, err := time.Parse(time.RFC3339Nano, r.ExpiresAt)
	if err != nil {
		return fmt.Errorf("approval expiry is invalid: %w", err)
	}
	if time.Now().UTC().After(expires) {
		return fmt.Errorf("approval %s expired", r.ApprovalID)
	}
	if r.Status == statusApproved {
		return nil
	}
	if r.Status != statusPending {
		return fmt.Errorf("approval %s cannot be approved from status %q", r.ApprovalID, r.Status)
	}
	return nil
}

// canRun validates whether an approval record may start a job.
func (r approvalRecord) canRun() error {
	expires, err := time.Parse(time.RFC3339Nano, r.ExpiresAt)
	if err != nil {
		return fmt.Errorf("approval expiry is invalid: %w", err)
	}
	if time.Now().UTC().After(expires) {
		return fmt.Errorf("approval %s expired", r.ApprovalID)
	}
	if r.Status != statusApproved {
		if r.ApprovalRequired {
			return fmt.Errorf("approval %s requires external approval", r.ApprovalID)
		}
		return fmt.Errorf("approval %s cannot run from status %q", r.ApprovalID, r.Status)
	}
	return nil
}

// jobRecord stores durable process execution status.
type jobRecord struct {
	JobID       string           `json:"job_id"`
	ApprovalID  string           `json:"approval_id"`
	Status      string           `json:"status"`
	ExitCode    int              `json:"exit_code"`
	StdoutTail  string           `json:"stdout_tail"`
	StderrTail  string           `json:"stderr_tail"`
	Truncated   bool             `json:"truncated"`
	TimedOut    bool             `json:"timed_out"`
	Error       string           `json:"error,omitempty"`
	StartedAt   string           `json:"started_at"`
	EndedAt     string           `json:"ended_at,omitempty"`
	Output      any              `json:"output,omitempty"`
	Diagnostics []Diagnostic     `json:"diagnostics,omitempty"`
	Artifacts   []Artifact       `json:"artifacts,omitempty"`
	Validation  ValidationResult `json:"validation,omitempty"`
}

// statusResult returns the public job status shape.
func (r jobRecord) statusResult() StatusResult {
	return StatusResult{
		JobID:       r.JobID,
		Status:      r.Status,
		ExitCode:    r.ExitCode,
		StdoutTail:  r.StdoutTail,
		StderrTail:  r.StderrTail,
		Truncated:   r.Truncated,
		TimedOut:    r.TimedOut,
		Error:       r.Error,
		StartedAt:   r.StartedAt,
		EndedAt:     r.EndedAt,
		Output:      r.Output,
		Diagnostics: append([]Diagnostic(nil), r.Diagnostics...),
		Artifacts:   append([]Artifact(nil), r.Artifacts...),
		Validation:  r.Validation,
	}
}

// limitedBuffer stores only the most recent output bytes.
type limitedBuffer struct {
	limit     int64
	data      []byte
	truncated bool
}

// newLimitedBuffer creates a bounded output collector.
func newLimitedBuffer(limit int64) *limitedBuffer {
	if limit <= 0 {
		limit = 64 << 10
	}
	return &limitedBuffer{limit: limit}
}

// Write appends process output while retaining only a bounded tail.
func (b *limitedBuffer) Write(p []byte) (int, error) {
	b.data = append(b.data, p...)
	if int64(len(b.data)) > b.limit {
		b.truncated = true
		b.data = b.data[int64(len(b.data))-b.limit:]
	}
	return len(p), nil
}

// String returns the retained output tail.
func (b *limitedBuffer) String() string {
	return string(bytes.TrimSpace(b.data))
}

// Truncated reports whether earlier output was discarded.
func (b *limitedBuffer) Truncated() bool {
	return b.truncated
}

// normalizeConfig fills conservative runtime defaults.
func normalizeConfig(cfg Config) (Config, error) {
	if strings.TrimSpace(cfg.DataDir) == "" {
		return Config{}, fmt.Errorf("command data directory is required")
	}
	if cfg.DefaultTimeout <= 0 {
		cfg.DefaultTimeout = 10 * time.Minute
	}
	if cfg.DefaultMaxOutput <= 0 {
		cfg.DefaultMaxOutput = 64 << 10
	}
	if cfg.ApprovalTTL <= 0 {
		cfg.ApprovalTTL = 10 * time.Minute
	}
	if len(cfg.AllowedWorkdirs) == 0 {
		cfg.AllowedWorkdirs = []string{"."}
	}
	if len(cfg.AllowedEnv) == 0 {
		cfg.AllowedEnv = []string{"PATH", "HOME", "USER", "TMPDIR"}
	}
	if strings.TrimSpace(cfg.ParserDir) == "" {
		cfg.ParserDir = defaultParserDir()
	}
	return cfg, nil
}

// defaultParserDir returns the OS-local command parser catalog path.
func defaultParserDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return filepath.Join(".", "agent-awesome", "command", "parsers")
	}
	return filepath.Join(configDir, "agent-awesome", "command", "parsers")
}

// cleanRoots resolves configured allowed working directory roots.
func cleanRoots(values []string) ([]string, error) {
	roots := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		abs, err := filepath.Abs(trimmed)
		if err != nil {
			return nil, fmt.Errorf("resolve allowed workdir %q: %w", value, err)
		}
		roots = append(roots, filepath.Clean(abs))
	}
	if len(roots) == 0 {
		return nil, fmt.Errorf("at least one allowed workdir is required")
	}
	return roots, nil
}

// renderStrings expands simple {{name}} placeholders in a string list.
func renderStrings(values []string, params map[string]any) []string {
	next := make([]string, len(values))
	for index, value := range values {
		next[index] = renderString(value, params)
	}
	return next
}

// renderString expands simple {{name}} placeholders in one value.
func renderString(value string, params map[string]any) string {
	rendered := value
	for key, replacement := range params {
		rendered = strings.ReplaceAll(rendered, "{{"+key+"}}", fmt.Sprint(replacement))
	}
	return rendered
}

// writeJSONFile writes one private JSON record atomically enough for local service state.
func writeJSONFile(ctx context.Context, path string, value any) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("encode %s: %w", path, err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// readJSONFile reads one private JSON record.
func readJSONFile(ctx context.Context, path string, target any) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

// randomID creates a prefixed random hex id.
func randomID(prefix string) (string, error) {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", fmt.Errorf("create %s id: %w", prefix, err)
	}
	return prefix + "_" + hex.EncodeToString(bytes[:]), nil
}

// validateRecordID rejects path traversal and malformed durable ids.
func validateRecordID(value string, label string) (string, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return "", fmt.Errorf("%s is required", label)
	}
	if !safeIDPattern.MatchString(trimmed) {
		return "", fmt.Errorf("%s %q is invalid", label, trimmed)
	}
	return trimmed, nil
}

// templateParameters returns placeholder names used by editable template fields.
func templateParameters(template Template) []string {
	seen := map[string]struct{}{}
	values := append([]string{}, template.Args...)
	values = append(values, template.Stdin, template.WorkingDir)
	for _, value := range values {
		for _, match := range templateParameterPattern.FindAllStringSubmatch(value, -1) {
			seen[match[1]] = struct{}{}
		}
	}
	names := make([]string, 0, len(seen))
	for name := range seen {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// sortedMapKeys returns stable public key names without exposing map values.
func sortedMapKeys(values map[string]string) []string {
	names := make([]string, 0, len(values))
	for name := range values {
		if strings.TrimSpace(name) != "" {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names
}

// commandSummary returns a human-readable command summary.
func commandSummary(executable string, args []string) string {
	parts := append([]string{executable}, args...)
	return strings.Join(parts, " ")
}

// firstNonEmpty returns the first non-empty string.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

// containsString reports whether a string list contains one value.
func containsString(values []string, needle string) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

// discoverArtifacts expands configured globs inside the command working directory.
func discoverArtifacts(workdir string, globs []string) ([]Artifact, []Diagnostic) {
	var artifacts []Artifact
	var diagnostics []Diagnostic
	for _, pattern := range globs {
		trimmed := strings.TrimSpace(pattern)
		if trimmed == "" {
			continue
		}
		if !filepath.IsAbs(trimmed) {
			trimmed = filepath.Join(workdir, trimmed)
		}
		matches, err := filepath.Glob(trimmed)
		if err != nil {
			diagnostics = append(diagnostics, Diagnostic{Severity: "error", Message: fmt.Sprintf("artifact glob %q: %v", pattern, err)})
			continue
		}
		for _, match := range matches {
			clean := filepath.Clean(match)
			rel, err := filepath.Rel(workdir, clean)
			if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
				diagnostics = append(diagnostics, Diagnostic{Severity: "error", Message: fmt.Sprintf("artifact %q is outside working directory", clean)})
				continue
			}
			info, err := os.Stat(clean)
			if err != nil || info.IsDir() {
				continue
			}
			artifacts = append(artifacts, Artifact{Path: filepath.ToSlash(rel), Size: info.Size()})
		}
	}
	sort.Slice(artifacts, func(i, j int) bool {
		return artifacts[i].Path < artifacts[j].Path
	})
	return artifacts, diagnostics
}

// cloneMap copies JSON-like template metadata.
func cloneMap(value map[string]any) map[string]any {
	if value == nil {
		return nil
	}
	next := make(map[string]any, len(value))
	for key, item := range value {
		next[key] = item
	}
	return next
}

// exitCode extracts a process exit code when available.
func exitCode(err error) int {
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}
