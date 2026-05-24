// This file defines dumb Operations data models and service requests.
package operations

const (
	// OperationRunQueueStatusQueued means a target may lease the queued run.
	OperationRunQueueStatusQueued = "queued"
	// OperationRunQueueStatusLeased means a target has leased but not started it.
	OperationRunQueueStatusLeased = "leased"
	// OperationRunQueueStatusRunning means a target started the workflow run.
	OperationRunQueueStatusRunning = "running"
	// OperationRunQueueStatusCompleted means the queued run finished successfully.
	OperationRunQueueStatusCompleted = "completed"
	// OperationRunQueueStatusFailed means the queued run exhausted or reported failure.
	OperationRunQueueStatusFailed = "failed"
	// OperationRunQueueStatusCanceled means the queued run was canceled before completion.
	OperationRunQueueStatusCanceled = "canceled"
)

// Operation stores one reusable workflow binding.
type Operation struct {
	ID              string                   `json:"id"`
	Name            string                   `json:"name"`
	WorkflowID      string                   `json:"workflow_id"`
	WorkflowVersion string                   `json:"workflow_version,omitempty"`
	CodebaseID      string                   `json:"codebase_id,omitempty"`
	RuntimeTargetID string                   `json:"runtime_target_id,omitempty"`
	AgentProfileID  string                   `json:"agent_profile_id,omitempty"`
	Defaults        map[string]any           `json:"defaults,omitempty"`
	Policy          OperationPolicy          `json:"policy"`
	Schedule        OperationSchedule        `json:"schedule,omitempty"`
	SecretRefs      []OperationSecretBinding `json:"secret_refs,omitempty"`
	Status          string                   `json:"status"`
	Version         int                      `json:"version"`
	CreatedAt       string                   `json:"created_at,omitempty"`
	UpdatedAt       string                   `json:"updated_at,omitempty"`
}

// OperationVersion stores immutable operation version metadata.
type OperationVersion struct {
	OperationID string `json:"operation_id"`
	Version     int    `json:"version"`
	Hash        string `json:"hash"`
	CreatedAt   string `json:"created_at"`
}

// OperationPolicy stores user-facing safety policy.
type OperationPolicy struct {
	AllowedTargets        []string `json:"allowed_targets,omitempty"`
	AllowedTools          []string `json:"allowed_tools,omitempty"`
	AllowedMCPServers     []string `json:"allowed_mcp_servers,omitempty"`
	AllowedAgents         []string `json:"allowed_agents,omitempty"`
	AllowedFolders        []string `json:"allowed_folders,omitempty"`
	AllowedCodebases      []string `json:"allowed_codebases,omitempty"`
	AllowedNetworkDomains []string `json:"allowed_network_domains,omitempty"`
	AllowedSecretRefs     []string `json:"allowed_secret_refs,omitempty"`
	ApprovalRequired      bool     `json:"approval_required,omitempty"`
	DestructiveAction     string   `json:"destructive_action,omitempty"`
	MaxRuntimeSeconds     int      `json:"max_runtime_seconds,omitempty"`
	MaxParallelism        int      `json:"max_parallelism,omitempty"`
	RetryLimit            int      `json:"retry_limit,omitempty"`
	SpendingLimitCents    int      `json:"spending_limit_cents,omitempty"`
	SourceControl         string   `json:"source_control,omitempty"`
}

// OperationTarget stores the runtime target binding.
type OperationTarget struct {
	RuntimeTargetID string `json:"runtime_target_id,omitempty"`
	AgentProfileID  string `json:"agent_profile_id,omitempty"`
}

// OperationSchedule stores recurring start metadata.
type OperationSchedule struct {
	Enabled         bool   `json:"enabled,omitempty"`
	Cron            string `json:"cron,omitempty"`
	QuietHoursStart string `json:"quiet_hours_start,omitempty"`
	QuietHoursEnd   string `json:"quiet_hours_end,omitempty"`
	StopAt          string `json:"stop_at,omitempty"`
	MaxRuns         int    `json:"max_runs,omitempty"`
}

// OperationSecretBinding stores one secret reference binding.
type OperationSecretBinding struct {
	Name string `json:"name"`
	Ref  string `json:"ref"`
}

// OperationRunLink links one Operation start to a workflow run.
type OperationRunLink struct {
	OperationID string `json:"operation_id"`
	RunID       string `json:"run_id"`
	CreatedAt   string `json:"created_at"`
}

