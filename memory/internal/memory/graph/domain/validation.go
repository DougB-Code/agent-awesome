package domain

import (
	"errors"
	"fmt"
	"strings"

	"memory/internal/memory/normalize"
	"memory/internal/memory/vocabulary"
)

// NormalizeUpsertNodeRequest validates and defaults a node write.
func NormalizeUpsertNodeRequest(req UpsertNodeRequest) (UpsertNodeRequest, error) {
	req.StableKey = strings.TrimSpace(req.StableKey)
	req.Title = strings.TrimSpace(req.Title)
	req.Summary = strings.TrimSpace(req.Summary)
	req.Actor = normalize.Default(req.Actor, DefaultActor)
	if !ValidNodeKind(req.Kind) {
		return req, fmt.Errorf("invalid node kind %q", req.Kind)
	}
	req.Status = vocabulary.DefaultLifecycleStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid node status %q", req.Status)
	}
	req.Firewall = vocabulary.DefaultFirewall(req.Firewall)
	if !ValidFirewall(req.Firewall) {
		return req, fmt.Errorf("invalid firewall %q", req.Firewall)
	}
	req.Sensitivity = vocabulary.DefaultSensitivity(req.Sensitivity)
	if !ValidSensitivity(req.Sensitivity) {
		return req, fmt.Errorf("invalid sensitivity %q", req.Sensitivity)
	}
	req.TrustLevel = vocabulary.DefaultTrustLevel(req.TrustLevel, TrustUserAsserted)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	req.Confidence = defaultConfidence(req.Confidence)
	return req, nil
}

// NormalizeUpsertEdgeRequest validates and defaults an edge write.
func NormalizeUpsertEdgeRequest(req UpsertEdgeRequest) (UpsertEdgeRequest, error) {
	req.Actor = normalize.Default(req.Actor, DefaultActor)
	if req.FromNodeID == "" {
		return req, errors.New("from_node_id is required")
	}
	if req.ToNodeID == "" {
		return req, errors.New("to_node_id is required")
	}
	if !ValidRelationType(req.Type) {
		return req, fmt.Errorf("invalid relation type %q", req.Type)
	}
	req.Status = vocabulary.DefaultLifecycleStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid edge status %q", req.Status)
	}
	req.TrustLevel = vocabulary.DefaultTrustLevel(req.TrustLevel, TrustUserAsserted)
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
	req.Key = normalize.Key(req.Key)
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
	req.Key = normalize.Key(req.Key)
	if req.Key == "" {
		return req, errors.New("property key is required")
	}
	req.Actor = normalize.Default(req.Actor, DefaultActor)
	req.Status = vocabulary.DefaultLifecycleStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid property status %q", req.Status)
	}
	req.TrustLevel = vocabulary.DefaultTrustLevel(req.TrustLevel, TrustUserAsserted)
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
	req.Locale = normalize.Key(req.Locale)
	req.Alias = strings.TrimSpace(req.Alias)
	if req.Alias == "" {
		return req, errors.New("alias is required")
	}
	req.Kind = normalize.Default(req.Kind, "name")
	return req, nil
}

// NormalizeWriteEvidenceBlobRequest validates and defaults a source blob write.
func NormalizeWriteEvidenceBlobRequest(req WriteEvidenceBlobRequest) (WriteEvidenceBlobRequest, error) {
	if req.NodeID == "" {
		return req, errors.New("node_id is required")
	}
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		return req, errors.New("content is required")
	}
	req.MediaType = normalize.Default(req.MediaType, "text/plain; charset=utf-8")
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
	req.Kind = normalize.Key(req.Kind)
	if req.Kind == "" {
		return req, errors.New("audit kind is required")
	}
	req.Actor = normalize.Default(req.Actor, DefaultActor)
	req.Message = strings.TrimSpace(req.Message)
	req.DetailsJSON = strings.TrimSpace(req.DetailsJSON)
	return req, nil
}

// NormalizeSearchNodesQuery validates and defaults a lexical graph search.
func NormalizeSearchNodesQuery(q SearchNodesQuery) (SearchNodesQuery, error) {
	q.Text = strings.TrimSpace(q.Text)
	policy, err := NormalizeAccessPolicy(AccessPolicy{
		Firewall:             q.Firewall,
		IncludeGlobal:        q.IncludeGlobal,
		AllowedSensitivities: q.AllowedSensitivities,
	})
	if err != nil {
		return q, err
	}
	q.Firewall = policy.Firewall
	q.IncludeGlobal = policy.IncludeGlobal
	q.AllowedSensitivities = policy.AllowedSensitivities
	for _, kind := range q.Kinds {
		if !ValidNodeKind(kind) {
			return q, fmt.Errorf("invalid node kind %q", kind)
		}
	}
	if q.Limit <= 0 || q.Limit > 100 {
		q.Limit = 20
	}
	return q, nil
}

// NormalizeAccessPolicy validates and defaults shared graph boundary metadata.
func NormalizeAccessPolicy(policy AccessPolicy) (AccessPolicy, error) {
	policy.Actor = normalize.Default(policy.Actor, DefaultActor)
	policy.Firewall = vocabulary.DefaultFirewall(policy.Firewall)
	if !ValidFirewall(policy.Firewall) {
		return policy, fmt.Errorf("invalid firewall %q", policy.Firewall)
	}
	if len(policy.AllowedSensitivities) == 0 {
		policy.AllowedSensitivities = DefaultReadableSensitivities()
	}
	for _, sensitivity := range policy.AllowedSensitivities {
		if !ValidSensitivity(sensitivity) {
			return policy, fmt.Errorf("invalid sensitivity %q", sensitivity)
		}
	}
	return policy, nil
}

// DefaultReadableSensitivities returns graph sensitivities allowed by default.
func DefaultReadableSensitivities() []Sensitivity {
	return vocabulary.DefaultReadableSensitivities()
}

// ValidNodeKind reports whether kind is in the controlled vocabulary.
func ValidNodeKind(kind NodeKind) bool {
	switch kind {
	case KindArtifact, KindEvidence, KindEntity, KindEvent, KindList, KindLocation, KindMemory, KindPerson, KindProject, KindRequirement, KindRisk, KindSource, KindTask, KindTopic:
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
	return vocabulary.ValidLifecycleStatus(status)
}

// ValidFirewall reports whether firewall is a safe memory firewall id.
func ValidFirewall(firewall Firewall) bool {
	return vocabulary.ValidFirewall(firewall)
}

// ValidSensitivity reports whether sensitivity is in the controlled vocabulary.
func ValidSensitivity(sensitivity Sensitivity) bool {
	return vocabulary.ValidSensitivity(sensitivity)
}

// ValidTrustLevel reports whether trust is in the controlled vocabulary.
func ValidTrustLevel(trust TrustLevel) bool {
	return vocabulary.ValidTrustLevel(trust)
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
	req.Actor = normalize.Default(req.Actor, DefaultActor)
	req.Status = vocabulary.DefaultLifecycleStatus(req.Status)
	if !ValidLifecycleStatus(req.Status) {
		return req, fmt.Errorf("invalid property status %q", req.Status)
	}
	req.TrustLevel = vocabulary.DefaultTrustLevel(req.TrustLevel, TrustUserAsserted)
	if !ValidTrustLevel(req.TrustLevel) {
		return req, fmt.Errorf("invalid trust level %q", req.TrustLevel)
	}
	if !ValidValue(req.Value) {
		return req, fmt.Errorf("invalid property value type %q", req.Value.Type)
	}
	req.Confidence = defaultConfidence(req.Confidence)
	return req, nil
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
