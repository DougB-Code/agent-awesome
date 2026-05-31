// This file implements runbook authoring operations for the Automations UI.
package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"

	"agentawesome/internal/services/runbook/definition"
	"agentawesome/internal/services/runbook/envelope"
	"agentawesome/internal/services/runbook/mapping"
	"agentawesome/internal/services/runbook/store"
)

const (
	draftStatusDraft      = "draft"
	draftStatusPublished  = "published"
	draftKindRunbook     = "runbook"
	draftKindStateMachine = definition.KindStateMachine
)

var authoringIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// ListRuns returns runbook runs matching operations filters.
func (s *Service) ListRuns(ctx context.Context, query RunQuery) ([]store.RunRecord, error) {
	return s.store.ListRuns(ctx, store.RunFilter{
		Status:       query.Status,
		DefinitionID: query.DefinitionID,
		Limit:        query.Limit,
	})
}

// ListDrafts returns editable runbook drafts.
func (s *Service) ListDrafts(ctx context.Context) ([]store.DraftRecord, error) {
	if err := s.syncDefinitionsFromDisk(ctx); err != nil {
		return nil, err
	}
	return s.store.ListDrafts(ctx)
}

// ensureDraftsForDefinitions mirrors installed definitions into editable drafts.
func (s *Service) ensureDraftsForDefinitions(ctx context.Context, sources []loadedDefinitionDraftSource) error {
	if len(sources) == 0 {
		return nil
	}
	drafts, err := s.store.ListDrafts(ctx)
	if err != nil {
		return err
	}
	draftIDs := map[string]struct{}{}
	definitionIDs := map[string]struct{}{}
	sourceDefinitionIDs := map[string]struct{}{}
	for _, source := range sources {
		if definitionID := strings.TrimSpace(source.definition.ID); definitionID != "" {
			sourceDefinitionIDs[definitionID] = struct{}{}
		}
	}
	for _, draft := range drafts {
		draftIDs[draft.ID] = struct{}{}
		if definitionID := strings.TrimSpace(stringFromMap(draft.Body, "id", "")); definitionID != "" {
			definitionIDs[definitionID] = struct{}{}
			if _, ok := sourceDefinitionIDs[definitionID]; !ok &&
				strings.TrimSpace(draft.Status) == draftStatusPublished &&
				draft.ID == draftIDForDefinition(definitionID) {
				if err := s.store.DeleteDraft(ctx, draft.ID); err != nil {
					return err
				}
				delete(draftIDs, draft.ID)
				delete(definitionIDs, definitionID)
			}
		}
	}
	for _, source := range sources {
		definitionID := strings.TrimSpace(source.definition.ID)
		if definitionID == "" {
			continue
		}
		if _, ok := definitionIDs[definitionID]; ok {
			continue
		}
		draftID := draftIDForDefinition(definitionID)
		if _, ok := draftIDs[draftID]; ok {
			continue
		}
		name := strings.TrimSpace(source.definition.Name)
		if name == "" {
			name = definitionID
		}
		body := cloneMap(source.body)
		body["kind"] = source.definition.Kind
		body["id"] = definitionID
		if strings.TrimSpace(stringFromMap(body, "name", "")) == "" {
			body["name"] = name
		}
		record := store.DraftRecord{
			ID:          draftID,
			Kind:        draftKindForDefinitionKind(source.definition.Kind),
			Name:        name,
			Description: strings.TrimSpace(source.definition.Description),
			Status:      draftStatusPublished,
			Body:        body,
			Validation:  map[string]any{},
		}
		if err := s.store.UpsertDraft(ctx, record); err != nil {
			return err
		}
		draftIDs[draftID] = struct{}{}
		definitionIDs[definitionID] = struct{}{}
	}
	return nil
}

// ensureDraftsForStoredDefinitions remirrors installed definitions when drafts were removed.
func (s *Service) ensureDraftsForStoredDefinitions(ctx context.Context) error {
	records, err := s.store.ListDefinitions(ctx)
	if err != nil {
		return err
	}
	sources := make([]loadedDefinitionDraftSource, 0, len(records))
	for _, record := range records {
		sources = append(sources, loadedDefinitionDraftSource{
			definition: definition.Definition{
				ID:          record.ID,
				Kind:        record.Kind,
				Name:        record.Name,
				Description: strings.TrimSpace(stringFromMap(record.Body, "description", "")),
			},
			body: cloneMap(record.Body),
		})
	}
	return s.ensureDraftsForDefinitions(ctx, sources)
}

