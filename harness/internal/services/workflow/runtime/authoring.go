// This file implements workflow authoring operations for the Automations UI.
package runtime

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"

	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/store"
)

const (
	draftStatusDraft     = "draft"
	draftStatusPublished = "published"
	draftKindTaskGraph   = "task_graph"
)

var authoringIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// ActionType describes one action node the authoring UI can place in a draft.
type ActionType struct {
	Name            string         `json:"name"`
	Label           string         `json:"label"`
	Description     string         `json:"description"`
	Risk            string         `json:"risk"`
	Available       bool           `json:"available"`
	InputSchema     map[string]any `json:"input_schema"`
	OutputSchema    map[string]any `json:"output_schema,omitempty"`
	InputContracts  []string       `json:"input_contracts,omitempty"`
	OutputContracts []string       `json:"output_contracts,omitempty"`
}

// DraftRequest carries a workflow draft create or update payload.
type DraftRequest struct {
	ID          string         `json:"id"`
	Kind        string         `json:"kind"`
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Body        map[string]any `json:"body"`
}

// ValidationDiagnostic describes one draft validation message.
type ValidationDiagnostic struct {
	Severity string `json:"severity"`
	Path     string `json:"path"`
	Message  string `json:"message"`
}

// ValidationResult reports syntax validity and publication readiness.
type ValidationResult struct {
	Valid       bool                   `json:"valid"`
	Publishable bool                   `json:"publishable"`
	Diagnostics []ValidationDiagnostic `json:"diagnostics"`
	Definition  map[string]any         `json:"definition,omitempty"`
}

// CompileResult contains a compiled workflow definition and YAML body.
type CompileResult struct {
	Definition definition.Definition `json:"definition"`
	YAML       string                `json:"yaml"`
	Validation ValidationResult      `json:"validation"`
}

// TemplateInstantiateRequest carries template parameter values.
type TemplateInstantiateRequest struct {
	Parameters map[string]any `json:"parameters"`
	Name       string         `json:"name"`
}

// PackageImportRequest carries one package record to install.
type PackageImportRequest struct {
	Package store.PackageRecord `json:"package"`
}

// taskGraphDraftDefinition stores the authoring-only task graph shape.
type taskGraphDraftDefinition struct {
	Kind        string                    `json:"kind"`
	ID          string                    `json:"id"`
	Name        string                    `json:"name,omitempty"`
	Description string                    `json:"description,omitempty"`
	Schedule    string                    `json:"schedule,omitempty"`
	Nodes       []taskGraphNodeDefinition `json:"nodes,omitempty"`
}

// taskGraphNodeDefinition stores one authoring-only task graph node.
type taskGraphNodeDefinition struct {
	ID         string         `json:"id"`
	Uses       string         `json:"uses"`
	DependsOn  []string       `json:"depends_on,omitempty"`
	With       map[string]any `json:"with,omitempty"`
	Timeout    string         `json:"timeout,omitempty"`
	Retry      int            `json:"retry,omitempty"`
	RetryDelay string         `json:"retry_delay,omitempty"`
}

// loadedDefinitionDraftSource carries a disk-loaded definition into authoring.
type loadedDefinitionDraftSource struct {
	definition definition.Definition
	body       map[string]any
}

// RunQuery selects workflow runs for the operations screen.
type RunQuery struct {
	Status       string
	DefinitionID string
	Limit        int
}

// ActionTypes returns the registered authoring action catalog.
func (s *Service) ActionTypes() []ActionType {
	names := s.actions.Names()
	types := make([]ActionType, 0, len(names))
	for _, name := range names {
		types = append(types, actionTypeForName(name))
	}
	return types
}

// ListRuns returns workflow runs matching operations filters.
func (s *Service) ListRuns(ctx context.Context, query RunQuery) ([]store.RunRecord, error) {
	return s.store.ListRuns(ctx, store.RunFilter{
		Status:       query.Status,
		DefinitionID: query.DefinitionID,
		Limit:        query.Limit,
	})
}

