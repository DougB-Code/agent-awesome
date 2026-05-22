// This file tests workflow authoring operations used by the Automations UI.
package runtime

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"agentawesome/internal/services/workflow/definition"
	"agentawesome/internal/services/workflow/store"
)

// TestDraftValidatePublishReload verifies draft publication installs definitions immediately.
func TestDraftValidatePublishReload(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	draft, err := service.CreateDraft(ctx, DraftRequest{
		ID:   "draft_publishable",
		Kind: draftKindTaskGraph,
		Name: "Publishable",
		Body: map[string]any{
			"kind": draftKindTaskGraph,
			"id":   "publishable",
			"name": "Publishable",
			"nodes": []any{
				map[string]any{
					"id":   "tool",
					"uses": "tool.call",
					"with": map[string]any{
						"name":      "mock_tool",
						"arguments": map[string]any{},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}

	validation, err := service.ValidateDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("ValidateDraft() error = %v", err)
	}
	if !validation.Valid || !validation.Publishable {
		t.Fatalf("validation = %#v, want valid and publishable", validation)
	}
	if _, ok := validation.Definition["nodes"]; ok {
		t.Fatalf("compiled definition leaked root nodes: %#v", validation.Definition)
	}
	definitionRecord, err := service.PublishDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("PublishDraft() error = %v", err)
	}
	if definitionRecord.ID != "publishable" {
		t.Fatalf("published definition id = %q, want publishable", definitionRecord.ID)
	}
	if definitionRecord.Kind != definition.KindStateMachine {
		t.Fatalf("published definition kind = %q, want state_machine", definitionRecord.Kind)
	}
	if _, ok := service.DescribeDefinition("publishable"); !ok {
		t.Fatalf("DescribeDefinition() did not find published definition")
	}
}

// TestOpenCreatesEditableDraftForLoadedDefinition verifies config workflows can be selected in the builder.
func TestOpenCreatesEditableDraftForLoadedDefinition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "loaded.yaml", `
kind: state_machine
id: loaded_tool
name: Loaded Tool
description: Loaded from the config workflow directory.
states:
  - id: call_tool
    type: task
    uses: tool.call
    with:
      name: mock_tool
      arguments: {}
`)
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	drafts, err := service.ListDrafts(ctx)
	if err != nil {
		t.Fatalf("ListDrafts() error = %v", err)
	}
	for _, draft := range drafts {
		if draft.ID != "draft_loaded_tool" {
			continue
		}
		if draft.Kind != definition.KindStateMachine {
			t.Fatalf("draft kind = %q, want state_machine", draft.Kind)
		}
		if draft.Name != "Loaded Tool" {
			t.Fatalf("draft name = %q, want Loaded Tool", draft.Name)
		}
		if draft.Body["id"] != "loaded_tool" {
			t.Fatalf("draft body id = %#v, want loaded_tool", draft.Body["id"])
		}
		return
	}
	t.Fatalf("ListDrafts() = %#v, want draft_loaded_tool", drafts)
}

// TestStateMachineDraftRejectsTaskGraphNodes verifies authoring nodes stay out of executable definitions.
func TestStateMachineDraftRejectsTaskGraphNodes(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	draft, err := service.CreateDraft(ctx, DraftRequest{
		ID:   "draft_leaky_nodes",
		Kind: definition.KindStateMachine,
		Body: map[string]any{
			"kind":    definition.KindStateMachine,
			"id":      "leaky_nodes",
			"initial": "start",
			"states": []any{
				map[string]any{"id": "start"},
			},
			"nodes": []any{
				map[string]any{"id": "tool", "uses": "tool.call"},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}
	validation, err := service.ValidateDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("ValidateDraft() error = %v", err)
	}
	if validation.Valid || validation.Publishable {
		t.Fatalf("validation = %#v, want root nodes rejected", validation)
	}
}

// TestActionCatalogOmitsRemovedActions verifies workflow authoring has no legacy actions.
func TestActionCatalogOmitsRemovedActions(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	removed := map[string]bool{"cli.command": false, "agent.run": false, "dag.run": false}
	for _, action := range service.ActionTypes() {
		if _, ok := removed[action.Name]; ok {
			removed[action.Name] = true
		}
	}
	for action, found := range removed {
		if found {
			t.Fatalf("%s action type was listed", action)
		}
	}

	draft, err := service.CreateDraft(ctx, DraftRequest{
		ID:   "draft_cli",
		Kind: draftKindTaskGraph,
		Body: map[string]any{
			"kind": draftKindTaskGraph,
			"id":   "cli_draft",
			"name": "CLI Draft",
			"nodes": []any{
				map[string]any{"id": "command", "uses": "cli.command"},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}
	validation, err := service.ValidateDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("ValidateDraft() error = %v", err)
	}
	if validation.Valid || validation.Publishable {
		t.Fatalf("validation = %#v, want invalid CLI task graph", validation)
	}
	if _, err := service.PublishDraft(ctx, draft.ID); err == nil {
		t.Fatalf("PublishDraft() error = nil, want CLI publish rejection")
	}
}

// TestTemplateInstantiateCreatesDraft verifies templates produce editable drafts.
func TestTemplateInstantiateCreatesDraft(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	templates, err := service.ListTemplates(ctx)
	if err != nil {
		t.Fatalf("ListTemplates() error = %v", err)
	}
	if len(templates) == 0 {
		t.Fatalf("ListTemplates() = empty, want built-in templates")
	}
	draft, err := service.InstantiateTemplate(ctx, "approval_state_machine", TemplateInstantiateRequest{
		Name:       "Course Approval",
		Parameters: map[string]any{"prompt": "Approve course download?"},
	})
	if err != nil {
		t.Fatalf("InstantiateTemplate() error = %v", err)
	}
	if draft.Status != draftStatusDraft {
		t.Fatalf("draft status = %q, want draft", draft.Status)
	}
	if draft.Name != "Course Approval" {
		t.Fatalf("draft name = %q, want Course Approval", draft.Name)
	}
}

// TestCodexCLIPilotTemplateAssertsPlanPolicy verifies the pilot plan gate matches policy.
func TestCodexCLIPilotTemplateAssertsPlanPolicy(t *testing.T) {
	template := mustBuiltInTemplate(t, "codex_cli_pilot")
	states := flattenTemplateStates(template.Body["states"])
	have := map[string]bool{}
	for _, state := range states {
		stateMap := state
		if stateMap["id"] != "assert_plan" {
			continue
		}
		actions, _ := stateMap["on_entry"].([]any)
		action, _ := actions[0].(map[string]any)
		with, _ := action["with"].(map[string]any)
		checks, _ := with["checks"].([]any)
		for _, check := range checks {
			checkMap, _ := check.(map[string]any)
			path, _ := checkMap["path"].(string)
			have[path] = true
		}
	}
	want := []string{
		"plan.output.plan.compliant",
		"plan.output.plan.project_conventions",
		"plan.output.plan.solid",
		"plan.output.plan.agents",
		"plan.output.plan.relevant_skills",
		"plan.output.plan.no_unnecessary_backwards_compatibility",
		"plan.output.plan.no_duplicate_implementations",
		"plan.output.plan.no_hardcoded_values",
	}
	for _, path := range want {
		if !have[path] {
			t.Fatalf("assert_plan missing policy check %q", path)
		}
	}
}

// TestCodexCLIPilotTemplateGatesFinalReviewAfterCleanup verifies cleanup can respond to review.
func TestCodexCLIPilotTemplateGatesFinalReviewAfterCleanup(t *testing.T) {
	template := mustBuiltInTemplate(t, "codex_cli_pilot")
	states := flattenTemplateStates(template.Body["states"])
	byID := map[string]map[string]any{}
	for _, state := range states {
		id, _ := state["id"].(string)
		byID[id] = state
	}

	if !hasTransition(byID["post_review"], "cleanup") {
		t.Fatalf("post_review transitions = %#v, want cleanup", byID["post_review"]["transitions"])
	}
	if !hasTransition(byID["assert_retest"], "final_review") {
		t.Fatalf("assert_retest transitions = %#v, want final_review", byID["assert_retest"]["transitions"])
	}
	assertReviewActions, _ := byID["assert_review"]["on_entry"].([]any)
	assertReviewAction, _ := assertReviewActions[0].(map[string]any)
	assertReviewWith, _ := assertReviewAction["with"].(map[string]any)
	assertReviewChecks, _ := assertReviewWith["checks"].([]any)
	check, _ := assertReviewChecks[0].(map[string]any)
	if check["path"] != "final_review.output.deviations" {
		t.Fatalf("assert_review path = %#v, want final review deviations", check["path"])
	}
	if !hasTransition(byID["assert_review"], "publish") {
		t.Fatalf("assert_review transitions = %#v, want publish phase", byID["assert_review"]["transitions"])
	}
}

// TestCodexCLIPilotTemplateValidatesAsHierarchy verifies the built-in phase workflow publishes.
func TestCodexCLIPilotTemplateValidatesAsHierarchy(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	draft, err := service.InstantiateTemplate(ctx, "codex_cli_pilot", TemplateInstantiateRequest{})
	if err != nil {
		t.Fatalf("InstantiateTemplate() error = %v", err)
	}
	validation, err := service.ValidateDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("ValidateDraft() error = %v", err)
	}
	if !validation.Valid || !validation.Publishable {
		t.Fatalf("validation = %#v, want publishable hierarchical workflow", validation)
	}
}

// TestStateMachineDraftPublishPreservesHierarchy verifies nested authoring is not flattened.
func TestStateMachineDraftPublishPreservesHierarchy(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	service, err := Open(ctx, Config{
		DefinitionsDir: definitionsDir,
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	draft, err := service.CreateDraft(ctx, DraftRequest{
		ID:   "draft_hierarchy",
		Kind: definition.KindStateMachine,
		Body: map[string]any{
			"kind":    definition.KindStateMachine,
			"id":      "hierarchy_publish",
			"initial": "phase",
			"states": []any{
				map[string]any{
					"id":      "phase",
					"initial": "child",
					"states":  []any{map[string]any{"id": "child"}},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}
	if _, err := service.PublishDraft(ctx, draft.ID); err != nil {
		t.Fatalf("PublishDraft() error = %v", err)
	}
	loaded, err := definition.LoadFile(filepath.Join(definitionsDir, "hierarchy_publish.yaml"), service.actions)
	if err != nil {
		t.Fatalf("LoadFile() error = %v", err)
	}
	if len(loaded.Definition.States) != 1 || len(loaded.Definition.States[0].States) != 1 {
		t.Fatalf("published states = %#v, want nested phase child", loaded.Definition.States)
	}
}

// flattenTemplateStates returns template states in depth-first author order.
func flattenTemplateStates(value any) []map[string]any {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	states := []map[string]any{}
	for _, item := range items {
		state, _ := item.(map[string]any)
		states = append(states, state)
		states = append(states, flattenTemplateStates(state["states"])...)
	}
	return states
}

// hasTransition reports whether a process state transitions to target.
func hasTransition(state map[string]any, target string) bool {
	items, _ := state["transitions"].([]any)
	for _, item := range items {
		transition, _ := item.(map[string]any)
		if transition["to"] == target {
			return true
		}
	}
	return false
}

// mustBuiltInTemplate returns a built-in template for tests.
func mustBuiltInTemplate(t *testing.T, id string) store.TemplateRecord {
	t.Helper()
	templates, err := builtInTemplates()
	if err != nil {
		t.Fatalf("builtInTemplates() error = %v", err)
	}
	for _, template := range templates {
		if template.ID == id {
			return template
		}
	}
	t.Fatalf("builtInTemplates() missing %q", id)
	return store.TemplateRecord{}
}

// TestPackageImportExportRoundTrip verifies package records can be installed and exported.
func TestPackageImportExportRoundTrip(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	imported, err := service.ImportPackage(ctx, PackageImportRequest{Package: storePackage("email_triage")})
	if err != nil {
		t.Fatalf("ImportPackage() error = %v", err)
	}
	exported, err := service.ExportPackage(ctx, imported.ID)
	if err != nil {
		t.Fatalf("ExportPackage() error = %v", err)
	}
	if exported.ID != imported.ID || exported.Version != "0.1.0" {
		t.Fatalf("exported package = %#v, want imported package", exported)
	}
}

// storePackage returns a small package record for authoring tests.
func storePackage(id string) store.PackageRecord {
	return store.PackageRecord{
		ID:      id,
		Name:    "Email Triage",
		Version: "0.1.0",
		Body:    map[string]any{"templates": []any{}},
	}
}