// GetDraft returns one editable runbook draft.
func (s *Service) GetDraft(ctx context.Context, id string) (store.DraftRecord, error) {
	return s.store.GetDraft(ctx, strings.TrimSpace(id))
}

// CreateDraft stores a new editable runbook draft.
func (s *Service) CreateDraft(ctx context.Context, req DraftRequest) (store.DraftRecord, error) {
	record, err := s.draftRecordFromRequest(req, true)
	if err != nil {
		return store.DraftRecord{}, err
	}
	if err := s.store.UpsertDraft(ctx, record); err != nil {
		return store.DraftRecord{}, err
	}
	return s.store.GetDraft(ctx, record.ID)
}

// UpdateDraft replaces editable draft fields.
func (s *Service) UpdateDraft(ctx context.Context, id string, req DraftRequest) (store.DraftRecord, error) {
	req.ID = strings.TrimSpace(id)
	record, err := s.draftRecordFromRequest(req, false)
	if err != nil {
		return store.DraftRecord{}, err
	}
	existing, err := s.store.GetDraft(ctx, record.ID)
	if err != nil {
		return store.DraftRecord{}, err
	}
	record.CreatedAt = existing.CreatedAt
	if record.Status == "" {
		record.Status = existing.Status
	}
	if err := s.store.UpsertDraft(ctx, record); err != nil {
		return store.DraftRecord{}, err
	}
	return s.store.GetDraft(ctx, record.ID)
}

// DeleteDraft removes one editable runbook draft.
func (s *Service) DeleteDraft(ctx context.Context, id string) error {
	draftID := strings.TrimSpace(id)
	if draftID == "" {
		return fmt.Errorf("runbook draft id is required")
	}
	if _, err := s.store.GetDraft(ctx, draftID); err != nil {
		return err
	}
	published, ok, err := s.store.GetPublishedDefinitionByDraftID(ctx, draftID)
	if err != nil {
		return err
	}
	if ok {
		if err := s.deletePublishedDefinitionFile(published.Path); err != nil {
			return err
		}
	}
	if err := s.store.DeleteDraft(ctx, draftID); err != nil {
		return err
	}
	if ok {
		if err := s.store.DeletePublishedDefinition(ctx, published.DefinitionID); err != nil {
			return err
		}
		return s.ReloadDefinitions(ctx)
	}
	return nil
}

// deletePublishedDefinitionFile removes a runbook YAML file inside DefinitionsDir.
func (s *Service) deletePublishedDefinitionFile(path string) error {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return nil
	}
	extension := strings.ToLower(filepath.Ext(trimmed))
	if extension != ".yaml" && extension != ".yml" {
		return fmt.Errorf("refusing to delete non-runbook definition file %q", trimmed)
	}
	configuredDir := strings.TrimSpace(s.cfg.DefinitionsDir)
	if configuredDir == "" {
		return fmt.Errorf("runbook definitions directory is required")
	}
	definitionsDir, err := filepath.Abs(configuredDir)
	if err != nil {
		return fmt.Errorf("resolve runbook definitions directory: %w", err)
	}
	targetPath, err := filepath.Abs(trimmed)
	if err != nil {
		return fmt.Errorf("resolve runbook definition path: %w", err)
	}
	relative, err := filepath.Rel(definitionsDir, targetPath)
	if err != nil {
		return fmt.Errorf("compare runbook definition path: %w", err)
	}
	if relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) || filepath.IsAbs(relative) {
		return fmt.Errorf("refusing to delete runbook definition outside definitions directory")
	}
	if err := os.Remove(targetPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("delete runbook definition file %q: %w", targetPath, err)
	}
	return nil
}

// ValidateDraft checks whether a draft can be compiled and published.
func (s *Service) ValidateDraft(ctx context.Context, id string) (ValidationResult, error) {
	draft, err := s.store.GetDraft(ctx, strings.TrimSpace(id))
	if err != nil {
		return ValidationResult{}, err
	}
	result := s.validateDraftRecord(draft)
	validationBody, err := mapFromJSON(result)
	if err != nil {
		return ValidationResult{}, err
	}
	draft.Validation = validationBody
	_ = s.store.UpsertDraft(ctx, draft)
	return result, nil
}

