// This file defines dumb codebase catalog data models.
package domain

import "time"

// Codebase stores durable repository metadata for workflow operations.
type Codebase struct {
	ID                 string    `json:"id"`
	Name               string    `json:"name"`
	Aliases            []string  `json:"aliases,omitempty"`
	RepositoryPath     string    `json:"repository_path,omitempty"`
	DefaultRemote      string    `json:"default_remote,omitempty"`
	DefaultBranch      string    `json:"default_branch,omitempty"`
	Provider           string    `json:"provider,omitempty"`
	ProviderRepository string    `json:"provider_repository,omitempty"`
	RuntimeTargetID    string    `json:"runtime_target_id,omitempty"`
	AgentProfileID     string    `json:"agent_profile_id,omitempty"`
	CreatedAt          time.Time `json:"created_at,omitempty"`
	UpdatedAt          time.Time `json:"updated_at,omitempty"`
}

// UpsertCodebaseRequest carries one codebase catalog write.
type UpsertCodebaseRequest struct {
	Codebase Codebase `json:"codebase"`
	Actor    string   `json:"actor,omitempty"`
}

// CodebaseIDRequest identifies one codebase catalog entry.
type CodebaseIDRequest struct {
	ID    string `json:"id"`
	Actor string `json:"actor,omitempty"`
}

// CodebaseQuery selects codebase catalog entries.
type CodebaseQuery struct {
	Text  string `json:"text,omitempty"`
	Limit int    `json:"limit,omitempty"`
	Actor string `json:"actor,omitempty"`
}

// ResolveCodebaseRequest carries a human codebase lookup phrase.
type ResolveCodebaseRequest struct {
	Query string `json:"query"`
	Actor string `json:"actor,omitempty"`
}

// CodebaseMatch stores one candidate codebase resolution.
type CodebaseMatch struct {
	Codebase   Codebase `json:"codebase"`
	Confidence float64  `json:"confidence"`
	Reason     string   `json:"reason,omitempty"`
}

// CodebaseResolution describes a deterministic codebase lookup result.
type CodebaseResolution struct {
	Status      string          `json:"status"`
	Codebase    *Codebase       `json:"codebase,omitempty"`
	Matches     []CodebaseMatch `json:"matches,omitempty"`
	Diagnostics []string        `json:"diagnostics,omitempty"`
}
