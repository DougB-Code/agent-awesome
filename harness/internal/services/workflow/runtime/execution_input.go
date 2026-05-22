// This file builds pipe-node inputs and resolves reusable mappings.
package runtime

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/envelope"
	"agentawesome/internal/services/workflow/mapping"
	"agentawesome/internal/services/workflow/store"
)

// pipeNodeInput builds the deterministic envelope input for one graph node.
func (s *Service) pipeNodeInput(ctx context.Context, def definition.Definition, run store.RunRecord, node definition.NodeDefinition, attempt int) (envelope.Envelope, error) {
	incoming := incomingEdges(def, node.ID)
	if len(incoming) == 0 {
		env := envelope.New(run.ID, node.ID, attempt, run.Input)
		env.Control.Status = envelope.StatusSucceeded
		return env, nil
	}
	records, err := s.store.ListNodeStates(ctx, run.ID)
	if err != nil {
		return envelope.Envelope{}, err
	}
	incoming, err = s.pipeActiveIncomingEdges(ctx, def, run.ID, node.ID, nodeStatusByID(records))
	if err != nil {
		return envelope.Envelope{}, err
	}
	if len(incoming) == 0 {
		return envelope.Envelope{}, fmt.Errorf("node %q has no active incoming edges", node.ID)
	}
	var merged envelope.Envelope
	for index, edge := range incoming {
		sourceMap, ok, err := s.store.StepOutput(ctx, run.ID, edge.From.Node)
		if err != nil {
			return envelope.Envelope{}, err
		}
		if !ok {
			return envelope.Envelope{}, fmt.Errorf("source node %q output is missing", edge.From.Node)
		}
		source := envelope.FromMap(sourceMap)
		adapted, diagnostics := adapters.Apply(edge.Adapter, source, s)
		if err := envelopeDiagnosticsError("adapter", diagnostics); err != nil {
			return envelope.Envelope{}, err
		}
		_ = s.appendEvent(ctx, run.ID, "edge_adapter_applied", "workflow edge adapter applied", map[string]any{
			"from_node":   edge.From.Node,
			"from_port":   edge.From.Port,
			"to_node":     edge.To.Node,
			"to_port":     edge.To.Port,
			"adapter":     adapterEventData(edge.Adapter),
			"mapping_ref": edge.Adapter.MappingRef,
		})
		adapted.Meta.WorkflowRunID = run.ID
		adapted.Meta.NodeRunID = node.ID
		adapted.Meta.Attempt = attempt
		if index == 0 && len(incoming) == 1 && edgeTargetPort(edge) == "input" {
			adapted.AddProvenance(edge.From.Node, edgeTargetPort(edge), adapted.Body.Value)
			adapted.Normalize()
			return adapted, nil
		}
		if index == 0 {
			merged = envelope.Empty(run.ID, node.ID, attempt)
			merged.Body.Kind = envelope.BodyKindObject
			merged.Body.Value = map[string]any{}
		}
		merged.MergeFrom(adapted, edgeTargetPort(edge))
		merged.AddProvenance(edge.From.Node, edgeTargetPort(edge), adapted.Body.Value)
	}
	merged.Normalize()
	return merged, nil
}

// Mapping resolves a named mapping spec for edge adapters.
func (s *Service) Mapping(name string) (mapping.Spec, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, def := range s.defs {
		for _, spec := range def.Mappings {
			if strings.TrimSpace(spec.Name) == strings.TrimSpace(name) {
				return spec, true
			}
		}
	}
	return mapping.Spec{}, false
}

// adapterEventData returns stable adapter metadata for audit events.
func adapterEventData(adapter adapters.Definition) map[string]any {
	data := map[string]any{
		"kind":      strings.TrimSpace(adapter.Kind),
		"strategy":  strings.TrimSpace(adapter.Strategy),
		"operation": strings.TrimSpace(adapter.Operation),
		"source":    strings.TrimSpace(adapter.Source),
		"target":    strings.TrimSpace(adapter.Target),
	}
	if adapter.Mapping != nil {
		data["mapping_name"] = strings.TrimSpace(adapter.Mapping.Name)
		data["mapping_api_version"] = strings.TrimSpace(adapter.Mapping.APIVersion)
	}
	return data
}
