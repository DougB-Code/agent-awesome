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
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
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
	domainID, err := NormalizeDomainID(req.DomainID, req.Firewall)
	if err != nil {
		return req, err
	}
	req.DomainID = domainID
	req.Firewall = domainID
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
	q.Actor = normalize.Default(q.Actor, vocabulary.DefaultAgentActor)
	domainID, err := NormalizeDomainID(q.DomainID, q.Firewall)
	if err != nil {
		return q, err
	}
	q.DomainID = domainID
	q.Firewall = domainID
	for _, kind := range q.Kinds {
		if !ValidKind(kind) {
			return q, fmt.Errorf("invalid kind %q", kind)
		}
	}
	q.Topics = NormalizeStrings(q.Topics)
	if len(q.AllowedSensitivities) == 0 {
		q.AllowedSensitivities = vocabulary.DefaultReadableSensitivities()
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

// NormalizeOrganizeMemoryRequest fills safe defaults for memory maintenance.
func NormalizeOrganizeMemoryRequest(req OrganizeMemoryRequest) (OrganizeMemoryRequest, error) {
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	domainID, err := NormalizeDomainID(req.DomainID, req.Firewall)
	if err != nil {
		return req, err
	}
	req.DomainID = domainID
	req.Firewall = domainID
	if len(req.AllowedSensitivities) == 0 {
		req.AllowedSensitivities = vocabulary.DefaultReadableSensitivities()
	}
	for _, sensitivity := range req.AllowedSensitivities {
		if !ValidSensitivity(sensitivity) {
			return req, fmt.Errorf("invalid sensitivity %q", sensitivity)
		}
	}
	if req.Limit <= 0 || req.Limit > 100 {
		req.Limit = 50
	}
	return req, nil
}

// NormalizeRepairRequest validates a memory repair request.
func NormalizeRepairRequest(req RepairRequest) (RepairRequest, error) {
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	domainID, err := NormalizeDomainID(req.DomainID, req.Firewall)
	if err != nil {
		return req, err
	}
	req.DomainID = domainID
	req.Firewall = domainID
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
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	req.Text = strings.TrimSpace(req.Text)
	if req.MemoryID == "" {
		return req, errors.New("memory_id is required")
	}
	if req.Text == "" {
		return req, errors.New("correction text is required")
	}
	domainID, err := NormalizeDomainID(req.DomainID, req.Firewall)
	if err != nil {
		return req, err
	}
	req.DomainID = domainID
	req.Firewall = domainID
	return req, nil
}

// NormalizeRefreshPageRequest validates a compiled page refresh request.
func NormalizeRefreshPageRequest(req RefreshPageRequest) (RefreshPageRequest, error) {
	req.Actor = normalize.Default(req.Actor, vocabulary.DefaultAgentActor)
	if req.Kind == "" {
		req.Kind = KindEntityPage
	}
	if req.Kind != KindEntityPage && req.Kind != KindTimeline {
		return req, fmt.Errorf("unsupported page kind %q", req.Kind)
	}
	domainID, err := NormalizeDomainID(req.DomainID, req.Firewall)
	if err != nil {
		return req, err
	}
	req.DomainID = domainID
	req.Firewall = domainID
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

// NormalizeDomainID resolves the canonical routing domain from new and legacy fields.
func NormalizeDomainID(domainID DomainID, legacy Firewall) (DomainID, error) {
	candidate := DomainID(strings.TrimSpace(string(domainID)))
	if candidate == "" {
		candidate = DomainID(strings.TrimSpace(string(legacy)))
	}
	candidate = vocabulary.DefaultFirewall(candidate)
	if !ValidDomainID(candidate) {
		return candidate, fmt.Errorf("invalid memory domain %q", candidate)
	}
	return candidate, nil
}

// ValidDomainID reports whether a memory domain id is safe for routing and storage.
func ValidDomainID(domainID DomainID) bool {
	return vocabulary.ValidFirewall(domainID)
}

// ValidFirewall reports whether firewall is a safe memory firewall id.
func ValidFirewall(firewall Firewall) bool {
	return ValidDomainID(DomainID(firewall))
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
