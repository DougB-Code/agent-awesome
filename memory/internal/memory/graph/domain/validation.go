package domain

import (
	"errors"
	"fmt"
	"strings"
)

// NormalizeUpsertNodeRequest validates and defaults a node write.
func NormalizeUpsertNodeRequest(req UpsertNodeRequest) (UpsertNodeRequest, error) {
	req.StableKey = strings.TrimSpace(req.StableKey)
	req.Title = strings.TrimSpace(req.Title)
	req.Summary = strings.TrimSpace(req.Summary)
	req.Actor = defaultString(req.Actor, "agent")
	if !ValidNodeKind(req.Kind) {
		return req, fmt.Errorf("invalid node kind %q", req.Kind)
	}
	req.Status = defaultStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid node status %q", req.Status)
	}
	req.Scope = defaultScope(req.Scope)
	if !ValidScope(req.Scope) {
		return req, fmt.Errorf("invalid scope %q", req.Scope)
	}
	req.Sensitivity = defaultSensitivity(req.Sensitivity)
	if !ValidSensitivity(req.Sensitivity) {
		return req, fmt.Errorf("invalid sensitivity %q", req.Sensitivity)
	}
	req.TrustLevel = defaultTrustLevel(req.TrustLevel)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	req.Confidence = defaultConfidence(req.Confidence)
	return req, nil
}

// NormalizeUpsertEdgeRequest validates and defaults an edge write.
func NormalizeUpsertEdgeRequest(req UpsertEdgeRequest) (UpsertEdgeRequest, error) {
	req.Actor = defaultString(req.Actor, "agent")
	if req.FromNodeID == "" {
		return req, errors.New("from_node_id is required")
	}
	if req.ToNodeID == "" {
		return req, errors.New("to_node_id is required")
	}
	if !ValidRelationType(req.Type) {
		return req, fmt.Errorf("invalid relation type %q", req.Type)
	}
	req.Status = defaultStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid edge status %q", req.Status)
	}
	req.TrustLevel = defaultTrustLevel(req.TrustLevel)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	req.Confidence = defaultConfidence(req.Confidence)
	return req, nil
}

// NormalizeUpsertNodePropertyRequest validates and defaults a node property write.
func NormalizeUpsertNodePropertyRequest(req UpsertNodePropertyRequest) (UpsertNodePropertyRequest, error) {
	if req.NodeID == "" {
		return req, errors.New("node_id is required")
	}
	req.Key = normalizeKey(req.Key)
	if req.Key == "" {
		return req, errors.New("property key is required")
	}
	return normalizePropertyFields(req)
}

// NormalizeUpsertEdgePropertyRequest validates and defaults an edge property write.
func NormalizeUpsertEdgePropertyRequest(req UpsertEdgePropertyRequest) (UpsertEdgePropertyRequest, error) {
	if req.EdgeID == "" {
		return req, errors.New("edge_id is required")
	}
	req.Key = normalizeKey(req.Key)
	if req.Key == "" {
		return req, errors.New("property key is required")
	}
	req.Actor = defaultString(req.Actor, "agent")
	req.Status = defaultStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid property status %q", req.Status)
	}
	req.TrustLevel = defaultTrustLevel(req.TrustLevel)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	if !ValidValue(req.Value) {
		return req, fmt.Errorf("invalid property value type %q", req.Value.Type)
	}
	req.Confidence = defaultConfidence(req.Confidence)
	return req, nil
}

// NormalizeUpsertAliasRequest validates and defaults an alias write.
func NormalizeUpsertAliasRequest(req UpsertAliasRequest) (UpsertAliasRequest, error) {
	if req.NodeID == "" {
		return req, errors.New("node_id is required")
	}
	req.Locale = strings.ToLower(strings.TrimSpace(req.Locale))
	req.Alias = strings.TrimSpace(req.Alias)
	if req.Alias == "" {
		return req, errors.New("alias is required")
	}
	req.Kind = defaultString(req.Kind, "name")
	return req, nil
}

// NormalizeWriteEvidenceBlobRequest validates and defaults an evidence blob write.
func NormalizeWriteEvidenceBlobRequest(req WriteEvidenceBlobRequest) (WriteEvidenceBlobRequest, error) {
	if req.NodeID == "" {
		return req, errors.New("node_id is required")
	}
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		return req, errors.New("content is required")
	}
	req.MediaType = defaultString(req.MediaType, "text/plain; charset=utf-8")
	req.SourceSystem = strings.TrimSpace(req.SourceSystem)
	req.SourceID = strings.TrimSpace(req.SourceID)
	if req.SourceNodeID == "" {
		req.SourceNodeID = req.NodeID
	}
	req.Actor = strings.TrimSpace(req.Actor)
	if req.Actor == "" {
		return req, errors.New("actor is required")
	}
	return req, nil
}

// NormalizeAppendAuditRequest validates and defaults an audit append request.
func NormalizeAppendAuditRequest(req AppendAuditRequest) (AppendAuditRequest, error) {
	req.Kind = normalizeKey(req.Kind)
	if req.Kind == "" {
		return req, errors.New("audit kind is required")
	}
	req.Actor = defaultString(req.Actor, "agent")
	req.Message = strings.TrimSpace(req.Message)
	req.DetailsJSON = strings.TrimSpace(req.DetailsJSON)
	return req, nil
}

