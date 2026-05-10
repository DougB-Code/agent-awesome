package domain

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// NormalizeExecutiveSummaryQuery validates and defaults a Today projection query.
func NormalizeExecutiveSummaryQuery(q ExecutiveSummaryQuery) (ExecutiveSummaryQuery, error) {
	if q.Scope == "" {
		q.Scope = ScopeUser
	}
	if !ValidScope(q.Scope) {
		return q, fmt.Errorf("invalid scope %q", q.Scope)
	}
	q.Horizon = strings.TrimSpace(q.Horizon)
	if q.Horizon == "" {
		q.Horizon = "today"
	}
	if !validExecutiveSummaryHorizon(q.Horizon) {
		return q, fmt.Errorf("invalid horizon %q", q.Horizon)
	}
	if q.Now == nil {
		now := time.Now().UTC()
		q.Now = &now
	} else {
		now := q.Now.UTC()
		q.Now = &now
	}
	if q.MaxItems <= 0 {
		q.MaxItems = 12
	}
	if q.MaxItems > 50 {
		q.MaxItems = 50
	}
	if q.IncludeEvidence == nil {
		value := true
		q.IncludeEvidence = &value
	}
	if q.IncludeActions == nil {
		value := true
		q.IncludeActions = &value
	}
	q.Channel = strings.TrimSpace(q.Channel)
	if q.Channel == "" {
		q.Channel = "ui"
	}
	if !validExecutiveSummaryChannel(q.Channel) {
		return q, fmt.Errorf("invalid channel %q", q.Channel)
	}
	return q, nil
}

// NormalizeExplainExecutiveSummaryItemQuery validates an explanation request.
func NormalizeExplainExecutiveSummaryItemQuery(q ExplainExecutiveSummaryItemQuery) (ExplainExecutiveSummaryItemQuery, error) {
	q.ItemID = strings.TrimSpace(q.ItemID)
	if q.ItemID == "" {
		return q, errors.New("item_id is required")
	}
	if q.IncludeSources == nil {
		value := true
		q.IncludeSources = &value
	}
	return q, nil
}

// validExecutiveSummaryHorizon reports whether the projection horizon is supported.
func validExecutiveSummaryHorizon(horizon string) bool {
	switch horizon {
	case "now", "today", "tomorrow", "week", "all":
		return true
	default:
		return false
	}
}

// validExecutiveSummaryChannel reports whether the presentation channel is supported.
func validExecutiveSummaryChannel(channel string) bool {
	switch channel {
	case "ui", "slack", "chat", "api":
		return true
	default:
		return false
	}
}
