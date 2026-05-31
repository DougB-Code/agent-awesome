package domain

import "time"

// ExecutiveSummarySchemaVersion identifies the canonical Today projection schema.
const ExecutiveSummarySchemaVersion = "agent-awesome/executive-summary/v1"

// ExecutiveSummaryQuery asks the memory service for a read-only Today projection.
type ExecutiveSummaryQuery struct {
	DomainID        DomainID   `json:"domain_id,omitempty"`
	Firewall        Firewall   `json:"firewall,omitempty"`
	Horizon         string     `json:"horizon,omitempty"`
	Now             *time.Time `json:"now,omitempty"`
	MaxItems        int        `json:"max_items,omitempty"`
	IncludeEvidence *bool      `json:"include_evidence,omitempty"`
	IncludeActions  *bool      `json:"include_actions,omitempty"`
	Channel         string     `json:"channel,omitempty"`
}

// ExecutiveSummaryProjection is the canonical source-backed Today read model.
type ExecutiveSummaryProjection struct {
	SchemaVersion    string                   `json:"schema_version"`
	GeneratedAt      time.Time                `json:"generated_at"`
	DomainID         DomainID                 `json:"domain_id,omitempty"`
	Firewall         ProjectionFirewall       `json:"firewall"`
	Horizon          string                   `json:"horizon"`
	Title            string                   `json:"title"`
	Subtitle         string                   `json:"subtitle"`
	NarrativeSummary string                   `json:"narrative_summary"`
	Metrics          []SummaryMetric          `json:"metrics"`
	Attention        AttentionProjection      `json:"attention"`
	OpenLoops        OpenLoopProjection       `json:"open_loops"`
	TimeHorizon      TimeHorizonProjection    `json:"time_horizon"`
	Delegation       DelegationProjection     `json:"delegation"`
	RiskUnblocks     RiskUnblockProjection    `json:"risk_unblocks"`
	Coverage         CoverageProjection       `json:"coverage"`
	Quality          ProjectionQualitySummary `json:"quality"`
	Links            []ProjectionLink         `json:"links"`
}

// ProjectionFirewall describes the memory firewall summarized by a projection.
type ProjectionFirewall struct {
	Kind  string `json:"kind"`
	ID    string `json:"id,omitempty"`
	Label string `json:"label,omitempty"`
}

// SummaryMetric stores one top-line executive summary counter.
type SummaryMetric struct {
	ID       string         `json:"id"`
	Label    string         `json:"label"`
	Value    string         `json:"value"`
	Subtitle string         `json:"subtitle,omitempty"`
	Severity string         `json:"severity,omitempty"`
	Link     ProjectionLink `json:"link,omitempty"`
}

// ProjectionLink stores a route reserved for a deeper projection page.
type ProjectionLink struct {
	Label string `json:"label,omitempty"`
	Route string `json:"route,omitempty"`
}

// ExecutiveSummaryItem stores one ranked item within a Today projection section.
type ExecutiveSummaryItem struct {
	ID              string                     `json:"id"`
	Kind            string                     `json:"kind"`
	Lane            string                     `json:"lane,omitempty"`
	Title           string                     `json:"title"`
	Subtitle        string                     `json:"subtitle,omitempty"`
	Reason          string                     `json:"reason"`
	Score           float64                    `json:"score,omitempty"`
	Confidence      float64                    `json:"confidence,omitempty"`
	Status          string                     `json:"status,omitempty"`
	Priority        string                     `json:"priority,omitempty"`
	TaskID          TaskID                     `json:"task_id,omitempty"`
	Person          string                     `json:"person,omitempty"`
	Project         string                     `json:"project,omitempty"`
	DueAt           *time.Time                 `json:"due_at,omitempty"`
	ScheduledAt     *time.Time                 `json:"scheduled_at,omitempty"`
	FollowUpAt      *time.Time                 `json:"follow_up_at,omitempty"`
	EstimateMinutes int                        `json:"estimate_minutes,omitempty"`
	Evidence        []ExecutiveSummaryEvidence `json:"evidence,omitempty"`
	PrimaryAction   *ExecutiveSummaryAction    `json:"primary_action,omitempty"`
	Actions         []ExecutiveSummaryAction   `json:"actions,omitempty"`
	Links           []ProjectionLink           `json:"links,omitempty"`
}

// ExecutiveSummaryEvidence names source records used for one item.
type ExecutiveSummaryEvidence struct {
	Kind         string `json:"kind"`
	ID           string `json:"id"`
	Label        string `json:"label"`
	Relationship string `json:"relationship,omitempty"`
}

// ExecutiveSummaryAction describes one safe or approval-gated next action.
type ExecutiveSummaryAction struct {
	ID      string `json:"id,omitempty"`
	Label   string `json:"label"`
	Tool    string `json:"tool,omitempty"`
	Safety  string `json:"safety,omitempty"`
	Payload any    `json:"payload,omitempty"`
}

