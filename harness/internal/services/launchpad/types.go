// This file defines dumb Launchpad data models and service requests.
package launchpad

const (
	// LaunchRunQueueStatusQueued means a target may lease the queued run.
	LaunchRunQueueStatusQueued = "queued"
	// LaunchRunQueueStatusLeased means a target has leased but not started it.
	LaunchRunQueueStatusLeased = "leased"
	// LaunchRunQueueStatusRunning means a target started the runbook run.
	LaunchRunQueueStatusRunning = "running"
	// LaunchRunQueueStatusCompleted means the queued run finished successfully.
	LaunchRunQueueStatusCompleted = "completed"
	// LaunchRunQueueStatusFailed means the queued run exhausted or reported failure.
	LaunchRunQueueStatusFailed = "failed"
	// LaunchRunQueueStatusCanceled means the queued run was canceled before completion.
	LaunchRunQueueStatusCanceled = "canceled"
)

// Launch stores one reusable runbook binding.
type Launch struct {
	ID              string                   `json:"id"`
	Name            string                   `json:"name"`
	RunbookID      string                   `json:"runbook_id"`
	RunbookVersion string                   `json:"runbook_version,omitempty"`
	CodebaseID      string                   `json:"codebase_id,omitempty"`
	RuntimeTargetID string                   `json:"runtime_target_id,omitempty"`
	AgentProfileID  string                   `json:"agent_profile_id,omitempty"`
	Defaults        map[string]any           `json:"defaults,omitempty"`
	Policy          LaunchPolicy          `json:"policy"`
	Schedule        LaunchSchedule        `json:"schedule,omitempty"`
	SecretRefs      []LaunchSecretBinding `json:"secret_refs,omitempty"`
	Status          string                   `json:"status"`
	Version         int                      `json:"version"`
	CreatedAt       string                   `json:"created_at,omitempty"`
	UpdatedAt       string                   `json:"updated_at,omitempty"`
}

// LaunchVersion stores immutable launch version metadata.
type LaunchVersion struct {
	LaunchID string `json:"launch_id"`
	Version     int    `json:"version"`
	Hash        string `json:"hash"`
	CreatedAt   string `json:"created_at"`
}

