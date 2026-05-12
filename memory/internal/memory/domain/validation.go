package domain

import (
	"errors"
	"fmt"
	"strings"

	"memory/internal/memory/normalize"
	"memory/internal/memory/vocabulary"
)

// NormalizeCaptureRequest fills conservative defaults and validates a write.
func NormalizeCaptureRequest(req CaptureRequest) (CaptureRequest, error) {
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		return req, errors.New("content is required")
	}
	req.Actor = normalize.Default(req.Actor, "agent")
	req.MediaType = normalize.Default(req.MediaType, "text/plain; charset=utf-8")
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
	req.Firewall = vocabulary.DefaultFirewall(req.Firewall)
	if !ValidFirewall(req.Firewall) {
		return req, fmt.Errorf("invalid firewall %q", req.Firewall)
	}
	req.TrustLevel = vocabulary.DefaultTrustLevel(req.TrustLevel, TrustSourceOriginal)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	req.Sensitivity = vocabulary.DefaultSensitivity(req.Sensitivity)
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
	q.Actor = normalize.Default(q.Actor, "agent")
	q.Firewall = vocabulary.DefaultFirewall(q.Firewall)
	if !ValidFirewall(q.Firewall) {
		return q, fmt.Errorf("invalid firewall %q", q.Firewall)
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
	req.Actor = normalize.Default(req.Actor, "agent")
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
	req.Actor = normalize.Default(req.Actor, "agent")
	req.Text = strings.TrimSpace(req.Text)
	if req.MemoryID == "" {
		return req, errors.New("memory_id is required")
	}
	if req.Text == "" {
		return req, errors.New("correction text is required")
	}
	req.Firewall = vocabulary.DefaultFirewall(req.Firewall)
	if !ValidFirewall(req.Firewall) {
		return req, fmt.Errorf("invalid firewall %q", req.Firewall)
	}
	return req, nil
}

// NormalizeRefreshPageRequest validates a compiled page refresh request.
func NormalizeRefreshPageRequest(req RefreshPageRequest) (RefreshPageRequest, error) {
	req.Actor = normalize.Default(req.Actor, "agent")
	if req.Kind == "" {
		req.Kind = KindEntityPage
	}
	if req.Kind != KindEntityPage && req.Kind != KindTimeline {
		return req, fmt.Errorf("unsupported page kind %q", req.Kind)
	}
	req.Firewall = vocabulary.DefaultFirewall(req.Firewall)
	if !ValidFirewall(req.Firewall) {
		return req, fmt.Errorf("invalid firewall %q", req.Firewall)
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
	return normalize.LowerUnique(values)
}

// ValidKind reports whether kind is in the controlled vocabulary.
func ValidKind(kind Kind) bool {
	return containsVocabularyValue(Kinds(), kind)
}

// ValidFirewall reports whether firewall is a safe memory firewall id.
func ValidFirewall(firewall Firewall) bool {
	return vocabulary.ValidFirewall(firewall)
}

// ValidTrustLevel reports whether level is in the controlled vocabulary.
func ValidTrustLevel(level TrustLevel) bool {
	return vocabulary.ValidTrustLevel(level)
}

// ValidSensitivity reports whether sensitivity is in the controlled vocabulary.
func ValidSensitivity(sensitivity Sensitivity) bool {
	return vocabulary.ValidSensitivity(sensitivity)
}

// ValidStatus reports whether status is in the memory lifecycle vocabulary.
func ValidStatus(status Status) bool {
	return vocabulary.ValidMemoryStatus(status)
}

// ValidRelationshipType reports whether relationship type is controlled.
func ValidRelationshipType(rel RelationshipType) bool {
	return containsVocabularyValue(RelationshipTypes(), rel)
}