// CompileDraft converts a draft to the canonical runbook YAML shape.
func (s *Service) CompileDraft(ctx context.Context, id string) (CompileResult, error) {
	draft, err := s.store.GetDraft(ctx, strings.TrimSpace(id))
	if err != nil {
		return CompileResult{}, err
	}
	def, validation := s.compileDraftRecord(draft)
	if !validation.Valid {
		return CompileResult{Validation: validation}, fmt.Errorf("runbook draft is invalid")
	}
	yamlBody, err := yaml.Marshal(def)
	if err != nil {
		return CompileResult{}, fmt.Errorf("encode runbook YAML: %w", err)
	}
	return CompileResult{Definition: def, YAML: string(yamlBody), Validation: validation}, nil
}

// PreviewMapping validates and executes a mapping against sample data.
func (s *Service) PreviewMapping(_ context.Context, req MappingPreviewRequest) (mapping.PreviewResult, error) {
	input := envelope.New("preview", "preview_input", 1, cloneMap(req.Input))
	if len(req.Envelope) > 0 {
		input = envelope.FromMap(req.Envelope)
	}
	return mapping.Preview(req.Mapping, input), nil
}

// PublishDraft writes a compiled definition and reloads runbook definitions.
func (s *Service) PublishDraft(ctx context.Context, id string) (store.DefinitionRecord, error) {
	draft, err := s.store.GetDraft(ctx, strings.TrimSpace(id))
	if err != nil {
		return store.DefinitionRecord{}, err
	}
	def, validation := s.compileDraftRecord(draft)
	if !validation.Valid || !validation.Publishable {
		return store.DefinitionRecord{}, fmt.Errorf("runbook draft is not publishable")
	}
	yamlBody, err := yaml.Marshal(def)
	if err != nil {
		return store.DefinitionRecord{}, fmt.Errorf("encode runbook YAML: %w", err)
	}
	if err := os.MkdirAll(s.cfg.DefinitionsDir, 0o700); err != nil {
		return store.DefinitionRecord{}, fmt.Errorf("create runbook definitions directory: %w", err)
	}
	path := filepath.Join(s.cfg.DefinitionsDir, def.ID+".yaml")
	if err := os.WriteFile(path, yamlBody, 0o600); err != nil {
		return store.DefinitionRecord{}, fmt.Errorf("write runbook definition: %w", err)
	}
	if err := s.ReloadDefinitions(ctx); err != nil {
		return store.DefinitionRecord{}, err
	}
	hash := definitionHash(def)
	if err := s.store.UpsertPublishedDefinition(ctx, store.PublishedDefinitionRecord{
		DefinitionID: def.ID,
		DraftID:      draft.ID,
		Path:         path,
		Hash:         hash,
	}); err != nil {
		return store.DefinitionRecord{}, err
	}
	validationBody, _ := mapFromJSON(validation)
	draft.Status = draftStatusPublished
	draft.Validation = validationBody
	_ = s.store.UpsertDraft(ctx, draft)
	defs, err := s.store.ListDefinitions(ctx)
	if err != nil {
		return store.DefinitionRecord{}, err
	}
	for _, record := range defs {
		if record.ID == def.ID {
			return record, nil
		}
	}
	return store.DefinitionRecord{}, fmt.Errorf("published definition %q was not reloaded", def.ID)
}

