// This file records and exposes runtime-observed output contract shapes.
package runtime

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/envelope"
	"agentawesome/internal/services/workflow/store"
)

const defaultObservedContractReviewThreshold = 3

// ObservedContractQuery selects runtime-observed output contracts for review.
type ObservedContractQuery struct {
	DefinitionID string `json:"definition_id"`
	NodeID       string `json:"node_id,omitempty"`
	ToolID       string `json:"tool_id,omitempty"`
	Limit        int    `json:"limit,omitempty"`
}

// ObservedContract describes a runtime-observed shape and whether it is review-ready.
type ObservedContract struct {
	DefinitionID      string           `json:"definition_id"`
	NodeID            string           `json:"node_id"`
	ToolID            string           `json:"tool_id"`
	ShapeHash         string           `json:"shape_hash"`
	Occurrences       int              `json:"occurrences"`
	Contract          map[string]any   `json:"contract"`
	ObservedFields    []map[string]any `json:"observed_fields"`
	ReviewRecommended bool             `json:"review_recommended"`
	FirstSeenAt       string           `json:"first_seen_at"`
	LastSeenAt        string           `json:"last_seen_at"`
}

// ListObservedContracts returns runtime-learned output contract shapes.
func (s *Service) ListObservedContracts(ctx context.Context, query ObservedContractQuery) ([]ObservedContract, error) {
	records, err := s.store.ListObservedContracts(ctx, store.ObservedContractFilter{
		DefinitionID: query.DefinitionID,
		NodeID:       query.NodeID,
		ToolID:       query.ToolID,
		Limit:        query.Limit,
	})
	if err != nil {
		return nil, err
	}
	out := make([]ObservedContract, 0, len(records))
	threshold := s.observedContractReviewThreshold()
	for _, record := range records {
		out = append(out, ObservedContract{
			DefinitionID:      record.DefinitionID,
			NodeID:            record.NodeID,
			ToolID:            record.ToolID,
			ShapeHash:         record.ShapeHash,
			Occurrences:       record.Occurrences,
			Contract:          record.Contract,
			ObservedFields:    record.ObservedFields,
			ReviewRecommended: record.Occurrences >= threshold,
			FirstSeenAt:       record.FirstSeenAt,
			LastSeenAt:        record.LastSeenAt,
		})
	}
	return out, nil
}

// recordObservedContract persists an inferred output contract for a successful node.
func (s *Service) recordObservedContract(ctx context.Context, def definition.Definition, node definition.NodeDefinition, output envelope.Envelope) error {
	output.Normalize()
	sample := observedOutputSample(output)
	inferred, observed := contracts.InferObservedContract([]map[string]any{sample})
	inferred.Produces = observedCarriers(output)
	inferred.Facets = mergeObservedFacets(inferred.Facets, output.Facets)
	inferred.Examples = []contracts.Example{{
		Name:        "observed-" + strings.TrimSpace(node.ID),
		OutputShape: sample,
	}}
	contractBody, err := mapFromJSON(inferred)
	if err != nil {
		return fmt.Errorf("encode inferred observed contract: %w", err)
	}
	observedFields, err := observedFieldsFromJSON(observed)
	if err != nil {
		return err
	}
	hash, err := observedShapeHash(contractBody)
	if err != nil {
		return err
	}
	return s.store.UpsertObservedContract(ctx, store.ObservedContractRecord{
		DefinitionID:   strings.TrimSpace(def.ID),
		NodeID:         strings.TrimSpace(node.ID),
		ToolID:         manifestForNode(node).ID,
		ShapeHash:      hash,
		Occurrences:    1,
		Contract:       contractBody,
		ObservedFields: observedFields,
	})
}

// observedContractReviewThreshold returns the occurrence count for review suggestions.
func (s *Service) observedContractReviewThreshold() int {
	if s.cfg.ObservedContractReviewThreshold > 0 {
		return s.cfg.ObservedContractReviewThreshold
	}
	return defaultObservedContractReviewThreshold
}

// observedOutputSample returns a stable sample map for inference.
func observedOutputSample(output envelope.Envelope) map[string]any {
	switch value := output.Body.Value.(type) {
	case nil:
		return map[string]any{}
	case map[string]any:
		return cloneMap(value)
	case []any:
		return map[string]any{"items": value}
	default:
		return map[string]any{"value": value}
	}
}

// observedCarriers derives produced carrier metadata from the output envelope.
func observedCarriers(output envelope.Envelope) []contracts.Carrier {
	carrier := contracts.Carrier{Kind: strings.TrimSpace(output.Body.Kind)}
	mediaTypes := map[string]struct{}{}
	for _, artifact := range output.Artifacts {
		if mediaType := strings.TrimSpace(artifact.MediaType); mediaType != "" {
			mediaTypes[mediaType] = struct{}{}
		}
	}
	for mediaType := range mediaTypes {
		carrier.MediaTypes = append(carrier.MediaTypes, mediaType)
	}
	sort.Strings(carrier.MediaTypes)
	return []contracts.Carrier{carrier}
}

// mergeObservedFacets combines inferred and emitted facet names.
func mergeObservedFacets(inferred []string, facets map[string]any) []string {
	set := map[string]struct{}{}
	for _, facet := range inferred {
		if trimmed := strings.TrimSpace(facet); trimmed != "" {
			set[trimmed] = struct{}{}
		}
	}
	for facet := range facets {
		if trimmed := strings.TrimSpace(facet); trimmed != "" {
			set[trimmed] = struct{}{}
		}
	}
	out := make([]string, 0, len(set))
	for facet := range set {
		out = append(out, facet)
	}
	sort.Strings(out)
	return out
}

// observedFieldsFromJSON converts inferred fields into map form for storage.
func observedFieldsFromJSON(fields []contracts.ObservedField) ([]map[string]any, error) {
	encoded, err := json.Marshal(fields)
	if err != nil {
		return nil, fmt.Errorf("encode observed fields: %w", err)
	}
	var out []map[string]any
	if err := json.Unmarshal(encoded, &out); err != nil {
		return nil, fmt.Errorf("decode observed fields: %w", err)
	}
	return out, nil
}

// observedShapeHash returns a stable hash for one inferred contract body.
func observedShapeHash(contract map[string]any) (string, error) {
	canonical := cloneMap(contract)
	delete(canonical, "examples")
	encoded, err := json.Marshal(canonical)
	if err != nil {
		return "", fmt.Errorf("encode observed contract hash: %w", err)
	}
	sum := sha256.Sum256(encoded)
	return "sha256:" + hex.EncodeToString(sum[:]), nil
}