// OperationRunSnapshot stores immutable run-start audit data.
type OperationRunSnapshot struct {
	RunID            string                   `json:"run_id"`
	OperationID      string                   `json:"operation_id"`
	OperationVersion int                      `json:"operation_version"`
	WorkflowID       string                   `json:"workflow_id"`
	WorkflowVersion  string                   `json:"workflow_version,omitempty"`
	ResolvedInput    map[string]any           `json:"resolved_input"`
	Resolution       map[string]any           `json:"resolution"`
	Target           OperationTarget          `json:"target"`
	Policy           OperationPolicy          `json:"policy"`
	SecretRefs       []OperationSecretBinding `json:"secret_refs,omitempty"`
	CreatedAt        string                   `json:"created_at"`
}

// Codebase stores the catalog fields Operations needs from memory.
type Codebase struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Aliases            []string `json:"aliases,omitempty"`
	RepositoryPath     string   `json:"repository_path,omitempty"`
	DefaultRemote      string   `json:"default_remote,omitempty"`
	DefaultBranch      string   `json:"default_branch,omitempty"`
	Provider           string   `json:"provider,omitempty"`
	ProviderRepository string   `json:"provider_repository,omitempty"`
	GoModulePath       string   `json:"go_module_path,omitempty"`
	RuntimeTargetID    string   `json:"runtime_target_id,omitempty"`
	AgentProfileID     string   `json:"agent_profile_id,omitempty"`
}

// CodebaseResolution stores one memory-backed codebase lookup result.
type CodebaseResolution struct {
	Status      string          `json:"status"`
	Codebase    *Codebase       `json:"codebase,omitempty"`
	Matches     []CodebaseMatch `json:"matches,omitempty"`
	Diagnostics []string        `json:"diagnostics,omitempty"`
}

// CodebaseMatch stores one codebase resolution candidate.
type CodebaseMatch struct {
	Codebase   Codebase `json:"codebase"`
	Confidence float64  `json:"confidence"`
	Reason     string   `json:"reason,omitempty"`
}

// OperationRequest carries create and update payloads.
type OperationRequest struct {
	ID              string                   `json:"id"`
	Name            string                   `json:"name"`
	WorkflowID      string                   `json:"workflow_id"`
	WorkflowVersion string                   `json:"workflow_version,omitempty"`
	CodebaseID      string                   `json:"codebase_id,omitempty"`
	RuntimeTargetID string                   `json:"runtime_target_id,omitempty"`
	AgentProfileID  string                   `json:"agent_profile_id,omitempty"`
	Defaults        map[string]any           `json:"defaults,omitempty"`
	Policy          OperationPolicy          `json:"policy,omitempty"`
	Schedule        OperationSchedule        `json:"schedule,omitempty"`
	SecretRefs      []OperationSecretBinding `json:"secret_refs,omitempty"`
	Status          string                   `json:"status,omitempty"`
}

// OperationQuery selects Operations for listing.
type OperationQuery struct {
	WorkflowID string `json:"workflow_id,omitempty"`
	CodebaseID string `json:"codebase_id,omitempty"`
	Status     string `json:"status,omitempty"`
}

// OperationRunRequest carries one preview or start request.
type OperationRunRequest struct {
	OperationID  string         `json:"operation_id,omitempty"`
	Input        map[string]any `json:"input,omitempty"`
	CodebaseName string         `json:"codebase_name,omitempty"`
	Source       string         `json:"source,omitempty"`
	Task         map[string]any `json:"task,omitempty"`
}

