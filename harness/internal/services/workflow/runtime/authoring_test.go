// This file tests workflow authoring operations used by the Automations UI.
package runtime

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"path/filepath"
	"testing"
	"time"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/services/capabilities"
	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/contracts"
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
		Kind: draftKindWorkflow,
		Name: "Publishable",
		Body: map[string]any{
			"kind": draftKindWorkflow,
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
	if _, ok := validation.Definition["nodes"]; !ok {
		t.Fatalf("compiled definition = %#v, want workflow nodes", validation.Definition)
	}
	definitionRecord, err := service.PublishDraft(ctx, draft.ID)
	if err != nil {
		t.Fatalf("PublishDraft() error = %v", err)
	}
	if definitionRecord.ID != "publishable" {
		t.Fatalf("published definition id = %q, want publishable", definitionRecord.ID)
	}
	if definitionRecord.Kind != definition.KindWorkflow {
		t.Fatalf("published definition kind = %q, want workflow", definitionRecord.Kind)
	}
	if _, ok := service.DescribeDefinition("publishable"); !ok {
		t.Fatalf("DescribeDefinition() did not find published definition")
	}
}

// TestDraftPublishBlocksUnavailableCapability verifies capability checks gate publication.
func TestDraftPublishBlocksUnavailableCapability(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
		Capabilities: capabilities.NewRegistry(&schema.Tools{
			LocalExec: schema.LocalExec{
				Enabled: false,
				Commands: []schema.LocalExecCommand{{
					Name:       "go_test_all",
					Executable: "go",
				}},
			},
		}, schema.Agent{Name: "AA", Instruction: "Work."}),
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	draft, err := service.CreateDraft(ctx, DraftRequest{
		ID:   "draft_blocked_capability",
		Kind: draftKindWorkflow,
		Body: map[string]any{
			"kind": draftKindWorkflow,
			"id":   "blocked_capability",
			"name": "Blocked Capability",
			"nodes": []any{
				map[string]any{
					"id":   "verify",
					"uses": "command.execute",
					"with": map[string]any{
						"template_id": "go_test_all",
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
	if !validation.Valid || validation.Publishable {
		t.Fatalf("validation = %#v, want valid but not publishable", validation)
	}
	if len(validation.Diagnostics) != 1 || validation.Diagnostics[0].Path != "nodes.verify.template_id" {
		t.Fatalf("diagnostics = %#v, want command template capability diagnostic", validation.Diagnostics)
	}
	if _, err := service.PublishDraft(ctx, draft.ID); err == nil {
		t.Fatalf("PublishDraft() error = nil, want capability rejection")
	}
}

// TestOpenCreatesEditableDraftForLoadedDefinition verifies config workflows can be selected in the builder.
func TestOpenCreatesEditableDraftForLoadedDefinition(t *testing.T) {
	ctx := context.Background()
	definitionsDir := t.TempDir()
	writeTestDefinition(t, definitionsDir, "loaded.yaml", `
kind: workflow
id: loaded_tool
name: Loaded Tool
description: Loaded from the config workflow directory.
nodes:
  - id: call_tool
    type: tool
    tool: mock_tool
    with:
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
		if draft.Kind != definition.KindWorkflow {
			t.Fatalf("draft kind = %q, want workflow", draft.Kind)
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

// TestDraftAcceptsStateMachineKind verifies authoring accepts hierarchical workflow drafts.
func TestDraftAcceptsStateMachineKind(t *testing.T) {
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
		ID:   "draft_state_machine",
		Kind: definition.KindStateMachine,
		Body: map[string]any{
			"kind":    definition.KindStateMachine,
			"id":      "state_machine",
			"initial": "start",
			"states": []any{
				map[string]any{"id": "start"},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}
	if draft.Kind != definition.KindStateMachine {
		t.Fatalf("draft kind = %q, want state_machine", draft.Kind)
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
		Kind: draftKindWorkflow,
		Body: map[string]any{
			"kind": draftKindWorkflow,
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
		t.Fatalf("validation = %#v, want invalid CLI workflow", validation)
	}
	if _, err := service.PublishDraft(ctx, draft.ID); err == nil {
		t.Fatalf("PublishDraft() error = nil, want CLI publish rejection")
	}
}

// TestActionManifestsExposeContracts verifies authoring can inspect callable manifests.
func TestActionManifestsExposeContracts(t *testing.T) {
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

	for _, manifest := range service.ActionManifests() {
		if manifest.ID != "tool.call" {
			continue
		}
		if manifest.Input.Schema["type"] != "object" {
			t.Fatalf("tool.call manifest = %#v, want object input schema", manifest)
		}
		return
	}
	t.Fatalf("ActionManifests() missing tool.call")
}

// TestDraftEdgeCompatibilityReportsContracts verifies node contracts can be checked before publishing.
func TestDraftEdgeCompatibilityReportsContracts(t *testing.T) {
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
		ID:   "draft_compatibility",
		Kind: draftKindWorkflow,
		Body: map[string]any{
			"kind": draftKindWorkflow,
			"id":   "compatibility",
			"nodes": []any{
				map[string]any{
					"id":   "source",
					"uses": "tool.call",
					"output": map[string]any{
						"produces": []any{map[string]any{"kind": "object"}},
						"facets":   []any{"document.text"},
					},
				},
				map[string]any{
					"id":   "direct_target",
					"uses": "tool.call",
					"input": map[string]any{
						"accepts":         []any{map[string]any{"kind": "object"}},
						"required_facets": []any{"document.text"},
					},
				},
				map[string]any{
					"id":   "blocked_target",
					"uses": "tool.call",
					"input": map[string]any{
						"required_facets": []any{"customer.email"},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}

	direct, err := service.CheckDraftEdgeCompatibility(ctx, draft.ID, EdgeCompatibilityRequest{
		SourceNodeID: "source",
		TargetNodeID: "direct_target",
	})
	if err != nil {
		t.Fatalf("CheckDraftEdgeCompatibility() direct error = %v", err)
	}
	if direct.Compatibility.Status != contracts.CompatibilityDirect {
		t.Fatalf("direct compatibility = %#v, want direct", direct.Compatibility)
	}
	blocked, err := service.CheckDraftEdgeCompatibility(ctx, draft.ID, EdgeCompatibilityRequest{
		SourceNodeID: "source",
		TargetNodeID: "blocked_target",
	})
	if err != nil {
		t.Fatalf("CheckDraftEdgeCompatibility() blocked error = %v", err)
	}
	if blocked.Compatibility.Status != contracts.CompatibilityBlocked {
		t.Fatalf("blocked compatibility = %#v, want blocked", blocked.Compatibility)
	}
}

// TestAdapterChoicePersistsReusableAdapter verifies ambiguous edges can be resolved once.
func TestAdapterChoicePersistsReusableAdapter(t *testing.T) {
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
		ID:   "draft_adapter_choice",
		Kind: draftKindWorkflow,
		Body: map[string]any{
			"kind": draftKindWorkflow,
			"id":   "adapter_choice",
			"nodes": []any{
				map[string]any{
					"id":   "source",
					"uses": "tool.call",
					"output": map[string]any{
						"produces": []any{map[string]any{"kind": "object"}},
						"facets":   []any{"contact.email", "account.owner.email"},
					},
				},
				map[string]any{
					"id":   "target",
					"uses": "tool.call",
					"input": map[string]any{
						"accepts":         []any{map[string]any{"kind": "object"}},
						"required_facets": []any{"email.recipient"},
					},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("CreateDraft() error = %v", err)
	}
	initial, err := service.CheckDraftEdgeCompatibility(ctx, draft.ID, EdgeCompatibilityRequest{
		SourceNodeID: "source",
		TargetNodeID: "target",
	})
	if err != nil {
		t.Fatalf("CheckDraftEdgeCompatibility() initial error = %v", err)
	}
	if initial.Compatibility.Status != contracts.CompatibilityNeedsUserChoice {
		t.Fatalf("initial compatibility = %#v, want needs_user_choice", initial.Compatibility)
	}

	result, err := service.SaveAdapterChoice(ctx, AdapterChoiceRequest{
		DraftID:      draft.ID,
		SourceNodeID: "source",
		TargetNodeID: "target",
		ChoiceIDs:    []string{initial.Compatibility.Choices[0].ID},
	})
	if err != nil {
		t.Fatalf("SaveAdapterChoice() error = %v", err)
	}
	if result.Adapter.Kind != adapters.KindMapping {
		t.Fatalf("adapter = %#v, want mapping adapter", result.Adapter)
	}
	after, err := service.CheckDraftEdgeCompatibility(ctx, draft.ID, EdgeCompatibilityRequest{
		SourceNodeID: "source",
		TargetNodeID: "target",
	})
	if err != nil {
		t.Fatalf("CheckDraftEdgeCompatibility() after error = %v", err)
	}
	if after.Compatibility.Status != contracts.CompatibilityAdapted || after.Compatibility.AdapterRef != result.Artifact.ID {
		t.Fatalf("after compatibility = %#v, want reusable adapter ref %q", after.Compatibility, result.Artifact.ID)
	}
	if after.SuggestedAdapter.Kind != adapters.KindMapping {
		t.Fatalf("suggested adapter = %#v, want persisted mapping adapter", after.SuggestedAdapter)
	}
}

// TestDesignAssistantPersistsValidatedArtifacts verifies suggestions persist only deterministic artifacts.
func TestDesignAssistantPersistsValidatedArtifacts(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
		DesignAssistant: staticDesignAssistant{artifacts: []DesignArtifact{
			{
				Kind: "mapping",
				Name: "Email to Approval",
				Body: map[string]any{
					"apiVersion": "aa.mapping/v1",
					"kind":       "Mapping",
					"name":       "email-to-approval",
					"steps": []any{
						map[string]any{"set": map[string]any{
							"target": "approval.title",
							"value":  map[string]any{"expr": `"Approve " + input.body.value.subject`},
						}},
					},
				},
			},
			{
				Kind: "tool_manifest",
				Name: "Send Email",
				Body: map[string]any{
					"id":      "aa.mail.send",
					"version": "1",
					"title":   "Send Email",
					"input": map[string]any{
						"required_facets": []any{"email.recipient"},
					},
				},
			},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	result, err := service.SuggestDesignArtifacts(ctx, DesignSuggestionRequest{Prompt: "map email to approval"})
	if err != nil {
		t.Fatalf("SuggestDesignArtifacts() error = %v", err)
	}
	if len(result.Artifacts) != 2 {
		t.Fatalf("artifacts = %#v, want two persisted artifacts", result.Artifacts)
	}
	stored, err := service.ListDesignArtifacts(ctx)
	if err != nil {
		t.Fatalf("ListDesignArtifacts() error = %v", err)
	}
	if len(stored) != 2 {
		t.Fatalf("stored artifacts = %#v, want two", stored)
	}
}

// TestDesignAssistantRejectsInvalidArtifacts verifies assistant output is validated.
func TestDesignAssistantRejectsInvalidArtifacts(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
		DesignAssistant: staticDesignAssistant{artifacts: []DesignArtifact{{
			Kind: "mapping",
			Body: map[string]any{"steps": []any{}},
		}}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	if _, err := service.SuggestDesignArtifacts(ctx, DesignSuggestionRequest{Prompt: "bad mapping"}); err == nil {
		t.Fatalf("SuggestDesignArtifacts() error = nil, want invalid artifact rejected")
	}
}

// TestDesignAssistantPersistsFacetAndExplanationArtifacts verifies phase-four artifact kinds.
func TestDesignAssistantPersistsFacetAndExplanationArtifacts(t *testing.T) {
	ctx := context.Background()
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
		DesignAssistant: staticDesignAssistant{artifacts: []DesignArtifact{
			{
				Kind: "facet_suggestion",
				Body: map[string]any{
					"tool_id":       "aa.crm.lookup",
					"contract_side": "output",
					"facets":        []any{"customer.email"},
					"observed_fields": []any{
						map[string]any{"path": "customer.email", "type": "string", "facet": "customer.email"},
					},
				},
			},
			{
				Kind: "workflow_explanation",
				Body: map[string]any{
					"workflow_id": "email_approval",
					"summary":     "Customer email is mapped into the approval recipient facet.",
					"decisions":   []any{"Use a mapping adapter for semantic alignment."},
				},
			},
		}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	result, err := service.SuggestDesignArtifacts(ctx, DesignSuggestionRequest{Prompt: "explain facets"})
	if err != nil {
		t.Fatalf("SuggestDesignArtifacts() error = %v", err)
	}
	if len(result.Artifacts) != 2 {
		t.Fatalf("artifacts = %#v, want two persisted artifacts", result.Artifacts)
	}
}

// TestDesignAssistantVerifiesExternalManifestArtifacts verifies external tools are signed.
func TestDesignAssistantVerifiesExternalManifestArtifacts(t *testing.T) {
	ctx := context.Background()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateKey() error = %v", err)
	}
	manifest := contracts.ToolManifest{
		ID:      "vendor.mail.send",
		Version: "1",
		Source:  contracts.ManifestSourceExternal,
		Runtime: contracts.Runtime{Sandbox: contracts.RuntimeSandboxProcess},
		Signing: contracts.Signing{
			SignerID:  "vendor",
			Algorithm: "ed25519",
		},
	}
	digest, err := contracts.ManifestDigest(manifest)
	if err != nil {
		t.Fatalf("ManifestDigest() error = %v", err)
	}
	manifest.Signing.Digest = digest
	manifest.Signing.Signature = base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, []byte(digest)))
	body, err := mapFromJSON(manifest)
	if err != nil {
		t.Fatalf("mapFromJSON() error = %v", err)
	}
	service, err := Open(ctx, Config{
		DefinitionsDir: t.TempDir(),
		DatabasePath:   filepath.Join(t.TempDir(), "workflow.db"),
		RequestTimeout: time.Second,
		TrustedSigners: []contracts.TrustedSigner{{
			ID:        "vendor",
			Algorithm: "ed25519",
			PublicKey: base64.StdEncoding.EncodeToString(publicKey),
		}},
		DesignAssistant: staticDesignAssistant{artifacts: []DesignArtifact{{
			Kind: "tool_manifest",
			Body: body,
		}}},
	})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	defer service.Close()

	if _, err := service.SuggestDesignArtifacts(ctx, DesignSuggestionRequest{Prompt: "external manifest"}); err != nil {
		t.Fatalf("SuggestDesignArtifacts() error = %v", err)
	}
}

// TestWorkflowDraftPublishPreservesEdges verifies pipe edges are published.
func TestWorkflowDraftPublishPreservesEdges(t *testing.T) {
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
		Kind: definition.KindWorkflow,
		Body: map[string]any{
			"kind": definition.KindWorkflow,
			"id":   "hierarchy_publish",
			"nodes": []any{
				map[string]any{"id": "first", "uses": "data.assert", "with": map[string]any{"path": "body.value.ready", "mode": "exists"}},
				map[string]any{"id": "second", "uses": "data.assert", "with": map[string]any{"path": "body.value.ready", "mode": "exists"}},
			},
			"edges": []any{
				map[string]any{"from": map[string]any{"node": "first"}, "to": map[string]any{"node": "second"}},
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
	if len(loaded.Definition.Edges) != 1 || loaded.Definition.Edges[0].From.Node != "first" {
		t.Fatalf("published edges = %#v, want first -> second", loaded.Definition.Edges)
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

// storePackage returns a small package record for authoring tests.
func storePackage(id string) store.PackageRecord {
	return store.PackageRecord{
		ID:      id,
		Name:    "Email Triage",
		Version: "0.1.0",
		Body:    map[string]any{"workflows": []any{}},
	}
}

// staticDesignAssistant returns fixed artifacts for authoring tests.
type staticDesignAssistant struct {
	artifacts []DesignArtifact
}

// SuggestDesignArtifacts returns configured test artifacts.
func (a staticDesignAssistant) SuggestDesignArtifacts(context.Context, DesignSuggestionRequest) ([]DesignArtifact, error) {
	return a.artifacts, nil
}