// ListDrafts returns editable workflow drafts.
func (s *Service) ListDrafts(ctx context.Context) ([]store.DraftRecord, error) {
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
	for _, draft := range drafts {
		draftIDs[draft.ID] = struct{}{}
		if definitionID := strings.TrimSpace(stringFromMap(draft.Body, "id", "")); definitionID != "" {
			definitionIDs[definitionID] = struct{}{}
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
		body["kind"] = definition.KindStateMachine
		body["id"] = definitionID
		if strings.TrimSpace(stringFromMap(body, "name", "")) == "" {
			body["name"] = name
		}
		record := store.DraftRecord{
			ID:          draftID,
			Kind:        definition.KindStateMachine,
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

// GetDraft returns one editable workflow draft.
func (s *Service) GetDraft(ctx context.Context, id string) (store.DraftRecord, error) {
	return s.store.GetDraft(ctx, strings.TrimSpace(id))
}

// CreateDraft stores a new editable workflow draft.
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

// DeleteDraft removes one editable workflow draft.
func (s *Service) DeleteDraft(ctx context.Context, id string) error {
	return s.store.DeleteDraft(ctx, strings.TrimSpace(id))
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

// CompileDraft converts a draft to the canonical workflow YAML shape.
func (s *Service) CompileDraft(ctx context.Context, id string) (CompileResult, error) {
	draft, err := s.store.GetDraft(ctx, strings.TrimSpace(id))
	if err != nil {
		return CompileResult{}, err
	}
	def, validation := s.compileDraftRecord(draft)
	if !validation.Valid {
		return CompileResult{Validation: validation}, fmt.Errorf("workflow draft is invalid")
	}
	yamlBody, err := yaml.Marshal(def)
	if err != nil {
		return CompileResult{}, fmt.Errorf("encode workflow YAML: %w", err)
	}
	return CompileResult{Definition: def, YAML: string(yamlBody), Validation: validation}, nil
}

// PublishDraft writes a compiled definition and reloads workflow definitions.
func (s *Service) PublishDraft(ctx context.Context, id string) (store.DefinitionRecord, error) {
	draft, err := s.store.GetDraft(ctx, strings.TrimSpace(id))
	if err != nil {
		return store.DefinitionRecord{}, err
	}
	def, validation := s.compileDraftRecord(draft)
	if !validation.Valid || !validation.Publishable {
		return store.DefinitionRecord{}, fmt.Errorf("workflow draft is not publishable")
	}
	yamlBody, err := yaml.Marshal(def)
	if err != nil {
		return store.DefinitionRecord{}, fmt.Errorf("encode workflow YAML: %w", err)
	}
	if err := os.MkdirAll(s.cfg.DefinitionsDir, 0o700); err != nil {
		return store.DefinitionRecord{}, fmt.Errorf("create workflow definitions directory: %w", err)
	}
	path := filepath.Join(s.cfg.DefinitionsDir, def.ID+".yaml")
	if err := os.WriteFile(path, yamlBody, 0o600); err != nil {
		return store.DefinitionRecord{}, fmt.Errorf("write workflow definition: %w", err)
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

// ListTemplates returns available workflow templates.
func (s *Service) ListTemplates(ctx context.Context) ([]store.TemplateRecord, error) {
	return s.store.ListTemplates(ctx)
}

// GetTemplate returns one workflow template.
func (s *Service) GetTemplate(ctx context.Context, id string) (store.TemplateRecord, error) {
	return s.store.GetTemplate(ctx, strings.TrimSpace(id))
}

// InstantiateTemplate creates an editable draft from a template.
func (s *Service) InstantiateTemplate(ctx context.Context, id string, req TemplateInstantiateRequest) (store.DraftRecord, error) {
	template, err := s.store.GetTemplate(ctx, strings.TrimSpace(id))
	if err != nil {
		return store.DraftRecord{}, err
	}
	body := cloneMap(template.Body)
	applyTemplateParameters(body, req.Parameters)
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = template.Name
	}
	return s.CreateDraft(ctx, DraftRequest{
		Kind:        stringFromMap(body, "kind", draftKindTaskGraph),
		Name:        name,
		Description: template.Description,
		Body:        body,
	})
}

// ListPackages returns installed workflow packages.
func (s *Service) ListPackages(ctx context.Context) ([]store.PackageRecord, error) {
	return s.store.ListPackages(ctx)
}

// ImportPackage installs one workflow package record.
func (s *Service) ImportPackage(ctx context.Context, req PackageImportRequest) (store.PackageRecord, error) {
	record := req.Package
	if err := validateAuthoringID(record.ID, "package id"); err != nil {
		return store.PackageRecord{}, err
	}
	if record.Name == "" {
		record.Name = record.ID
	}
	if record.Version == "" {
		record.Version = "0.1.0"
	}
	if err := s.store.UpsertPackage(ctx, record); err != nil {
		return store.PackageRecord{}, err
	}
	return s.store.GetPackage(ctx, record.ID)
}

// ExportPackage returns one installed workflow package.
func (s *Service) ExportPackage(ctx context.Context, id string) (store.PackageRecord, error) {
	return s.store.GetPackage(ctx, strings.TrimSpace(id))
}

// SeedAuthoringCatalog installs built-in templates and package metadata.
func (s *Service) SeedAuthoringCatalog(ctx context.Context) error {
	templates, err := builtInTemplates()
	if err != nil {
		return err
	}
	for _, template := range templates {
		if err := s.store.UpsertTemplate(ctx, template); err != nil {
			return err
		}
	}
	return nil
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
		kind = stringFromMap(req.Body, "kind", draftKindTaskGraph)
	}
	if kind != draftKindTaskGraph && kind != definition.KindStateMachine {
		return store.DraftRecord{}, fmt.Errorf("draft kind must be %q or %q", draftKindTaskGraph, definition.KindStateMachine)
	}
	body := cloneMap(req.Body)
	if len(body) == 0 {
		body = blankDefinitionBody(id, kind, req.Name, req.Description)
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = stringFromMap(body, "name", id)
	}
	body["kind"] = kind
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
	if isTaskGraphDraft(draft, body) {
		return taskGraphDefinitionFromDraft(draft, body)
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
		def.Kind = draft.Kind
	}
	if strings.TrimSpace(def.Name) == "" {
		def.Name = draft.Name
	}
	return def, nil
}

// isTaskGraphDraft reports whether a draft body uses visual task-graph authoring.
func isTaskGraphDraft(draft store.DraftRecord, body map[string]any) bool {
	return strings.TrimSpace(draft.Kind) == draftKindTaskGraph ||
		strings.TrimSpace(stringFromMap(body, "kind", "")) == draftKindTaskGraph
}

// taskGraphDefinitionFromDraft compiles authoring graph nodes into task states.
func taskGraphDefinitionFromDraft(draft store.DraftRecord, body map[string]any) (definition.Definition, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return definition.Definition{}, fmt.Errorf("encode task graph draft: %w", err)
	}
	var graph taskGraphDraftDefinition
	if err := json.Unmarshal(encoded, &graph); err != nil {
		return definition.Definition{}, fmt.Errorf("decode task graph draft: %w", err)
	}
	normalizeTaskGraphRetries(body, &graph)
	id := strings.TrimSpace(graph.ID)
	if id == "" {
		id = definitionIDFromDraftID(draft.ID)
	}
	name := strings.TrimSpace(graph.Name)
	if name == "" {
		name = draft.Name
	}
	states := make([]definition.StateDefinition, 0, len(graph.Nodes))
	for _, node := range graph.Nodes {
		states = append(states, definition.StateDefinition{
			ID:         node.ID,
			Type:       definition.StateTypeTask,
			Uses:       node.Uses,
			DependsOn:  append([]string(nil), node.DependsOn...),
			With:       cloneMap(node.With),
			Timeout:    node.Timeout,
			Retry:      node.Retry,
			RetryDelay: node.RetryDelay,
		})
	}
	return definition.Definition{
		Kind:        definition.KindStateMachine,
		ID:          id,
		Name:        name,
		Description: strings.TrimSpace(graph.Description),
		Schedule:    strings.TrimSpace(graph.Schedule),
		States:      states,
		Authoring: map[string]any{
			"mode":       draftKindTaskGraph,
			"task_graph": cloneMap(body),
		},
	}, nil
}

// normalizeTaskGraphRetries folds editable retry policy maps into task nodes.
func normalizeTaskGraphRetries(body map[string]any, def *taskGraphDraftDefinition) {
	if def == nil {
		return
	}
	nodes := anySlice(body["nodes"])
	for index := range def.Nodes {
		if index >= len(nodes) {
			continue
		}
		nodeMap, ok := nodes[index].(map[string]any)
		if !ok {
			continue
		}
		retries, ok := nodeMap["retries"].(map[string]any)
		if !ok {
			continue
		}
		if def.Nodes[index].Retry == 0 {
			def.Nodes[index].Retry = intFromAny(retries["attempts"])
		}
		if def.Nodes[index].RetryDelay == "" {
			def.Nodes[index].RetryDelay = strings.TrimSpace(fmt.Sprint(retries["delay"]))
		}
	}
}

// blankDefinitionBody returns a minimal editable definition body.
func blankDefinitionBody(id string, kind string, name string, description string) map[string]any {
	definitionID := definitionIDFromDraftID(id)
	if strings.TrimSpace(name) == "" {
		name = definitionID
	}
	body := map[string]any{
		"kind":        kind,
		"id":          definitionID,
		"name":        name,
		"description": strings.TrimSpace(description),
	}
	if kind == definition.KindStateMachine {
		body["initial"] = "review"
		body["states"] = []any{
			map[string]any{"id": "review", "transitions": []any{map[string]any{"trigger": "approved", "to": "approved"}}},
			map[string]any{"id": "approved"},
		}
	} else {
		body["nodes"] = []any{
			map[string]any{
				"id":   "tool_task",
				"uses": "tool.call",
				"with": map[string]any{
					"name":      "",
					"arguments": map[string]any{},
				},
			},
		}
	}
	return body
}

// actionTypeForName returns authoring metadata for one registered action.
func actionTypeForName(name string) ActionType {
	action := ActionType{
		Name:           name,
		Label:          name,
		Description:    "Workflow action.",
		Risk:           "read",
		Available:      true,
		InputSchema:    map[string]any{"type": "object"},
		OutputSchema:   map[string]any{"type": "object"},
		InputContracts: []string{"aa.workflow.action_input.v1"},
	}
	switch name {
	case "tool.call":
		action.Label = "Run Tool"
		action.Description = "Call a harness-exposed context or MCP-backed tool."
		action.Risk = "tool"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"name"}, "properties": map[string]any{"name": map[string]any{"type": "string"}, "domain_id": map[string]any{"type": "string"}, "arguments": map[string]any{"type": "object"}}}
		action.InputContracts = []string{"aa.external_call_request.v1"}
		action.OutputContracts = []string{"aa.external_call_result.v1"}
	case "mcp.call":
		action.Label = "Call MCP Tool"
		action.Description = "Call an installed MCP tool endpoint."
		action.Risk = "tool"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"endpoint", "tool"}, "properties": map[string]any{"endpoint": map[string]any{"type": "string"}, "tool": map[string]any{"type": "string"}, "arguments": map[string]any{"type": "object"}}}
		action.InputContracts = []string{"aa.external_call_request.v1"}
		action.OutputContracts = []string{"aa.external_call_result.v1"}
	case "data.assert":
		action.Label = "Assert Data"
		action.Description = "Gate workflow progression on deterministic input data checks."
		action.Risk = "validation"
		action.InputSchema = map[string]any{"type": "object", "properties": map[string]any{"path": map[string]any{"type": "string"}, "mode": map[string]any{"type": "string"}, "value": map[string]any{}, "checks": map[string]any{"type": "array"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"passed": map[string]any{"type": "boolean"}, "checks": map[string]any{"type": "array"}}}
		action.InputContracts = []string{"aa.validation_request.v1"}
		action.OutputContracts = []string{"aa.validation_result.v1"}
	case "workflow.run":
		action.Label = "Run Workflow"
		action.Description = "Start a nested workflow definition."
		action.Risk = "workflow"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"workflow"}, "properties": map[string]any{"workflow": map[string]any{"type": "string"}, "input": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"run_id": map[string]any{"type": "string"}, "definition_id": map[string]any{"type": "string"}, "status": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.workflow_run_request.v1"}
		action.OutputContracts = []string{"aa.workflow_run_result.v1"}
	case "workflow.signal":
		action.Label = "Signal Workflow"
		action.Description = "Emit a workflow signal."
		action.Risk = "workflow"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"signal"}, "properties": map[string]any{"run_id": map[string]any{"type": "string"}, "signal": map[string]any{"type": "string"}, "payload": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"run_id": map[string]any{"type": "string"}, "signal": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.workflow_signal_request.v1"}
		action.OutputContracts = []string{"aa.workflow_signal_result.v1"}
	case "human.request":
		action.Label = "Ask User"
		action.Description = "Create a pending user item through the gateway-facing inbox."
		action.Risk = "approval"
		action.InputSchema = map[string]any{"type": "object", "required": []any{"prompt"}, "properties": map[string]any{"prompt": map[string]any{"type": "string"}, "payload": map[string]any{"type": "object"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"pending_id": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.human_request.v1"}
		action.OutputContracts = []string{"aa.human_request_result.v1"}
	case "delay.until":
		action.Label = "Wait"
		action.Description = "Pause until a timestamp or duration elapses."
		action.Risk = "time"
		action.InputSchema = map[string]any{"type": "object", "properties": map[string]any{"until": map[string]any{"type": "string"}, "duration": map[string]any{"type": "string"}}}
		action.OutputSchema = map[string]any{"type": "object", "properties": map[string]any{"waited": map[string]any{"type": "string"}}}
		action.InputContracts = []string{"aa.wait_request.v1"}
		action.OutputContracts = []string{"aa.wait_result.v1"}
	}
	return action
}

// unavailableActions returns registered actions that cannot be published yet.
func unavailableActions(_ definition.Definition) []string {
	return nil
}

// applyTemplateParameters replaces simple string placeholders in template bodies.
func applyTemplateParameters(body map[string]any, params map[string]any) {
	for key, value := range body {
		switch typed := value.(type) {
		case string:
			next := typed
			for param, replacement := range params {
				next = strings.ReplaceAll(next, "{{"+param+"}}", fmt.Sprint(replacement))
			}
			body[key] = next
		case map[string]any:
			applyTemplateParameters(typed, params)
		case []any:
			for _, item := range typed {
				if nested, ok := item.(map[string]any); ok {
					applyTemplateParameters(nested, params)
				}
			}
		}
	}
}

// invalidValidation builds a failed validation report.
func invalidValidation(path string, err error) ValidationResult {
	return ValidationResult{
		Valid:       false,
		Publishable: false,
		Diagnostics: []ValidationDiagnostic{{
			Severity: "error",
			Path:     path,
			Message:  err.Error(),
		}},
	}
}

// validateAuthoringID checks ids used by authoring records.
func validateAuthoringID(value string, label string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return fmt.Errorf("%s is required", label)
	}
	if !authoringIDPattern.MatchString(trimmed) {
		return fmt.Errorf("%s %q is invalid", label, trimmed)
	}
	return nil
}

// definitionIDFromDraftID returns a safe default definition id for a draft.
func definitionIDFromDraftID(id string) string {
	trimmed := strings.TrimPrefix(strings.TrimSpace(id), "draft_")
	if trimmed == "" || !authoringIDPattern.MatchString(trimmed) {
		return "automation_" + strings.ReplaceAll(strings.TrimSpace(id), "-", "_")
	}
	return trimmed
}

// draftIDForDefinition returns the editable draft id for a loaded definition.
func draftIDForDefinition(id string) string {
	return "draft_" + strings.TrimSpace(id)
}

// stringFromMap returns a string value from a JSON map.
func stringFromMap(body map[string]any, key string, fallback string) string {
	if value, ok := body[key].(string); ok && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	return fallback
}

// anySlice returns a JSON list from decoded draft data.
func anySlice(value any) []any {
	if items, ok := value.([]any); ok {
		return items
	}
	return []any{}
}

// intFromAny reads whole-number JSON values without expression evaluation.
func intFromAny(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case int64:
		return int(typed)
	case float64:
		return int(typed)
	case json.Number:
		parsed, _ := typed.Int64()
		return int(parsed)
	default:
		return 0
	}
}

// cloneMap returns a JSON-deep-copy of a map.
func cloneMap(value map[string]any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return map[string]any{}
	}
	var cloned map[string]any
	if err := json.Unmarshal(encoded, &cloned); err != nil {
		return map[string]any{}
	}
	return cloned
}

// cloneMapList returns a JSON-deep-copy of a map list.
func cloneMapList(value []map[string]any) []map[string]any {
	if value == nil {
		return []map[string]any{}
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return []map[string]any{}
	}
	var cloned []map[string]any
	if err := json.Unmarshal(encoded, &cloned); err != nil {
		return []map[string]any{}
	}
	return cloned
}

// mapFromJSON converts a typed value to generic JSON object form.
func mapFromJSON(value any) (map[string]any, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(encoded, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// definitionHash returns the stable JSON hash used for published metadata.
func definitionHash(def definition.Definition) string {
	encoded, _ := json.Marshal(def)
	sum := sha256.Sum256(encoded)
	return hex.EncodeToString(sum[:])
}
