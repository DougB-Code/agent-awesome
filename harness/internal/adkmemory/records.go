// This file maps graph-backed memory records into runtime memory entries.
package adkmemory

import "time"

// sourceRef identifies the origin of memory evidence.
type sourceRef struct {
	System string `json:"system"`
	ID     string `json:"id"`
}

// rawEvidence stores hydrated source text returned by search_sources.
type rawEvidence struct {
	ID          string    `json:"id"`
	ContentText string    `json:"content_text"`
	CreatedAt   time.Time `json:"created_at"`
	Source      sourceRef `json:"source"`
}

// memoryRecord is the subset of graph memory fields needed by the runtime.
type memoryRecord struct {
	ID         string       `json:"id"`
	EvidenceID string       `json:"evidence_id"`
	Title      string       `json:"title"`
	Summary    string       `json:"summary"`
	Subjects   []string     `json:"subjects"`
	EventTime  *time.Time   `json:"event_time,omitempty"`
	CreatedAt  time.Time    `json:"created_at"`
	UpdatedAt  time.Time    `json:"updated_at"`
	Source     sourceRef    `json:"source"`
	Raw        *rawEvidence `json:"raw,omitempty"`
}

// retrievalBundle is the MCP search_sources structured response.
type retrievalBundle struct {
	Primary []memoryRecord `json:"primary_memory"`
}

// recordText returns the best text available for a memory record.
func recordText(record memoryRecord) string {
	if record.Raw != nil && record.Raw.ContentText != "" {
		return record.Raw.ContentText
	}
	if record.Summary != "" {
		return record.Summary
	}
	return record.Title
}

// recordAuthor returns a compact author label for a memory record.
func recordAuthor(record memoryRecord) string {
	if len(record.Subjects) > 0 && record.Subjects[0] != "" {
		return record.Subjects[0]
	}
	if record.Source.System != "" {
		return record.Source.System
	}
	return "agentawesome-harness"
}

// recordTimestamp returns the event time when available, then storage time.
func recordTimestamp(record memoryRecord) time.Time {
	if record.EventTime != nil {
		return *record.EventTime
	}
	if !record.CreatedAt.IsZero() {
		return record.CreatedAt
	}
	return record.UpdatedAt
}