// draftRecordFromRequest normalizes a user draft request into a store record.
func (s *Service) draftRecordFromRequest(req DraftRequest, create bool) (store.DraftRecord, error) {
	id := strings.TrimSpace(req.ID)
	if id == "" && create {
		generated, err := randomID("draft")
		if err != nil {
			return store.DraftRecord{}, err
		}
		id = generated
	}
	if err := validateAuthoringID(id, "draft id"); err != nil {
		return store.DraftRecord{}, err
	}
	kind := strings.TrimSpace(req.Kind)
	if kind == "" {
		kind = draftKindRunbook
	}
	if kind != draftKindRunbook {
		return store.DraftRecord{}, fmt.Errorf("draft kind must be %q", draftKindRunbook)
	}
	body := cloneMap(req.Body)
	if len(body) == 0 {
		body = blankDefinitionBody(id, req.Name, req.Description)
	}
	bodyKind := strings.TrimSpace(stringFromMap(body, "kind", ""))
	if bodyKind == "" {
		bodyKind = draftKindStateMachine
	}
	if bodyKind != draftKindStateMachine {
		return store.DraftRecord{}, fmt.Errorf("draft body kind must be %q", draftKindStateMachine)
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = stringFromMap(body, "name", id)
	}
	body["kind"] = bodyKind
	if strings.TrimSpace(stringFromMap(body, "id", "")) == "" {
		body["id"] = definitionIDFromDraftID(id)
	}
	if strings.TrimSpace(stringFromMap(body, "name", "")) == "" {
		body["name"] = name
	}
	return store.DraftRecord{
		ID:          id,
		Kind:        kind,
		Name:        name,
		Description: strings.TrimSpace(req.Description),
		Status:      draftStatusDraft,
		Body:        body,
		Validation:  map[string]any{},
	}, nil
}

// validateDraftRecord returns only the validation report for a draft.
func (s *Service) validateDraftRecord(draft store.DraftRecord) ValidationResult {
	_, validation := s.compileDraftRecord(draft)
	return validation
}

// compileDraftRecord converts a draft record to a definition plus diagnostics.
func (s *Service) compileDraftRecord(draft store.DraftRecord) (definition.Definition, ValidationResult) {
	def, err := definitionFromDraft(draft)
	if err != nil {
		return definition.Definition{}, invalidValidation("definition", err)
	}
	if err := definition.Validate(def, s.actions); err != nil {
		return def, invalidValidation("definition", err)
	}
	diagnostics := []ValidationDiagnostic{}
	for _, name := range unavailableActions(def) {
		diagnostics = append(diagnostics, ValidationDiagnostic{
			Severity: "error",
			Path:     "actions." + name,
			Message:  fmt.Sprintf("action %q can be drafted but cannot be published yet", name),
		})
	}
	diagnostics = append(diagnostics, s.capabilityDiagnostics(def)...)
	definitionBody, err := mapFromJSON(def)
	if err != nil {
		return def, invalidValidation("definition", err)
	}
	return def, ValidationResult{
		Valid:       true,
		Publishable: len(diagnostics) == 0,
		Diagnostics: diagnostics,
		Definition:  definitionBody,
	}
}

// definitionFromDraft decodes the canonical definition shape from a draft body.
func definitionFromDraft(draft store.DraftRecord) (definition.Definition, error) {
	body := draft.Body
	if nested, ok := body["definition"].(map[string]any); ok {
		body = nested
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return definition.Definition{}, fmt.Errorf("encode draft body: %w", err)
	}
	var def definition.Definition
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&def); err != nil {
		return definition.Definition{}, fmt.Errorf("decode draft definition: %w", err)
	}
	if strings.TrimSpace(def.ID) == "" {
		def.ID = definitionIDFromDraftID(draft.ID)
	}
	if strings.TrimSpace(def.Kind) == "" {
		def.Kind = draftKindStateMachine
	}
	if strings.TrimSpace(def.Name) == "" {
		def.Name = draft.Name
	}
	def.Authoring = map[string]any{
		"mode":     def.Kind,
		"runbook": cloneMap(body),
	}
	return def, nil
}

// blankDefinitionBody returns a minimal editable state-machine definition body.
func blankDefinitionBody(id string, name string, description string) map[string]any {
	definitionID := definitionIDFromDraftID(id)
	if strings.TrimSpace(name) == "" {
		name = definitionID
	}
	body := map[string]any{
		"kind":        draftKindStateMachine,
		"id":          definitionID,
		"name":        name,
		"description": strings.TrimSpace(description),
	}
	body["apiVersion"] = "aa.runbook/v1"
	body["initial"] = "start"
	body["states"] = []any{
		map[string]any{"id": "start"},
	}
	return body
}

// draftKindForDefinitionKind maps runtime definitions into authoring sections.
func draftKindForDefinitionKind(kind string) string {
	if strings.TrimSpace(kind) == draftKindStateMachine {
		return draftKindRunbook
	}
	return ""
}