// LaunchPolicy stores user-facing safety policy.
type LaunchPolicy struct {
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

// LaunchTarget stores the runtime target binding.
type LaunchTarget struct {
	RuntimeTargetID string `json:"runtime_target_id,omitempty"`
	AgentProfileID  string `json:"agent_profile_id,omitempty"`
}

// LaunchSchedule stores recurring start metadata.
type LaunchSchedule struct {
	Enabled         bool   `json:"enabled,omitempty"`
	Cron            string `json:"cron,omitempty"`
	QuietHoursStart string `json:"quiet_hours_start,omitempty"`
	QuietHoursEnd   string `json:"quiet_hours_end,omitempty"`
	StopAt          string `json:"stop_at,omitempty"`
	MaxRuns         int    `json:"max_runs,omitempty"`
}

// LaunchSecretBinding stores one secret reference binding.
type LaunchSecretBinding struct {
	Name string `json:"name"`
	Ref  string `json:"ref"`
}

// LaunchRunLink links one Launch start to a runbook run.
type LaunchRunLink struct {
	LaunchID string `json:"launch_id"`
	RunID       string `json:"run_id"`
	CreatedAt   string `json:"created_at"`
}

// LaunchRunSnapshot stores immutable run-start audit data.
type LaunchRunSnapshot struct {
	RunID            string                   `json:"run_id"`
	LaunchID      string                   `json:"launch_id"`
	LaunchVersion int                      `json:"launch_version"`
	RunbookID       string                   `json:"runbook_id"`
	RunbookVersion  string                   `json:"runbook_version,omitempty"`
	ResolvedInput    map[string]any           `json:"resolved_input"`
	Resolution       map[string]any           `json:"resolution"`
	Target           LaunchTarget          `json:"target"`
	Policy           LaunchPolicy          `json:"policy"`
	SecretRefs       []LaunchSecretBinding `json:"secret_refs,omitempty"`
	CreatedAt        string                   `json:"created_at"`
}

// Codebase stores the catalog fields Launchpad needs from memory.
type Codebase struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Aliases            []string `json:"aliases,omitempty"`
	RepositoryPath     string   `json:"repository_path,omitempty"`
	DefaultRemote      string   `json:"default_remote,omitempty"`
	DefaultBranch      string   `json:"default_branch,omitempty"`
	Provider           string   `json:"provider,omitempty"`
	ProviderRepository string   `json:"provider_repository,omitempty"`
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

// LaunchRequest carries create and update payloads.
type LaunchRequest struct {
	ID              string                   `json:"id"`
	Name            string                   `json:"name"`
	RunbookID      string                   `json:"runbook_id"`
	RunbookVersion string                   `json:"runbook_version,omitempty"`
	CodebaseID      string                   `json:"codebase_id,omitempty"`
	RuntimeTargetID string                   `json:"runtime_target_id,omitempty"`
	AgentProfileID  string                   `json:"agent_profile_id,omitempty"`
	Defaults        map[string]any           `json:"defaults,omitempty"`
	Policy          LaunchPolicy          `json:"policy,omitempty"`
	Schedule        LaunchSchedule        `json:"schedule,omitempty"`
	SecretRefs      []LaunchSecretBinding `json:"secret_refs,omitempty"`
	Status          string                   `json:"status,omitempty"`
}

// LaunchQuery selects Launchpad for listing.
type LaunchQuery struct {
	RunbookID string `json:"runbook_id,omitempty"`
	CodebaseID string `json:"codebase_id,omitempty"`
	Status     string `json:"status,omitempty"`
}

// LaunchRunRequest carries one preview or start request.
type LaunchRunRequest struct {
	LaunchID  string         `json:"launch_id,omitempty"`
	Input        map[string]any `json:"input,omitempty"`
	CodebaseName string         `json:"codebase_name,omitempty"`
	Source       string         `json:"source,omitempty"`
	Task         map[string]any `json:"task,omitempty"`
}

// LaunchRunQueueItem stores one durable queued Launch run request.
type LaunchRunQueueItem struct {
	ID               string                   `json:"id"`
	LaunchID      string                   `json:"launch_id"`
	LaunchVersion int                      `json:"launch_version"`
	LaunchHash    string                   `json:"launch_hash"`
	RunbookID       string                   `json:"runbook_id"`
	RunbookVersion  string                   `json:"runbook_version,omitempty"`
	Target           LaunchTarget          `json:"target"`
	Policy           LaunchPolicy          `json:"policy"`
	PolicyDecision   LaunchPolicyDecision  `json:"policy_decision"`
	SecretRefs       []LaunchSecretBinding `json:"secret_refs,omitempty"`
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

// LaunchRunQueueQuery selects queued Launch run records.
type LaunchRunQueueQuery struct {
	LaunchID string `json:"launch_id,omitempty"`
	Status      string `json:"status,omitempty"`
	TargetID    string `json:"target_id,omitempty"`
	Limit       int    `json:"limit,omitempty"`
}

// LaunchScheduleResult reports one scheduler scan.
type LaunchScheduleResult struct {
	Checked  int                     `json:"checked"`
	Enqueued []LaunchRunQueueItem `json:"enqueued,omitempty"`
	Skipped  []LaunchScheduleSkip `json:"skipped,omitempty"`
}

// LaunchScheduleSkip stores a display-safe skipped schedule reason.
type LaunchScheduleSkip struct {
	LaunchID string `json:"launch_id"`
	Reason      string `json:"reason"`
}

// LaunchRunLeaseRequest carries a target lease request.
type LaunchRunLeaseRequest struct {
	TargetID     string `json:"target_id"`
	LeaseSeconds int    `json:"lease_seconds,omitempty"`
}

// LaunchRunLease stores one worker lease over a queued run.
type LaunchRunLease struct {
	Item           LaunchRunQueueItem `json:"item"`
	LeaseID        string                `json:"lease_id"`
	LeaseExpiresAt string                `json:"lease_expires_at"`
}

// LaunchRunLeaseRenewRequest extends an existing worker lease.
type LaunchRunLeaseRenewRequest struct {
	LeaseID      string `json:"lease_id"`
	LeaseSeconds int    `json:"lease_seconds,omitempty"`
}

// LaunchRunLeaseReleaseRequest completes or fails a leased queued run.
type LaunchRunLeaseReleaseRequest struct {
	LeaseID string `json:"lease_id"`
	Status  string `json:"status"`
	RunID   string `json:"run_id,omitempty"`
	Error   string `json:"error,omitempty"`
}

// LaunchPreview contains a dry-run resolution and policy decision.
type LaunchPreview struct {
	Launch      Launch               `json:"launch"`
	ResolvedInput  map[string]any          `json:"resolved_input"`
	Resolution     map[string]any          `json:"resolution"`
	MissingSetup   []string                `json:"missing_setup,omitempty"`
	PolicyDecision LaunchPolicyDecision `json:"policy_decision"`
	Status         string                  `json:"status"`
}

// LaunchStartResult contains the runbook run started by Launchpad.
type LaunchStartResult struct {
	Launch Launch            `json:"launch"`
	Run       RunbookRun          `json:"run"`
	Preview   LaunchPreview     `json:"preview"`
	Link      LaunchRunLink     `json:"link"`
	Snapshot  LaunchRunSnapshot `json:"snapshot"`
}

// LaunchRunQueueStartResult contains the runbook run started from a lease.
type LaunchRunQueueStartResult struct {
	Item     LaunchRunQueueItem `json:"item"`
	Run      RunbookRun           `json:"run"`
	Link     LaunchRunLink      `json:"link"`
	Snapshot LaunchRunSnapshot  `json:"snapshot"`
}

// LaunchPolicyDecision reports start-time policy evaluation.
type LaunchPolicyDecision struct {
	Status  string   `json:"status"`
	Reasons []string `json:"reasons,omitempty"`
}

// RunbookRun stores the runbook run subset returned by the executor.
type RunbookRun struct {
	ID           string         `json:"id"`
	DefinitionID string         `json:"definition_id"`
	Status       string         `json:"status"`
	Input        map[string]any `json:"input,omitempty"`
}
