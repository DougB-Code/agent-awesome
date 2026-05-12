package domain

import (
	"time"

	"memory/internal/memory/vocabulary"
)

// EvidenceID identifies an immutable raw source artifact.
type EvidenceID string

// MemoryID identifies the memory record that makes source content discoverable.
type MemoryID string

// EntityID identifies a canonical entity.
type EntityID string

// PageID identifies a compiled knowledge page.
type PageID string

// JobID identifies an asynchronous enrichment or maintenance job.
type JobID string

// AuditID identifies an audit event.
type AuditID string

// Kind classifies the durable memory object's material form.
type Kind string

const (
	// KindConversation stores conversation transcripts.
	KindConversation Kind = "conversation"
	// KindDocument stores uploaded or fetched documents.
	KindDocument Kind = "document"
	// KindToolOutput stores tool output source content.
	KindToolOutput Kind = "tool_output"
	// KindArtifact stores named generated artifacts.
	KindArtifact Kind = "artifact"
	// KindSummary stores source-backed summaries.
	KindSummary Kind = "summary"
	// KindEntityPage stores compiled entity pages.
	KindEntityPage Kind = "entity_page"
	// KindTimeline stores compiled timelines.
	KindTimeline Kind = "timeline"
	// KindProfileFact stores durable profile facts.
	KindProfileFact Kind = "profile_fact"
)

// Firewall classifies the memory firewall boundary for records.
type Firewall = vocabulary.Firewall

const (
	// FirewallSession limits memory to one session.
	FirewallSession = vocabulary.FirewallSession
	// FirewallUser limits memory to one user.
	FirewallUser = vocabulary.FirewallUser
	// FirewallHousehold shares memory across a household.
	FirewallHousehold = vocabulary.FirewallHousehold
	// FirewallTenant limits memory to an organization tenant.
	FirewallTenant = vocabulary.FirewallTenant
	// FirewallProject limits memory to a project.
	FirewallProject = vocabulary.FirewallProject
	// FirewallGlobal exposes memory globally within the service policy.
	FirewallGlobal = vocabulary.FirewallGlobal
)

// TrustLevel describes where a fact or artifact came from.
type TrustLevel = vocabulary.TrustLevel

const (
	// TrustSourceOriginal marks verbatim source artifacts.
	TrustSourceOriginal = vocabulary.TrustSourceOriginal
	// TrustUserAsserted marks user-supplied claims.
	TrustUserAsserted = vocabulary.TrustUserAsserted
	// TrustModelExtracted marks model-extracted fields.
	TrustModelExtracted = vocabulary.TrustModelExtracted
	// TrustModelSynthesized marks model-written summaries or pages.
	TrustModelSynthesized = vocabulary.TrustModelSynthesized
	// TrustExternallyVerified marks facts checked against an external source.
	TrustExternallyVerified = vocabulary.TrustExternallyVerified
)

// Sensitivity controls whether a caller may see a record.
type Sensitivity = vocabulary.Sensitivity

const (
	// SensitivityPublic is safe for broad disclosure.
	SensitivityPublic = vocabulary.SensitivityPublic
	// SensitivityInternal is visible inside the configured boundary.
	SensitivityInternal = vocabulary.SensitivityInternal
	// SensitivityPrivate is visible to the owning user or household.
	SensitivityPrivate = vocabulary.SensitivityPrivate
	// SensitivityRestricted requires an explicit request grant.
	SensitivityRestricted = vocabulary.SensitivityRestricted
)

// Status describes the lifecycle state of memory.
type Status = vocabulary.LifecycleStatus

const (
	// StatusActive marks current records.
	StatusActive = vocabulary.StatusActive
	// StatusSuperseded marks records replaced by newer source content.
	StatusSuperseded = vocabulary.StatusSuperseded
	// StatusDeprecated marks discouraged records that remain auditable.
	StatusDeprecated = vocabulary.StatusDeprecated
	// StatusArchived marks retained but inactive records.
	StatusArchived = vocabulary.StatusArchived
)

// RelationshipType names a relationship between durable memory objects.
type RelationshipType string

const (
	// RelationshipGeneratedBy links a derived object to its generator.
	RelationshipGeneratedBy RelationshipType = "generated_by"
	// RelationshipRefersTo links an object to another referenced object.
	RelationshipRefersTo RelationshipType = "refers_to"
	// RelationshipSupersedes links a newer object to an older object.
	RelationshipSupersedes RelationshipType = "supersedes"
	// RelationshipContradicts links conflicting records.
	RelationshipContradicts RelationshipType = "contradicts"
	// RelationshipDuplicates links duplicate records.
	RelationshipDuplicates RelationshipType = "duplicates"
	// RelationshipRelatedToEvent links memory to an event or timeline.
	RelationshipRelatedToEvent RelationshipType = "related_to_event"
)

