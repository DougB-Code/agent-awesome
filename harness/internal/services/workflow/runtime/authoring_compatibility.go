// This file handles authoring-time edge compatibility and adapter choices.
package runtime

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/compatibility"
	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/store"
)

// CheckDraftEdgeCompatibility evaluates a prospective edge in an editable draft.
func (s *Service) CheckDraftEdgeCompatibility(ctx context.Context, id string, req EdgeCompatibilityRequest) (EdgeCompatibilityResult, error) {
	draft, err := s.store.GetDraft(ctx, strings.TrimSpace(id))
	if err != nil {
		return EdgeCompatibilityResult{}, err
	}
	def, validation := s.compileDraftRecord(draft)
	if !validation.Valid {
		return EdgeCompatibilityResult{}, fmt.Errorf("workflow draft is invalid")
	}
	source, ok := nodeByID(def.Nodes, req.SourceNodeID)
	if !ok {
		return EdgeCompatibilityResult{}, fmt.Errorf("source node %q is not defined", req.SourceNodeID)
	}
	target, ok := nodeByID(def.Nodes, req.TargetNodeID)
	if !ok {
		return EdgeCompatibilityResult{}, fmt.Errorf("target node %q is not defined", req.TargetNodeID)
	}
	adapter := req.Adapter
	if !adapters.Declared(adapter) {
		adapter = edgeAdapter(def, source.ID, target.ID)
	}
	sourceManifest := manifestForNode(source)
	targetManifest := manifestForNode(target)
	engine, reusableAdapters, err := s.compatibilityEngine(ctx)
	if err != nil {
		return EdgeCompatibilityResult{}, err
	}
	result := engine.Check(sourceManifest, targetManifest, adapter)
	suggested := adapters.Definition{}
	if !adapters.Declared(adapter) {
		if strings.TrimSpace(result.AdapterRef) != "" {
			suggested = reusableAdapters[strings.TrimSpace(result.AdapterRef)]
		} else {
			suggested = compatibility.SuggestAdapter(sourceManifest, targetManifest, result)
		}
	}
	return EdgeCompatibilityResult{
		SourceNodeID:     source.ID,
		TargetNodeID:     target.ID,
		Source:           sourceManifest,
		Target:           targetManifest,
		Compatibility:    result,
		SuggestedAdapter: suggested,
	}, nil
}

// SaveAdapterChoice persists one user-confirmed adapter decision.
func (s *Service) SaveAdapterChoice(ctx context.Context, req AdapterChoiceRequest) (AdapterChoiceResult, error) {
	draftID := strings.TrimSpace(req.DraftID)
	if draftID == "" {
		return AdapterChoiceResult{}, fmt.Errorf("draft id is required")
	}
	draft, err := s.store.GetDraft(ctx, draftID)
	if err != nil {
		return AdapterChoiceResult{}, err
	}
	def, validation := s.compileDraftRecord(draft)
	if !validation.Valid {
		return AdapterChoiceResult{}, fmt.Errorf("workflow draft is invalid")
	}
	source, ok := nodeByID(def.Nodes, req.SourceNodeID)
	if !ok {
		return AdapterChoiceResult{}, fmt.Errorf("source node %q is not defined", req.SourceNodeID)
	}
	target, ok := nodeByID(def.Nodes, req.TargetNodeID)
	if !ok {
		return AdapterChoiceResult{}, fmt.Errorf("target node %q is not defined", req.TargetNodeID)
	}
	sourceManifest := manifestForNode(source)
	targetManifest := manifestForNode(target)
	baseResult := compatibility.NewEngine().Check(sourceManifest, targetManifest, adapters.Definition{})
	adapter := req.Adapter
	if !adapters.Declared(adapter) {
		selected, err := selectedCompatibilityChoices(baseResult.Choices, req.ChoiceIDs)
		if err != nil {
			return AdapterChoiceResult{}, err
		}
		if len(selected) > 0 {
			adapter = compatibility.AdapterForChoices(sourceManifest, targetManifest, selected)
		} else {
			adapter = compatibility.SuggestAdapter(sourceManifest, targetManifest, baseResult)
		}
	}
	if !adapters.Declared(adapter) {
		return AdapterChoiceResult{}, fmt.Errorf("adapter choice requires an explicit adapter or selected compatibility choice")
	}
	artifactBody, err := mapFromJSON(AdapterArtifact{
		SourceTool:   sourceManifest.ID,
		TargetTool:   targetManifest.ID,
		SourceNodeID: source.ID,
		TargetNodeID: target.ID,
		ChoiceIDs:    append([]string(nil), req.ChoiceIDs...),
		Adapter:      adapter,
	})
	if err != nil {
		return AdapterChoiceResult{}, fmt.Errorf("encode adapter choice artifact: %w", err)
	}
	record, err := s.designArtifactRecord(DesignArtifact{
		ID:   req.ID,
		Kind: "adapter",
		Name: req.Name,
		Body: artifactBody,
	})
	if err != nil {
		return AdapterChoiceResult{}, err
	}
	if err := s.store.UpsertDesignArtifact(ctx, record); err != nil {
		return AdapterChoiceResult{}, err
	}
	return AdapterChoiceResult{Artifact: record, Adapter: adapter, Compatibility: baseResult}, nil
}

