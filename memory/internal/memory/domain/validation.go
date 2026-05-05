package domain

import (
	"errors"
	"fmt"
	"strings"
)

// NormalizeCaptureRequest fills conservative defaults and validates a write.
func NormalizeCaptureRequest(req CaptureRequest) (CaptureRequest, error) {
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		return req, errors.New("content is required")
	}
	req.Actor = normalizeDefault(req.Actor, "agent")
	req.MediaType = normalizeDefault(req.MediaType, "text/plain; charset=utf-8")
	req.Title = strings.TrimSpace(req.Title)
	if req.Title == "" {
		req.Title = "Untitled memory"
	}
	req.IdempotencyKey = strings.TrimSpace(req.IdempotencyKey)
	if req.Kind == "" {
		req.Kind = KindDocument
	}
	if !ValidKind(req.Kind) {
		return req, fmt.Errorf("invalid kind %q", req.Kind)
	}
	if req.Scope == "" {
		req.Scope = ScopeUser
	}
	if !ValidScope(req.Scope) {
		return req, fmt.Errorf("invalid scope %q", req.Scope)
	}
	if req.TrustLevel == "" {
		req.TrustLevel = TrustSourceOriginal
	}
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	if req.Sensitivity == "" {
		req.Sensitivity = SensitivityPrivate
	}
	if !ValidSensitivity(req.Sensitivity) {
		return req, fmt.Errorf("invalid sensitivity %q", req.Sensitivity)
	}
	req.Subjects = NormalizeStrings(req.Subjects)
	req.Topics = NormalizeStrings(req.Topics)
	req.EntityNames = NormalizeStrings(req.EntityNames)
	return req, nil
}

// NormalizeRetrievalQuery fills safe retrieval defaults and validates filters.
func NormalizeRetrievalQuery(q RetrievalQuery) (RetrievalQuery, error) {
	q.Actor = normalizeDefault(q.Actor, "agent")
	if q.Scope == "" {
		q.Scope = ScopeUser
	}
	if !ValidScope(q.Scope) {
		return q, fmt.Errorf("invalid scope %q", q.Scope)
	}
	for _, kind := range q.Kinds {
		if !ValidKind(kind) {
			return q, fmt.Errorf("invalid kind %q", kind)
		}
	}
	q.Topics = NormalizeStrings(q.Topics)
	if len(q.AllowedSensitivities) == 0 {
		q.AllowedSensitivities = []Sensitivity{SensitivityPublic, SensitivityInternal, SensitivityPrivate}
	}
	for _, sensitivity := range q.AllowedSensitivities {
		if !ValidSensitivity(sensitivity) {
			return q, fmt.Errorf("invalid sensitivity %q", sensitivity)
		}
	}
	if q.Limit <= 0 || q.Limit > 100 {
		q.Limit = 20
	}
	return q, nil
}

// NormalizeRepairRequest validates a memory repair request.
func NormalizeRepairRequest(req RepairRequest) (RepairRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "agent")
	if req.MemoryID == "" {
		return req, errors.New("memory_id is required")
	}
	if req.Kind != nil && !ValidKind(*req.Kind) {
		return req, fmt.Errorf("invalid kind %q", *req.Kind)
	}
	if req.Sensitivity != nil && !ValidSensitivity(*req.Sensitivity) {
		return req, fmt.Errorf("invalid sensitivity %q", *req.Sensitivity)
	}
	if req.Status != nil && !ValidStatus(*req.Status) {
		return req, fmt.Errorf("invalid status %q", *req.Status)
	}
	req.Subjects = NormalizeStrings(req.Subjects)
	req.Topics = NormalizeStrings(req.Topics)
	req.EntityNames = NormalizeStrings(req.EntityNames)
	return req, nil
}

// NormalizeCorrectionRequest validates a user correction.
func NormalizeCorrectionRequest(req CorrectionRequest) (CorrectionRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "agent")
	req.Text = strings.TrimSpace(req.Text)
	if req.MemoryID == "" {
		return req, errors.New("memory_id is required")
	}
	if req.Text == "" {
		return req, errors.New("correction text is required")
	}
	if req.Scope == "" {
		req.Scope = ScopeUser
	}
	if !ValidScope(req.Scope) {
		return req, fmt.Errorf("invalid scope %q", req.Scope)
	}
	return req, nil
}

// NormalizeRefreshPageRequest validates a compiled page refresh request.
func NormalizeRefreshPageRequest(req RefreshPageRequest) (RefreshPageRequest, error) {
	req.Actor = normalizeDefault(req.Actor, "agent")
	if req.Kind == "" {
		req.Kind = KindEntityPage
	}
	if req.Kind != KindEntityPage && req.Kind != KindTimeline {
		return req, fmt.Errorf("unsupported page kind %q", req.Kind)
	}
	if req.Scope == "" {
		req.Scope = ScopeUser
	}
	if !ValidScope(req.Scope) {
		return req, fmt.Errorf("invalid scope %q", req.Scope)
	}
	req.Title = strings.TrimSpace(req.Title)
	req.Topic = strings.TrimSpace(req.Topic)
	if req.Title == "" && req.EntityID == "" && req.Topic == "" {
		return req, errors.New("title, entity_id, or topic is required")
	}
	return req, nil
}

// NormalizeStrings trims, lowercases, deduplicates, and removes blanks.
func NormalizeStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	normalized := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.ToLower(strings.TrimSpace(value))
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		normalized = append(normalized, value)
	}
	return normalized
}

// ValidKind reports whether kind is in the controlled vocabulary.
func ValidKind(kind Kind) bool {
	switch kind {
	case KindConversation, KindDocument, KindToolOutput, KindArtifact, KindSummary, KindEntityPage, KindTimeline, KindProfileFact:
		return true
	default:
		return false
	}
}

// ValidScope reports whether scope is in the controlled vocabulary.
func ValidScope(scope Scope) bool {
	switch scope {
	case ScopeSession, ScopeUser, ScopeHousehold, ScopeTenant, ScopeProject, ScopeGlobal:
		return true
	default:
		return false
	}
}

// ValidTrustLevel reports whether level is in the controlled vocabulary.
func ValidTrustLevel(level TrustLevel) bool {
	switch level {
	case TrustSourceOriginal, TrustUserAsserted, TrustModelExtracted, TrustModelSynthesized, TrustExternallyVerified:
		return true
	default:
		return false
	}
}

// ValidSensitivity reports whether sensitivity is in the controlled vocabulary.
func ValidSensitivity(sensitivity Sensitivity) bool {
	switch sensitivity {
	case SensitivityPublic, SensitivityInternal, SensitivityPrivate, SensitivityRestricted:
		return true
	default:
		return false
	}
}

// ValidStatus reports whether status is in the controlled vocabulary.
func ValidStatus(status Status) bool {
	switch status {
	case StatusActive, StatusSuperseded, StatusDeprecated, StatusArchived:
		return true
	default:
		return false
	}
}

// ValidRelationshipType reports whether relationship type is controlled.
func ValidRelationshipType(rel RelationshipType) bool {
	switch rel {
	case RelationshipGeneratedBy, RelationshipRefersTo, RelationshipSupersedes, RelationshipContradicts, RelationshipDuplicates, RelationshipRelatedToEvent:
		return true
	default:
		return false
	}
}

// normalizeDefault trims a value and substitutes a default when blank.
func normalizeDefault(value string, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback
	}
	return value
}
