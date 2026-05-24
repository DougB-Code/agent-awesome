// This file implements reusable workflow run setups for Operations.
package runtime

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/store"
)

// ListRunSetups returns reusable workflow run setups.
func (s *Service) ListRunSetups(ctx context.Context, query RunSetupQuery) ([]store.RunSetupRecord, error) {
	return s.store.ListRunSetups(ctx, store.RunSetupFilter{
		DefinitionID: query.DefinitionID,
	})
}

// GetRunSetup returns one reusable workflow run setup.
func (s *Service) GetRunSetup(ctx context.Context, id string) (store.RunSetupRecord, error) {
	return s.store.GetRunSetup(ctx, strings.TrimSpace(id))
}

// CreateRunSetup stores one reusable workflow run setup.
func (s *Service) CreateRunSetup(ctx context.Context, req RunSetupRequest) (store.RunSetupRecord, error) {
	record, err := s.runSetupRecordFromRequest(ctx, req, true)
	if err != nil {
		return store.RunSetupRecord{}, err
	}
	if err := s.store.UpsertRunSetup(ctx, record); err != nil {
		return store.RunSetupRecord{}, err
	}
	return s.store.GetRunSetup(ctx, record.ID)
}

// UpdateRunSetup replaces one reusable workflow run setup.
func (s *Service) UpdateRunSetup(ctx context.Context, id string, req RunSetupRequest) (store.RunSetupRecord, error) {
	req.ID = strings.TrimSpace(id)
	record, err := s.runSetupRecordFromRequest(ctx, req, false)
	if err != nil {
		return store.RunSetupRecord{}, err
	}
	existing, err := s.store.GetRunSetup(ctx, record.ID)
	if err != nil {
		return store.RunSetupRecord{}, err
	}
	record.CreatedAt = existing.CreatedAt
	if err := s.store.UpsertRunSetup(ctx, record); err != nil {
		return store.RunSetupRecord{}, err
	}
	return s.store.GetRunSetup(ctx, record.ID)
}

// DeleteRunSetup removes one reusable workflow run setup.
func (s *Service) DeleteRunSetup(ctx context.Context, id string) error {
	return s.store.DeleteRunSetup(ctx, strings.TrimSpace(id))
}

// StartRunSetup starts one workflow run from saved setup input plus run input.
func (s *Service) StartRunSetup(ctx context.Context, id string, input map[string]any) (store.RunRecord, error) {
	setup, err := s.store.GetRunSetup(ctx, strings.TrimSpace(id))
	if err != nil {
		return store.RunRecord{}, err
	}
	return s.StartWorkflow(ctx, setup.DefinitionID, mergeRunSetupInput(setup.Input, input))
}

// runSetupRecordFromRequest normalizes a run setup request into a store record.
func (s *Service) runSetupRecordFromRequest(ctx context.Context, req RunSetupRequest, create bool) (store.RunSetupRecord, error) {
	id := strings.TrimSpace(req.ID)
	if id == "" && create {
		generated, err := randomID("setup")
		if err != nil {
			return store.RunSetupRecord{}, err
		}
		id = generated
	}
	if err := validateAuthoringID(id, "run setup id"); err != nil {
		return store.RunSetupRecord{}, err
	}
	definitionID := strings.TrimSpace(req.DefinitionID)
	if definitionID == "" {
		return store.RunSetupRecord{}, fmt.Errorf("workflow file is required")
	}
	if err := s.syncDefinitionsFromDisk(ctx); err != nil {
		return store.RunSetupRecord{}, err
	}
	if _, ok := s.DescribeDefinition(definitionID); !ok {
		return store.RunSetupRecord{}, fmt.Errorf("workflow definition %q not found", definitionID)
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = definitionID + " setup"
	}
	return store.RunSetupRecord{
		ID:           id,
		DefinitionID: definitionID,
		Name:         name,
		Description:  strings.TrimSpace(req.Description),
		Input:        cloneMap(req.Input),
	}, nil
}

// mergeRunSetupInput overlays one-off run input on top of saved setup input.
func mergeRunSetupInput(setup map[string]any, input map[string]any) map[string]any {
	merged := cloneMap(setup)
	for key, value := range input {
		if nestedInput, ok := value.(map[string]any); ok {
			if nestedSetup, ok := merged[key].(map[string]any); ok {
				merged[key] = mergeRunSetupInput(nestedSetup, nestedInput)
				continue
			}
		}
		merged[key] = value
	}
	return merged
}
