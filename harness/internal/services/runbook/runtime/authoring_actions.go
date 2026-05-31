// This file exposes action catalog data to runbook authoring clients.
package runtime

import (
	"agentawesome/internal/services/runbook/actions"
	"agentawesome/internal/services/runbook/contracts"
)

// ActionTypes returns the registered authoring action catalog.
func (s *Service) ActionTypes() []ActionType {
	names := s.actions.Names()
	types := make([]ActionType, 0, len(names))
	for _, name := range names {
		types = append(types, actionTypeFromMetadata(actions.MetadataFor(name)))
	}
	return types
}

// ActionManifests returns AA-owned manifests for installed action boundaries.
func (s *Service) ActionManifests() []contracts.ToolManifest {
	names := s.actions.Names()
	manifests := make([]contracts.ToolManifest, 0, len(names))
	for _, name := range names {
		manifests = append(manifests, actions.ManifestForMetadata(actions.MetadataFor(name)))
	}
	return manifests
}

// actionTypeFromMetadata converts action metadata into the authoring API DTO.
func actionTypeFromMetadata(meta actions.Metadata) ActionType {
	return ActionType{
		Name:            meta.Name,
		Label:           meta.Label,
		Description:     meta.Description,
		Risk:            meta.Risk,
		Available:       meta.Available,
		InputSchema:     cloneMap(meta.InputSchema),
		OutputSchema:    cloneMap(meta.OutputSchema),
		InputContracts:  append([]string(nil), meta.InputContracts...),
		OutputContracts: append([]string(nil), meta.OutputContracts...),
	}
}