// OperationRunQueueItem stores one durable queued Operation run request.
type OperationRunQueueItem struct {
	ID               string                   `json:"id"`
	OperationID      string                   `json:"operation_id"`
	OperationVersion int                      `json:"operation_version"`
	OperationHash    string                   `json:"operation_hash"`
	WorkflowID       string                   `json:"workflow_id"`
	WorkflowVersion  string                   `json:"workflow_version,omitempty"`
	Target           OperationTarget          `json:"target"`
	Policy           OperationPolicy          `json:"policy"`
	PolicyDecision   OperationPolicyDecision  `json:"policy_decision"`
	SecretRefs       []OperationSecretBinding `json:"secret_refs,omitempty"`
	ResolvedInput    map[string]any           `json:"resolved_input"`
	Resolution       map[string]any           `json:"resolution"`
	RequestInput     map[string]any           `json:"request_input,omitempty"`
	Source           string                   `json:"source,omitempty"`
	Status           string                   `json:"status"`
	Attempts         int                      `json:"attempts"`
	MaxAttempts      int                      `json:"max_attempts"`
	LeaseID          string                   `json:"lease_id,omitempty"`
	LeasedByTargetID string                   `json:"leased_by_target_id,omitempty"`
	LeaseExpiresAt   string                   `json:"lease_expires_at,omitempty"`
	RunID            string                   `json:"run_id,omitempty"`
	LastError        string                   `json:"last_error,omitempty"`
	EnqueuedAt       string                   `json:"enqueued_at"`
	UpdatedAt        string                   `json:"updated_at"`
	StartedAt        string                   `json:"started_at,omitempty"`
	CompletedAt      string                   `json:"completed_at,omitempty"`
}

// OperationRunQueueQuery selects queued Operation run records.
type OperationRunQueueQuery struct {
	OperationID string `json:"operation_id,omitempty"`
	Status      string `json:"status,omitempty"`
	TargetID    string `json:"target_id,omitempty"`
	Limit       int    `json:"limit,omitempty"`
}

// OperationScheduleResult reports one scheduler scan.
type OperationScheduleResult struct {
	Checked  int                     `json:"checked"`
	Enqueued []OperationRunQueueItem `json:"enqueued,omitempty"`
	Skipped  []OperationScheduleSkip `json:"skipped,omitempty"`
}

// OperationScheduleSkip stores a display-safe skipped schedule reason.
type OperationScheduleSkip struct {
	OperationID string `json:"operation_id"`
	Reason      string `json:"reason"`
}

// OperationRunLeaseRequest carries a target lease request.
type OperationRunLeaseRequest struct {
	TargetID     string `json:"target_id"`
	LeaseSeconds int    `json:"lease_seconds,omitempty"`
}

// OperationRunLease stores one worker lease over a queued run.
type OperationRunLease struct {
	Item           OperationRunQueueItem `json:"item"`
	LeaseID        string                `json:"lease_id"`
	LeaseExpiresAt string                `json:"lease_expires_at"`
}

// OperationRunLeaseRenewRequest extends an existing worker lease.
type OperationRunLeaseRenewRequest struct {
	LeaseID      string `json:"lease_id"`
	LeaseSeconds int    `json:"lease_seconds,omitempty"`
}

// OperationRunLeaseReleaseRequest completes or fails a leased queued run.
type OperationRunLeaseReleaseRequest struct {
	LeaseID string `json:"lease_id"`
	Status  string `json:"status"`
	RunID   string `json:"run_id,omitempty"`
	Error   string `json:"error,omitempty"`
}

// OperationPreview contains a dry-run resolution and policy decision.
type OperationPreview struct {
	Operation      Operation               `json:"operation"`
	ResolvedInput  map[string]any          `json:"resolved_input"`
	Resolution     map[string]any          `json:"resolution"`
	MissingSetup   []string                `json:"missing_setup,omitempty"`
	PolicyDecision OperationPolicyDecision `json:"policy_decision"`
	Status         string                  `json:"status"`
}

// OperationStartResult contains the workflow run started by Operations.
type OperationStartResult struct {
	Operation Operation            `json:"operation"`
	Run       WorkflowRun          `json:"run"`
	Preview   OperationPreview     `json:"preview"`
	Link      OperationRunLink     `json:"link"`
	Snapshot  OperationRunSnapshot `json:"snapshot"`
}

// OperationRunQueueStartResult contains the workflow run started from a lease.
type OperationRunQueueStartResult struct {
	Item     OperationRunQueueItem `json:"item"`
	Run      WorkflowRun           `json:"run"`
	Link     OperationRunLink      `json:"link"`
	Snapshot OperationRunSnapshot  `json:"snapshot"`
}

// OperationPolicyDecision reports start-time policy evaluation.
type OperationPolicyDecision struct {
	Status  string   `json:"status"`
	Reasons []string `json:"reasons,omitempty"`
}

// WorkflowRun stores the workflow run subset returned by the executor.
type WorkflowRun struct {
	ID           string         `json:"id"`
	DefinitionID string         `json:"definition_id"`
	Status       string         `json:"status"`
	Input        map[string]any `json:"input,omitempty"`
}
