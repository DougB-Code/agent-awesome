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
		Kind: definition.KindDAG,
		Name: "Publishable",
		Body: map[string]any{
			"kind": definition.KindDAG,
			"id":   "publishable",
			"name": "Publishable",
			"nodes": []any{
				map[string]any{
					"id":   "agent",
					"uses": "agent.run",
					"with": map[string]any{
						"instructions": "Summarize input.",
						"input":        map[string]any{},
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
	definitionRecord, err := service.PublishDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("PublishDraft() error = %v", err)
	}
	if definitionRecord.ID != "publishable" {
		t.Fatalf("published definition id = %q, want publishable", definitionRecord.ID)
	}
	if _, ok := service.DescribeDefinition("publishable"); !ok {
		t.Fatalf("DescribeDefinition() did not find published definition")
	}
}

// TestActionCatalogMarksCLIUnavailable verifies CLI nodes are draft-only in v1.
func TestActionCatalogMarksCLIUnavailable(t *testing.T) {
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

	var found bool
	for _, action := range service.ActionTypes() {
		if action.Name == "cli.command" {
			found = true
			if action.Available {
				t.Fatalf("cli.command Available = true, want false")
			}
		}
	}
	if !found {
		t.Fatalf("cli.command action type was not listed")
	}

	draft, err := service.CreateDraft(ctx, DraftRequest{
		ID:   "draft_cli",
		Kind: definition.KindDAG,
		Body: map[string]any{
			"kind": definition.KindDAG,
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
		t.Fatalf("validation = %#v, want invalid CLI DAG", validation)
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

// TestAgentSpecCRUD verifies reusable agent specs can be edited safely.
func TestAgentSpecCRUD(t *testing.T) {
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

	if _, err := service.CreateAgentSpec(ctx, AgentSpecRequest{
		ID:   "bad_agent",
		Name: "Bad Agent",
		Permissions: map[string]any{
			"shell": map[string]any{"execute": true},
		},
	}); err == nil {
		t.Fatalf("CreateAgentSpec() error = nil, want invalid permission rejection")
	}
	if _, err := service.CreateAgentSpec(ctx, AgentSpecRequest{
		ID:   "bad_network_agent",
		Name: "Bad Network Agent",
		Permissions: map[string]any{
			"network": map[string]any{"execute": true},
		},
	}); err == nil {
		t.Fatalf("CreateAgentSpec() error = nil, want invalid network execute rejection")
	}

	created, err := service.CreateAgentSpec(ctx, AgentSpecRequest{
		ID:           "triage_agent",
		Name:         "Triage Agent",
		Instructions: "Classify input into review buckets.",
		Permissions: map[string]any{
			"filesystem": map[string]any{"read": true},
			"network":    map[string]any{"read": true},
		},
	})
	if err != nil {
		t.Fatalf("CreateAgentSpec() error = %v", err)
	}
	filesystem := created.Permissions["filesystem"].(map[string]any)
	if filesystem["read"] != true || filesystem["write"] != false {
		t.Fatalf("created permissions = %#v, want normalized filesystem read only", created.Permissions)
	}

	updated, err := service.UpdateAgentSpec(ctx, created.ID, AgentSpecRequest{
		Name:         "Email Triage Agent",
		Instructions: "Classify email into action buckets.",
		Permissions: map[string]any{
			"filesystem": map[string]any{"read": true, "write": true},
			"network":    map[string]any{"read": true},
		},
	})
	if err != nil {
		t.Fatalf("UpdateAgentSpec() error = %v", err)
	}
	updatedFilesystem := updated.Permissions["filesystem"].(map[string]any)
	if updated.Name != "Email Triage Agent" || updatedFilesystem["write"] != true {
		t.Fatalf("updated agent spec = %#v, want edited name and permissions", updated)
	}

	specs, err := service.ListAgentSpecs(ctx)
	if err != nil {
		t.Fatalf("ListAgentSpecs() error = %v", err)
	}
	if len(specs) != 1 {
		t.Fatalf("ListAgentSpecs() length = %d, want 1", len(specs))
	}
	if err := service.DeleteAgentSpec(ctx, created.ID); err != nil {
		t.Fatalf("DeleteAgentSpec() error = %v", err)
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