// nodeByID finds one node by id.
func nodeByID(nodes []definition.NodeDefinition, id string) (definition.NodeDefinition, bool) {
	for _, node := range nodes {
		if strings.TrimSpace(node.ID) == strings.TrimSpace(id) {
			return node, true
		}
	}
	return definition.NodeDefinition{}, false
}

// edgeAdapter returns the adapter already authored for a source-target pair.
func edgeAdapter(def definition.Definition, sourceID string, targetID string) adapters.Definition {
	for _, edge := range def.Edges {
		if strings.TrimSpace(edge.From.Node) == strings.TrimSpace(sourceID) &&
			strings.TrimSpace(edge.To.Node) == strings.TrimSpace(targetID) {
			return edge.Adapter
		}
	}
	return adapters.Definition{}
}

// compatibilityEngine loads persisted reusable adapters into a fresh engine.
func (s *Service) compatibilityEngine(ctx context.Context) (*compatibility.Engine, map[string]adapters.Definition, error) {
	engine := compatibility.NewEngine()
	reusable := map[string]adapters.Definition{}
	records, err := s.store.ListDesignArtifacts(ctx)
	if err != nil {
		return nil, nil, err
	}
	for _, record := range records {
		artifact, ok, err := adapterArtifactFromRecord(record)
		if err != nil {
			return nil, nil, err
		}
		if !ok {
			continue
		}
		engine.RegisterAdapter(artifact.SourceTool, artifact.TargetTool, record.ID)
		reusable[record.ID] = artifact.Adapter
	}
	return engine, reusable, nil
}

// adapterArtifactFromRecord decodes adapter design artifacts.
func adapterArtifactFromRecord(record store.DesignArtifactRecord) (AdapterArtifact, bool, error) {
	if strings.TrimSpace(record.Kind) != "adapter" {
		return AdapterArtifact{}, false, nil
	}
	encoded, err := json.Marshal(record.Body)
	if err != nil {
		return AdapterArtifact{}, false, fmt.Errorf("encode adapter artifact %q: %w", record.ID, err)
	}
	var artifact AdapterArtifact
	if err := json.Unmarshal(encoded, &artifact); err != nil {
		return AdapterArtifact{}, false, fmt.Errorf("decode adapter artifact %q: %w", record.ID, err)
	}
	return artifact, true, nil
}

// selectedCompatibilityChoices resolves user-selected compatibility choice ids.
func selectedCompatibilityChoices(available []contracts.CompatibilityChoice, ids []string) ([]contracts.CompatibilityChoice, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	availableByID := map[string]contracts.CompatibilityChoice{}
	for _, choice := range available {
		availableByID[strings.TrimSpace(choice.ID)] = choice
	}
	selected := make([]contracts.CompatibilityChoice, 0, len(ids))
	for _, id := range ids {
		trimmed := strings.TrimSpace(id)
		choice, ok := availableByID[trimmed]
		if !ok {
			return nil, fmt.Errorf("compatibility choice %q is not available", trimmed)
		}
		selected = append(selected, choice)
	}
	return selected, nil
}
