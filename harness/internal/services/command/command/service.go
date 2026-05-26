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
	"time"

	commandparser "agentawesome/internal/services/command/parser"
)

const (
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
	ParameterSchema        map[string]any    `json:"parameter_schema,omitempty"`
	OutputContract         OutputContract    `json:"output_contract,omitempty"`
	ParserID               string            `json:"parser_id,omitempty"`
	OutputSource           string            `json:"output_source,omitempty"`
	ArtifactGlobs          []string          `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any    `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string            `json:"working_directory_policy,omitempty"`
	ValidationSchema       map[string]any    `json:"validation_schema,omitempty"`
	Surface                CommandSurface    `json:"surface,omitempty"`
	Annotations            map[string]any    `json:"annotations,omitempty"`
}

// TemplateSummary describes a configured command template without secret-bearing fields.
type TemplateSummary struct {
	ID                     string         `json:"id"`
	Description            string         `json:"description"`
	Parameters             []string       `json:"parameters,omitempty"`
	Timeout                string         `json:"timeout,omitempty"`
	MaxOutputBytes         int64          `json:"max_output_bytes,omitempty"`
	ParameterSchema        map[string]any `json:"parameter_schema,omitempty"`
	OutputContract         OutputContract `json:"output_contract,omitempty"`
	ParserID               string         `json:"parser_id,omitempty"`
	OutputSource           string         `json:"output_source,omitempty"`
	ArtifactGlobs          []string       `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string         `json:"working_directory_policy,omitempty"`
	Surface                CommandSurface `json:"surface,omitempty"`
	Annotations            map[string]any `json:"annotations,omitempty"`
}

// CommandSurface documents the model-facing CLI command surface.
type CommandSurface struct {
	GlobalFlags []CommandFlag       `json:"global_flags,omitempty"`
	Subcommands []CommandSubcommand `json:"subcommands,omitempty"`
}

// CommandFlag documents one supported CLI flag.
type CommandFlag struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
}

// CommandSubcommand documents one supported CLI subcommand.
type CommandSubcommand struct {
	Name        string              `json:"name"`
	Description string              `json:"description,omitempty"`
	Flags       []CommandFlag       `json:"flags,omitempty"`
	Subcommands []CommandSubcommand `json:"subcommands,omitempty"`
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

// Service validates configured command templates and records job results.
type Service struct {
	cfg       Config
	roots     []string
	templates map[string]Template
	parsers   *commandparser.Catalog
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
		if _, exists := templates[id]; exists {
			return nil, fmt.Errorf("command template %q is duplicated", id)
		}
		templates[id] = template
	}
	if err := os.MkdirAll(filepath.Join(normalized.DataDir, "jobs"), 0o700); err != nil {
		return nil, fmt.Errorf("create jobs directory: %w", err)
	}
	parserCatalog, err := commandparser.NewCatalog(normalized.ParserDir)
	if err != nil {
		return nil, err
	}
	return &Service{cfg: normalized, roots: roots, templates: templates, parsers: parserCatalog}, nil
}

// Close releases command service resources.
func (s *Service) Close() {
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
		Timeout:                timeout.String(),
		MaxOutputBytes:         maxOutput,
		ParameterSchema:        cloneMap(template.ParameterSchema),
		OutputContract:         template.OutputContract,
		ParserID:               template.ParserID,
		OutputSource:           template.OutputSource,
		ArtifactGlobs:          append([]string(nil), template.ArtifactGlobs...),
		EnvironmentPolicy:      cloneMap(template.EnvironmentPolicy),
		WorkingDirectoryPolicy: template.WorkingDirectoryPolicy,
		Surface:                cloneCommandSurface(template.Surface),
		Annotations:            cloneMap(template.Annotations),
	}
}

// Execute runs one configured command template and returns its completed result.
func (s *Service) Execute(ctx context.Context, req ExecuteRequest) (StatusResult, error) {
	proposal, err := s.resolveTemplateRequest(req)
	if err != nil {
		return StatusResult{}, err
	}
	jobID, err := randomID("job")
	if err != nil {
		return StatusResult{}, err
	}
	record := jobRecord{
		JobID:     jobID,
		Status:    statusRunning,
		ExitCode:  -1,
		StartedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err := s.saveJob(ctx, record); err != nil {
		return StatusResult{}, err
	}
	runCtx, cancel := context.WithTimeout(ctx, proposal.Timeout)
	defer cancel()
	status := s.execute(runCtx, jobID, proposal)
	return status, commandExecuteResultError(status)
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

// Status loads one command job status.
func (s *Service) Status(ctx context.Context, jobID string) (StatusResult, error) {
	record, err := s.loadJob(ctx, jobID)
	if err != nil {
		return StatusResult{}, err
	}
	return record.statusResult(), nil
}

// execute runs one frozen command proposal and stores bounded output.
func (s *Service) execute(ctx context.Context, jobID string, proposal commandRecord) StatusResult {
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
		return StatusResult{JobID: jobID, Status: statusFailed, ExitCode: -1, Error: loadErr.Error()}
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
	return record.statusResult()
}

// completedOutput derives structured output, diagnostics, artifacts, and validation.
func (s *Service) completedOutput(ctx context.Context, proposal commandRecord, record jobRecord) (any, []Diagnostic, []Artifact, ValidationResult) {
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
func parseContractOutput(proposal commandRecord, record jobRecord) (any, error) {
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

// resolveTemplateRequest expands one named command template.
func (s *Service) resolveTemplateRequest(req ExecuteRequest) (commandRecord, error) {
	template, ok := s.templates[strings.TrimSpace(req.TemplateID)]
	if !ok {
		return commandRecord{}, fmt.Errorf("command template %q not found", req.TemplateID)
	}
	if err := validateTemplateParameters(req.Parameters, template.ParameterSchema); err != nil {
		return commandRecord{}, err
	}
	executable := strings.TrimSpace(renderString(template.Executable, req.Parameters))
	if executable == "" {
		return commandRecord{}, fmt.Errorf("command template %q executable resolved empty", template.ID)
	}
	args := renderStrings(template.Args, req.Parameters)
	stdin := renderString(template.Stdin, req.Parameters)
	env := renderStringMap(template.Env, req.Parameters)
	cwd, err := s.safeWorkdir(firstNonEmpty(req.WorkingDir, template.WorkingDir))
	if err != nil {
		return commandRecord{}, err
	}
	timeout := template.Timeout
	if timeout <= 0 {
		timeout = s.cfg.DefaultTimeout
	}
	maxOutput := template.MaxOutputBytes
	if maxOutput <= 0 {
		maxOutput = s.cfg.DefaultMaxOutput
	}
	return commandRecord{
		TemplateID:             template.ID,
		Executable:             executable,
		Args:                   args,
		Stdin:                  stdin,
		WorkingDir:             cwd,
		Env:                    env,
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
	clean, err := filepath.EvalSymlinks(filepath.Clean(abs))
	if err != nil {
		return "", fmt.Errorf("resolve cwd %q: %w", cwd, err)
	}
	clean = filepath.Clean(clean)
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

// jobPath returns the private record path for one validated job id.
func (s *Service) jobPath(jobID string) (string, error) {
	id, err := validateRecordID(jobID, "job id")
	if err != nil {
		return "", err
	}
	return filepath.Join(s.cfg.DataDir, "jobs", id+".json"), nil
}

// commandRecord stores one resolved configured command execution.
type commandRecord struct {
	TemplateID             string            `json:"template_id,omitempty"`
	Executable             string            `json:"executable"`
	Args                   []string          `json:"args"`
	Stdin                  string            `json:"stdin,omitempty"`
	WorkingDir             string            `json:"cwd"`
	Env                    map[string]string `json:"env,omitempty"`
	Timeout                time.Duration     `json:"timeout"`
	MaxOutputBytes         int64             `json:"max_output_bytes"`
	ParameterSchema        map[string]any    `json:"parameter_schema,omitempty"`
	Reason                 string            `json:"reason,omitempty"`
	Actor                  string            `json:"actor,omitempty"`
	SessionID              string            `json:"session_id,omitempty"`
	OutputContract         OutputContract    `json:"output_contract,omitempty"`
	ParserID               string            `json:"parser_id,omitempty"`
	OutputSource           string            `json:"output_source,omitempty"`
	ArtifactGlobs          []string          `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any    `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string            `json:"working_directory_policy,omitempty"`
	ValidationSchema       map[string]any    `json:"validation_schema,omitempty"`
}

// jobRecord stores durable process execution status.
type jobRecord struct {
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
		canonical, err := filepath.EvalSymlinks(filepath.Clean(abs))
		if err != nil {
			return nil, fmt.Errorf("resolve allowed workdir %q: %w", value, err)
		}
		roots = append(roots, filepath.Clean(canonical))
	}
	if len(roots) == 0 {
		return nil, fmt.Errorf("at least one allowed workdir is required")
	}
	return roots, nil
}

// renderStrings expands simple {{name}} placeholders in a string list.
func renderStrings(values []string, params map[string]any) []string {
	next := make([]string, 0, len(values))
	for _, value := range values {
		if name, ok := wholeTemplateParameter(value); ok {
			if expanded, ok := stringListParam(params[name]); ok {
				next = append(next, expanded...)
				continue
			}
		}
		next = append(next, renderString(value, params))
	}
	return next
}

// wholeTemplateParameter returns the name when a value is exactly one placeholder.
func wholeTemplateParameter(value string) (string, bool) {
	trimmed := strings.TrimSpace(value)
	matches := templateParameterPattern.FindStringSubmatch(trimmed)
	if len(matches) != 2 || matches[0] != trimmed {
		return "", false
	}
	return matches[1], true
}

// stringListParam converts a parameter value into command argument strings.
func stringListParam(value any) ([]string, bool) {
	switch typed := value.(type) {
	case []string:
		return append([]string(nil), typed...), true
	case []any:
		values := make([]string, 0, len(typed))
		for _, item := range typed {
			values = append(values, fmt.Sprint(item))
		}
		return values, true
	default:
		return nil, false
	}
}

// renderStringMap expands simple {{name}} placeholders in a string map.
func renderStringMap(values map[string]string, params map[string]any) map[string]string {
	if len(values) == 0 {
		return nil
	}
	next := make(map[string]string, len(values))
	for key, value := range values {
		next[key] = renderString(value, params)
	}
	return next
}

// renderString expands simple {{name}} placeholders in one value.
func renderString(value string, params map[string]any) string {
	return templateParameterPattern.ReplaceAllStringFunc(value, func(match string) string {
		parts := templateParameterPattern.FindStringSubmatch(match)
		if len(parts) != 2 {
			return match
		}
		replacement, ok := params[parts[1]]
		if !ok {
			return match
		}
		return fmt.Sprint(replacement)
	})
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
	values := []string{template.Executable}
	values = append(values, template.Args...)
	values = append(values, template.Stdin, template.WorkingDir)
	for _, value := range template.Env {
		values = append(values, value)
	}
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

// cloneCommandSurface returns a detached copy of CLI surface documentation.
func cloneCommandSurface(surface CommandSurface) CommandSurface {
	globalFlags := make([]CommandFlag, len(surface.GlobalFlags))
	copy(globalFlags, surface.GlobalFlags)
	subcommands := cloneCommandSubcommands(surface.Subcommands)
	return CommandSurface{GlobalFlags: globalFlags, Subcommands: subcommands}
}

// cloneCommandSubcommands returns detached recursive CLI subcommand metadata.
func cloneCommandSubcommands(values []CommandSubcommand) []CommandSubcommand {
	subcommands := make([]CommandSubcommand, len(values))
	for index, subcommand := range values {
		subcommands[index] = CommandSubcommand{
			Name:        subcommand.Name,
			Description: subcommand.Description,
			Flags:       append([]CommandFlag(nil), subcommand.Flags...),
			Subcommands: cloneCommandSubcommands(subcommand.Subcommands),
		}
	}
	return subcommands
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