// NormalizeSearchNodesQuery validates and defaults a lexical graph search.
func NormalizeSearchNodesQuery(q SearchNodesQuery) (SearchNodesQuery, error) {
	q.Text = strings.TrimSpace(q.Text)
	if q.Scope == "" {
		q.Scope = ScopeUser
	}
	if !ValidScope(q.Scope) {
		return q, fmt.Errorf("invalid scope %q", q.Scope)
	}
	for _, kind := range q.Kinds {
		if !ValidNodeKind(kind) {
			return q, fmt.Errorf("invalid node kind %q", kind)
		}
	}
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

// ValidNodeKind reports whether kind is in the controlled vocabulary.
func ValidNodeKind(kind NodeKind) bool {
	switch kind {
	case KindArtifact, KindCommitment, KindEvidence, KindEntity, KindEvent, KindList, KindLocation, KindMemory, KindPerson, KindProject, KindRequirement, KindRisk, KindSource, KindTask, KindTopic:
		return true
	default:
		return false
	}
}

// ValidRelationType reports whether relation is in the controlled vocabulary.
func ValidRelationType(relation RelationType) bool {
	switch relation {
	case RelationAbout, RelationAssignedTo, RelationBlocks, RelationCapturedFrom, RelationContradicts, RelationDependsOn, RelationDerivedFrom, RelationEnables, RelationHasContext, RelationHasRisk, RelationLocatedAt, RelationMaterializedAs, RelationMentions, RelationPartOf, RelationRelatedTo, RelationRefersTo, RelationSourcedFrom, RelationSupersedes, RelationSupportedBy, RelationTaggedWith:
		return true
	default:
		return false
	}
}

// ValidLifecycleStatus reports whether status is in the controlled vocabulary.
func ValidLifecycleStatus(status LifecycleStatus) bool {
	switch status {
	case StatusActive, StatusArchived, StatusDeleted, StatusDeprecated, StatusSuperseded:
		return true
	default:
		return false
	}
}

// ValidScope reports whether scope is in the controlled vocabulary.
func ValidScope(scope Scope) bool {
	switch scope {
	case ScopeGlobal, ScopeHousehold, ScopeProject, ScopeSession, ScopeTenant, ScopeUser:
		return true
	default:
		return false
	}
}

// ValidSensitivity reports whether sensitivity is in the controlled vocabulary.
func ValidSensitivity(sensitivity Sensitivity) bool {
	switch sensitivity {
	case SensitivityInternal, SensitivityPrivate, SensitivityPublic, SensitivityRestricted:
		return true
	default:
		return false
	}
}

// ValidTrustLevel reports whether trust is in the controlled vocabulary.
func ValidTrustLevel(trust TrustLevel) bool {
	switch trust {
	case TrustExternallyVerified, TrustModelExtracted, TrustModelSynthesized, TrustSourceOriginal, TrustUserAsserted:
		return true
	default:
		return false
	}
}

// ValidValue reports whether value has a supported type.
func ValidValue(value Value) bool {
	switch value.Type {
	case ValueBool, ValueJSON, ValueNumber, ValueText, ValueTime:
		return true
	default:
		return false
	}
}

// normalizePropertyFields defaults common node property metadata.
func normalizePropertyFields(req UpsertNodePropertyRequest) (UpsertNodePropertyRequest, error) {
	req.Actor = defaultString(req.Actor, "agent")
	req.Status = defaultStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid property status %q", req.Status)
	}
	req.TrustLevel = defaultTrustLevel(req.TrustLevel)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	if !ValidValue(req.Value) {
		return req, fmt.Errorf("invalid property value type %q", req.Value.Type)
	}
	req.Confidence = defaultConfidence(req.Confidence)
	return req, nil
}

// normalizeKey trims and normalizes a vocabulary key.
func normalizeKey(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

// defaultStatus returns the active lifecycle when status is blank.
func defaultStatus(status LifecycleStatus) LifecycleStatus {
	if status == "" {
		return StatusActive
	}
	return status
}

// defaultScope returns user scope when scope is blank.
func defaultScope(scope Scope) Scope {
	if scope == "" {
		return ScopeUser
	}
	return scope
}

// defaultSensitivity returns private sensitivity when sensitivity is blank.
func defaultSensitivity(sensitivity Sensitivity) Sensitivity {
	if sensitivity == "" {
		return SensitivityPrivate
	}
	return sensitivity
}

// defaultTrustLevel returns user-asserted trust when trust is blank.
func defaultTrustLevel(trust TrustLevel) TrustLevel {
	if trust == "" {
		return TrustUserAsserted
	}
	return trust
}

// defaultConfidence returns full confidence when confidence is omitted.
func defaultConfidence(confidence float64) float64 {
	if confidence <= 0 {
		return 1
	}
	if confidence > 1 {
		return 1
	}
	return confidence
}

// defaultString trims a value and substitutes a fallback when blank.
func defaultString(value string, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback
	}
	return value
}
