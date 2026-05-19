// This file tests workflow authoring operations used by the Automations UI.
package runtime

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"workflow/internal/definition"
	"workflow/internal/store"
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
	template := codexCLIPilotTemplate()
	states, _ := template.Body["states"].([]any)
	have := map[string]bool{}
	for _, state := range states {
		stateMap, _ := state.(map[string]any)
		if stateMap["id"] != "assert_plan" {
			continue
		}
		with, _ := stateMap["with"].(map[string]any)
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
	template := codexCLIPilotTemplate()
	states, _ := template.Body["states"].([]any)
	byID := map[string]map[string]any{}
	for _, state := range states {
		stateMap, _ := state.(map[string]any)
		id, _ := stateMap["id"].(string)
		byID[id] = stateMap
	}

	cleanupDeps, _ := byID["cleanup"]["depends_on"].([]string)
	if !hasString(cleanupDeps, "post_review") {
		t.Fatalf("cleanup depends_on = %#v, want post_review", cleanupDeps)
	}
	finalReviewDeps, _ := byID["final_review"]["depends_on"].([]string)
	if !hasString(finalReviewDeps, "assert_retest") {
		t.Fatalf("final_review depends_on = %#v, want assert_retest", finalReviewDeps)
	}
	assertReviewWith, _ := byID["assert_review"]["with"].(map[string]any)
	assertReviewChecks, _ := assertReviewWith["checks"].([]any)
	check, _ := assertReviewChecks[0].(map[string]any)
	if check["path"] != "final_review.output.deviations" {
		t.Fatalf("assert_review path = %#v, want final review deviations", check["path"])
	}
	commitDeps, _ := byID["commit"]["depends_on"].([]string)
	if !hasString(commitDeps, "assert_review") {
		t.Fatalf("commit depends_on = %#v, want assert_review", commitDeps)
	}
}

// hasString reports whether values contains expected.
func hasString(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
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
