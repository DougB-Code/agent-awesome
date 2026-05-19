// This file defines durable workflow store records.
package store

// DefinitionRecord stores one installed workflow definition snapshot.
type DefinitionRecord struct {
	ID        string         `json:"id"`
	Kind      string         `json:"kind"`
	Name      string         `json:"name"`
	Hash      string         `json:"hash"`
	Body      map[string]any `json:"body"`
	UpdatedAt string         `json:"updated_at"`
}

// RunRecord stores one workflow run state.
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

// EventRecord stores one workflow run event.
type EventRecord struct {
	ID        int64          `json:"id"`
	RunID     string         `json:"run_id"`
	Type      string         `json:"type"`
	Message   string         `json:"message"`
	Data      map[string]any `json:"data"`
	CreatedAt string         `json:"created_at"`
}

// TaskStateRecord stores durable execution status for one task state.
type TaskStateRecord struct {
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

// PendingItem stores one user-visible workflow inbox item.
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

// DraftRecord stores one editable workflow authoring draft.
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

// TemplateRecord stores one parameterized workflow template.
type TemplateRecord struct {
	ID           string           `json:"id"`
	Name         string           `json:"name"`
	Description  string           `json:"description"`
	Category     string           `json:"category"`
	Tags         []string         `json:"tags"`
	Parameters   []map[string]any `json:"parameters"`
	Requirements map[string]any   `json:"requirements"`
	Body         map[string]any   `json:"body"`
	CreatedAt    string           `json:"created_at"`
	UpdatedAt    string           `json:"updated_at"`
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

// PublishedDefinitionRecord links published definitions back to authoring drafts.
type PublishedDefinitionRecord struct {
	DefinitionID string `json:"definition_id"`
	DraftID      string `json:"draft_id"`
	Path         string `json:"path"`
	Hash         string `json:"hash"`
	PublishedAt  string `json:"published_at"`
}

// RunFilter selects workflow runs for operator views.
type RunFilter struct {
	Status       string
	DefinitionID string
	Limit        int
}