// JobKind identifies asynchronous memory work.
type JobKind string

const (
	// JobClassify enriches memory facets.
	JobClassify JobKind = "classification"
	// JobResolveEntities canonicalizes entity names and aliases.
	JobResolveEntities JobKind = "entity_resolution"
	// JobLinkRelationships discovers and records related memory.
	JobLinkRelationships JobKind = "relationship_linking"
	// JobSummarize creates source-backed summaries.
	JobSummarize JobKind = "summarization"
	// JobRefreshCompiledPage refreshes compiled knowledge pages.
	JobRefreshCompiledPage JobKind = "compiled_page_refresh"
	// JobDetectDuplicates finds identical or near-identical source content.
	JobDetectDuplicates JobKind = "duplicate_detection"
	// JobReviewContradictions flags conflicting claims.
	JobReviewContradictions JobKind = "contradiction_review"
	// JobReindex refreshes lexical indexes.
	JobReindex JobKind = "reindexing"
)

// JobStatus describes queue state for an asynchronous job.
type JobStatus string

const (
	// JobPending is ready to be leased.
	JobPending JobStatus = "pending"
	// JobRunning is leased by a worker.
	JobRunning JobStatus = "running"
	// JobSucceeded completed successfully.
	JobSucceeded JobStatus = "succeeded"
	// JobFailed exhausted retry attempts.
	JobFailed JobStatus = "failed"
)

// SourceRef identifies where raw source content came from.
type SourceRef struct {
	System string `json:"system"`
	ID     string `json:"id"`
}

// RawEvidence stores immutable source truth.
type RawEvidence struct {
	ID          EvidenceID `json:"id"`
	Checksum    string     `json:"checksum"`
	Path        string     `json:"path"`
	MediaType   string     `json:"media_type"`
	Source      SourceRef  `json:"source"`
	Title       string     `json:"title"`
	CreatedAt   time.Time  `json:"created_at"`
	SizeBytes   int64      `json:"size_bytes"`
	ContentText string     `json:"content_text,omitempty"`
	Idempotency string     `json:"idempotency_key,omitempty"`
}

