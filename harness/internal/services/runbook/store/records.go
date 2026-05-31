// This file defines durable runbook store records.
package store

const (
	// StatusRunning records an actively executing runbook or node.
	StatusRunning = "running"
	// StatusWaiting records a runbook paused on external input.
	StatusWaiting = "waiting"
	// StatusSucceeded records successful runbook or node completion.
	StatusSucceeded = "succeeded"
	// StatusFailed records failed runbook or node completion.
	StatusFailed = "failed"
	// StatusCanceled records a canceled runbook.
	StatusCanceled = "canceled"
	// StatusPending records an unstarted in-memory node state.
	StatusPending = "pending"
	// StatusSkipped records a conditionally inactive runbook node.
	StatusSkipped = "skipped"
)

const (
	// PendingStatusOpen records a pending item awaiting response.
	PendingStatusOpen = "open"
	// PendingStatusCompleted records a pending item with a response.
	PendingStatusCompleted = "completed"
)

// DefinitionRecord stores one installed runbook definition snapshot.
type DefinitionRecord struct {
	ID        string         `json:"id"`
	Kind      string         `json:"kind"`
	Name      string         `json:"name"`
	Hash      string         `json:"hash"`
	Body      map[string]any `json:"body"`
	UpdatedAt string         `json:"updated_at"`
}

// RunRecord stores one runbook run state.
type RunRecord struct {
	ID           string         `json:"id"`
	DefinitionID string         `json:"definition_id"`
	Kind         string         `json:"kind"`
	Status       string         `json:"status"`
	State        string         `json:"state"`
	Input        map[string]any `json:"input"`
	Output       map[string]any `json:"output"`
	CreatedAt    string         `json:"created_at"`
	UpdatedAt    string         `json:"updated_at"`
}

// RunSetupRecord stores reusable input for starting runbook runs.
type RunSetupRecord struct {
	ID           string         `json:"id"`
	DefinitionID string         `json:"definition_id"`
	Name         string         `json:"name"`
	Description  string         `json:"description"`
	Input        map[string]any `json:"input"`
	CreatedAt    string         `json:"created_at"`
	UpdatedAt    string         `json:"updated_at"`
}

// EventRecord stores one runbook run event.
type EventRecord struct {
	ID        int64          `json:"id"`
	RunID     string         `json:"run_id"`
	Type      string         `json:"type"`
	Message   string         `json:"message"`
	Data      map[string]any `json:"data"`
	CreatedAt string         `json:"created_at"`
}

// NodeStateRecord stores durable execution status for one runbook node.
type NodeStateRecord struct {
	RunID       string         `json:"run_id"`
	StateID     string         `json:"state_id"`
	Status      string         `json:"status"`
	Attempts    int            `json:"attempts"`
	Output      map[string]any `json:"output"`
	Error       string         `json:"error"`
	StartedAt   string         `json:"started_at"`
	CompletedAt string         `json:"completed_at"`
	UpdatedAt   string         `json:"updated_at"`
}

// PendingItem stores one user-visible runbook inbox item.
type PendingItem struct {
	ID        string         `json:"id"`
	RunID     string         `json:"run_id"`
	StepID    string         `json:"step_id"`
	Status    string         `json:"status"`
	Prompt    string         `json:"prompt"`
	Payload   map[string]any `json:"payload"`
	Response  map[string]any `json:"response"`
	CreatedAt string         `json:"created_at"`
	UpdatedAt string         `json:"updated_at"`
}

// DraftRecord stores one editable runbook authoring draft.
type DraftRecord struct {
	ID          string         `json:"id"`
	Kind        string         `json:"kind"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Status      string         `json:"status"`
	Body        map[string]any `json:"body"`
	Validation  map[string]any `json:"validation"`
	CreatedAt   string         `json:"created_at"`
	UpdatedAt   string         `json:"updated_at"`
}

// PackageRecord stores an importable or exportable automation package.
type PackageRecord struct {
	ID          string         `json:"id"`
	Name        string         `json:"name"`
	Version     string         `json:"version"`
	Description string         `json:"description"`
	Body        map[string]any `json:"body"`
	CreatedAt   string         `json:"created_at"`
	UpdatedAt   string         `json:"updated_at"`
}

// DesignArtifactRecord stores a deterministic artifact proposed at design time.
type DesignArtifactRecord struct {
	ID        string         `json:"id"`
	Kind      string         `json:"kind"`
	Name      string         `json:"name"`
	Body      map[string]any `json:"body"`
	CreatedAt string         `json:"created_at"`
}

// ObservedContractRecord stores one runtime-observed output contract shape.
type ObservedContractRecord struct {
	DefinitionID   string           `json:"definition_id"`
	NodeID         string           `json:"node_id"`
	ToolID         string           `json:"tool_id"`
	ShapeHash      string           `json:"shape_hash"`
	Occurrences    int              `json:"occurrences"`
	Contract       map[string]any   `json:"contract"`
	ObservedFields []map[string]any `json:"observed_fields"`
	FirstSeenAt    string           `json:"first_seen_at"`
	LastSeenAt     string           `json:"last_seen_at"`
}

// PublishedDefinitionRecord links published definitions back to authoring drafts.
type PublishedDefinitionRecord struct {
	DefinitionID string `json:"definition_id"`
	DraftID      string `json:"draft_id"`
	Path         string `json:"path"`
	Hash         string `json:"hash"`
	PublishedAt  string `json:"published_at"`
}

// RunFilter selects runbook runs for operator views.
type RunFilter struct {
	Status       string
	DefinitionID string
	Limit        int
}

// RunSetupFilter selects reusable runbook run setups for operator views.
type RunSetupFilter struct {
	DefinitionID string
}

// ObservedContractFilter selects runtime-observed output shapes.
type ObservedContractFilter struct {
	DefinitionID string
	NodeID       string
	ToolID       string
	Limit        int
}