// AttentionProjection groups the ranked items needing user attention.
type AttentionProjection struct {
	Items []ExecutiveSummaryItem `json:"items"`
	Link  ProjectionLink         `json:"link,omitempty"`
}

// OpenLoopProjection summarizes missing, waiting, stale, and blocked work.
type OpenLoopProjection struct {
	Categories []OpenLoopCategory `json:"categories"`
	Link       ProjectionLink     `json:"link,omitempty"`
}

// OpenLoopCategory stores one open-loop category counter and examples.
type OpenLoopCategory struct {
	ID       string                 `json:"id"`
	Label    string                 `json:"label"`
	Count    int                    `json:"count"`
	Severity string                 `json:"severity,omitempty"`
	TopItems []ExecutiveSummaryItem `json:"top_items,omitempty"`
	Link     ProjectionLink         `json:"link,omitempty"`
}

// TimeHorizonProjection stores count buckets for near-future work.
type TimeHorizonProjection struct {
	Buckets []TimeHorizonBucket `json:"buckets"`
	Link    ProjectionLink      `json:"link,omitempty"`
}

// TimeHorizonBucket stores one fixed horizon bucket.
type TimeHorizonBucket struct {
	ID      string         `json:"id"`
	Label   string         `json:"label"`
	Count   int            `json:"count"`
	Summary string         `json:"summary,omitempty"`
	TopItem string         `json:"top_item,omitempty"`
	Link    ProjectionLink `json:"link,omitempty"`
}

// DelegationProjection summarizes what the agent can safely handle.
type DelegationProjection struct {
	Buckets []DelegationBucket `json:"buckets"`
	Link    ProjectionLink     `json:"link,omitempty"`
}

// DelegationBucket stores one agent-status bucket.
type DelegationBucket struct {
	ID       string                 `json:"id"`
	Label    string                 `json:"label"`
	Count    int                    `json:"count"`
	Items    []ExecutiveSummaryItem `json:"items,omitempty"`
	Severity string                 `json:"severity,omitempty"`
	Link     ProjectionLink         `json:"link,omitempty"`
}

// RiskUnblockProjection stores dependency chains and unblock suggestions.
type RiskUnblockProjection struct {
	Chains []RiskUnblockChain `json:"chains"`
	Link   ProjectionLink     `json:"link,omitempty"`
}

// RiskUnblockChain stores one blocker-to-outcome chain.
type RiskUnblockChain struct {
	ID              string                  `json:"id"`
	Nodes           []RiskUnblockChainNode  `json:"nodes"`
	SuggestedAction *ExecutiveSummaryAction `json:"suggested_action,omitempty"`
}

// RiskUnblockChainNode stores one node in a risk or unblock chain.
type RiskUnblockChainNode struct {
	TaskID   TaskID `json:"task_id,omitempty"`
	Title    string `json:"title"`
	Subtitle string `json:"subtitle,omitempty"`
}

// CoverageProjection stores source coverage and explicit unknown domains.
type CoverageProjection struct {
	Good         []string `json:"good"`
	Partial      []string `json:"partial"`
	NotConnected []string `json:"not_connected"`
	Promise      string   `json:"promise"`
}

// ProjectionQualitySummary communicates confidence without inventing unknown data.
type ProjectionQualitySummary struct {
	Label            string   `json:"label"`
	RelationCoverage float64  `json:"relation_coverage"`
	TaskCount        int      `json:"task_count"`
	UnknownDomains   []string `json:"unknown_domains,omitempty"`
	Limits           []string `json:"limits,omitempty"`
}

// ExplainExecutiveSummaryItemQuery asks why one projection item was surfaced.
type ExplainExecutiveSummaryItemQuery struct {
	ItemID         string `json:"item_id"`
	IncludeSources *bool  `json:"include_sources,omitempty"`
}

// ExecutiveSummaryItemExplanation explains one surfaced Today item.
type ExecutiveSummaryItemExplanation struct {
	ItemID     string                     `json:"item_id"`
	Title      string                     `json:"title"`
	Reason     string                     `json:"reason"`
	Evidence   []ExecutiveSummaryEvidence `json:"evidence,omitempty"`
	Confidence float64                    `json:"confidence"`
	Limits     []string                   `json:"limits,omitempty"`
}

// IncludeEvidenceEnabled reports whether source handles should be returned.
func (q ExecutiveSummaryQuery) IncludeEvidenceEnabled() bool {
	return q.IncludeEvidence == nil || *q.IncludeEvidence
}

// IncludeActionsEnabled reports whether action hints should be returned.
func (q ExecutiveSummaryQuery) IncludeActionsEnabled() bool {
	return q.IncludeActions == nil || *q.IncludeActions
}

// IncludeSourcesEnabled reports whether explanation source handles should be returned.
func (q ExplainExecutiveSummaryItemQuery) IncludeSourcesEnabled() bool {
	return q.IncludeSources == nil || *q.IncludeSources
}