// MemoryRecord stores retrieval metadata for raw source content.
type MemoryRecord struct {
	ID            MemoryID       `json:"id"`
	EvidenceID    EvidenceID     `json:"evidence_id"`
	Kind          Kind           `json:"kind"`
	Firewall      Firewall       `json:"firewall"`
	TrustLevel    TrustLevel     `json:"trust_level"`
	Sensitivity   Sensitivity    `json:"sensitivity"`
	Status        Status         `json:"status"`
	Title         string         `json:"title"`
	Summary       string         `json:"summary"`
	Subjects      []string       `json:"subjects"`
	Topics        []string       `json:"topics"`
	EntityIDs     []EntityID     `json:"entity_ids"`
	EntityNames   []string       `json:"entity_names,omitempty"`
	EventTime     *time.Time     `json:"event_time,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	Idempotency   string         `json:"idempotency_key,omitempty"`
	Source        SourceRef      `json:"source"`
	Raw           *RawEvidence   `json:"raw,omitempty"`
	Relationships []Relationship `json:"relationships,omitempty"`
}

// Entity stores a canonical named thing and its aliases.
type Entity struct {
	ID        EntityID  `json:"id"`
	Name      string    `json:"name"`
	Aliases   []string  `json:"aliases"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Relationship links memory records, source content, pages, entities, and events.
type Relationship struct {
	ID         string           `json:"id"`
	FromID     string           `json:"from_id"`
	Type       RelationshipType `json:"type"`
	ToID       string           `json:"to_id"`
	SourceID   EvidenceID       `json:"source_id,omitempty"`
	TrustLevel TrustLevel       `json:"trust_level"`
	CreatedAt  time.Time        `json:"created_at"`
}

// CompiledPage stores a source-backed human-readable knowledge artifact.
type CompiledPage struct {
	ID          PageID       `json:"id"`
	Kind        Kind         `json:"kind"`
	Firewall    Firewall     `json:"firewall"`
	Title       string       `json:"title"`
	Path        string       `json:"path"`
	Status      Status       `json:"status"`
	SourceIDs   []EvidenceID `json:"source_ids"`
	Content     string       `json:"content,omitempty"`
	CreatedAt   time.Time    `json:"created_at"`
	UpdatedAt   time.Time    `json:"updated_at"`
	Stale       bool         `json:"stale"`
	Uncertainty []string     `json:"uncertainty,omitempty"`
}

// AuditEvent records how memory changed or was retrieved.
type AuditEvent struct {
	ID        AuditID    `json:"id"`
	Kind      string     `json:"kind"`
	Actor     string     `json:"actor"`
	SubjectID string     `json:"subject_id"`
	SourceID  EvidenceID `json:"source_id,omitempty"`
	Message   string     `json:"message"`
	Details   string     `json:"details,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

// Job stores durable asynchronous work.
type Job struct {
	ID             JobID     `json:"id"`
	Kind           JobKind   `json:"kind"`
	TargetID       string    `json:"target_id"`
	Status         JobStatus `json:"status"`
	IdempotencyKey string    `json:"idempotency_key"`
	Payload        string    `json:"payload"`
	Attempts       int       `json:"attempts"`
	MaxAttempts    int       `json:"max_attempts"`
	AvailableAt    time.Time `json:"available_at"`
	LeasedUntil    time.Time `json:"leased_until,omitempty"`
	LeaseOwner     string    `json:"lease_owner,omitempty"`
	LastError      string    `json:"last_error,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// CaptureRequest asks the service to persist new source content.
type CaptureRequest struct {
	Actor          string      `json:"actor"`
	Content        string      `json:"content"`
	MediaType      string      `json:"media_type"`
	Title          string      `json:"title"`
	Source         SourceRef   `json:"source"`
	Kind           Kind        `json:"kind"`
	Firewall       Firewall    `json:"firewall"`
	TrustLevel     TrustLevel  `json:"trust_level"`
	Sensitivity    Sensitivity `json:"sensitivity"`
	Subjects       []string    `json:"subjects"`
	Topics         []string    `json:"topics"`
	EntityNames    []string    `json:"entity_names"`
	EventTime      *time.Time  `json:"event_time,omitempty"`
	IdempotencyKey string      `json:"idempotency_key"`
}

// CaptureResult returns the synchronous write result.
type CaptureResult struct {
	EvidenceID EvidenceID `json:"evidence_id"`
	MemoryID   MemoryID   `json:"memory_id"`
	JobIDs     []JobID    `json:"job_ids"`
	Duplicate  bool       `json:"duplicate"`
}

// RetrievalQuery asks the service to search memory.
type RetrievalQuery struct {
	Actor                string        `json:"actor"`
	Firewall             Firewall      `json:"firewall"`
	IncludeGlobal        bool          `json:"include_global,omitempty"`
	Text                 string        `json:"text"`
	Kinds                []Kind        `json:"kinds"`
	Topics               []string      `json:"topics"`
	EntityIDs            []EntityID    `json:"entity_ids"`
	TimeFrom             *time.Time    `json:"time_from,omitempty"`
	TimeTo               *time.Time    `json:"time_to,omitempty"`
	AllowedSensitivities []Sensitivity `json:"allowed_sensitivities"`
	Limit                int           `json:"limit"`
}

// RetrievalBundle returns source content, compiled knowledge, and flags.
type RetrievalBundle struct {
	Primary        []MemoryRecord `json:"primary_memory"`
	Supporting     []MemoryRecord `json:"supporting_memory"`
	CompiledPages  []CompiledPage `json:"compiled_pages"`
	Provenance     []SourceRef    `json:"provenance_links"`
	Uncertainty    []string       `json:"uncertainty"`
	Contradictions []Relationship `json:"contradictions"`
}

// RepairRequest asks the service to correct memory metadata.
type RepairRequest struct {
	Actor       string       `json:"actor"`
	MemoryID    MemoryID     `json:"memory_id"`
	Kind        *Kind        `json:"kind,omitempty"`
	Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
	Status      *Status      `json:"status,omitempty"`
	Title       *string      `json:"title,omitempty"`
	Summary     *string      `json:"summary,omitempty"`
	Subjects    []string     `json:"subjects,omitempty"`
	Topics      []string     `json:"topics,omitempty"`
	EntityNames []string     `json:"entity_names,omitempty"`
}

// CorrectionRequest records a user correction as first-class source content.
type CorrectionRequest struct {
	Actor    string   `json:"actor"`
	MemoryID MemoryID `json:"memory_id"`
	Firewall Firewall `json:"firewall"`
	Text     string   `json:"text"`
}

// RefreshPageRequest asks the service to rebuild a compiled page.
type RefreshPageRequest struct {
	Actor    string   `json:"actor"`
	Kind     Kind     `json:"kind"`
	Firewall Firewall `json:"firewall"`
	Title    string   `json:"title"`
	EntityID EntityID `json:"entity_id,omitempty"`
	Topic    string   `json:"topic,omitempty"`
}

// Metrics summarizes operational service state.
type Metrics struct {
	EvidenceCount      int64 `json:"evidence_count"`
	MemoryCount        int64 `json:"memory_count"`
	PageCount          int64 `json:"page_count"`
	PendingJobs        int64 `json:"pending_jobs"`
	FailedJobs         int64 `json:"failed_jobs"`
	RecordsWithSources int64 `json:"records_with_sources"`
}
