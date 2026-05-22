// This file tests pipe graph compatibility decisions.
package compatibility

import (
	"testing"

	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/contracts"
)

// TestEngineReportsDirectAndBlockedCompatibility verifies deterministic edge decisions.
func TestEngineReportsDirectAndBlockedCompatibility(t *testing.T) {
	engine := NewEngine()
	direct := engine.Check(
		contracts.ToolManifest{ID: "source", Output: contracts.Contract{Produces: []contracts.Carrier{{Kind: "object"}}, Facets: []string{"customer.email"}}},
		contracts.ToolManifest{ID: "target", Input: contracts.Contract{Accepts: []contracts.Carrier{{Kind: "object"}}, RequiredFacets: []string{"customer.email"}}},
		adapters.Definition{},
	)
	if direct.Status != contracts.CompatibilityDirect {
		t.Fatalf("direct status = %q, want direct", direct.Status)
	}

	blocked := engine.Check(
		contracts.ToolManifest{ID: "source", Output: contracts.Contract{}},
		contracts.ToolManifest{ID: "target", Input: contracts.Contract{Accepts: []contracts.Carrier{{Kind: "file"}}, RequiredFacets: []string{"document.text"}}},
		adapters.Definition{},
	)
	if blocked.Status != contracts.CompatibilityBlocked {
		t.Fatalf("blocked status = %q, want blocked", blocked.Status)
	}
}

// TestEngineReportsUserChoiceForAmbiguousSemanticFacets verifies ambiguous edges pause for choice.
func TestEngineReportsUserChoiceForAmbiguousSemanticFacets(t *testing.T) {
	result := NewEngine().Check(
		contracts.ToolManifest{ID: "crm", Output: contracts.Contract{
			Produces: []contracts.Carrier{{Kind: "object"}},
			Facets:   []string{"contact.email", "account.owner.email"},
		}},
		contracts.ToolManifest{ID: "send", Input: contracts.Contract{
			Accepts:        []contracts.Carrier{{Kind: "object"}},
			RequiredFacets: []string{"email.recipient"},
		}},
		adapters.Definition{},
	)

	if result.Status != contracts.CompatibilityNeedsUserChoice {
		t.Fatalf("status = %q, want needs_user_choice", result.Status)
	}
	if len(result.Choices) != 2 {
		t.Fatalf("choices = %#v, want two email choices", result.Choices)
	}
}

// TestSuggestAdapterBuildsFacetMapping verifies automatic semantic mappings become adapters.
func TestSuggestAdapterBuildsFacetMapping(t *testing.T) {
	source := contracts.ToolManifest{ID: "crm", Output: contracts.Contract{
		Produces: []contracts.Carrier{{Kind: "object"}},
		Facets:   []string{"customer.email"},
	}}
	target := contracts.ToolManifest{ID: "send", Input: contracts.Contract{
		Accepts:        []contracts.Carrier{{Kind: "object"}},
		RequiredFacets: []string{"email.recipient"},
	}}
	result := NewEngine().Check(source, target, adapters.Definition{})

	if result.Status != contracts.CompatibilityAdapted {
		t.Fatalf("status = %q, want adapted", result.Status)
	}
	adapter := SuggestAdapter(source, target, result)
	if adapter.Kind != adapters.KindMapping || adapter.Mapping == nil || len(adapter.Mapping.Steps) != 1 {
		t.Fatalf("adapter = %#v, want one mapping step", adapter)
	}
}

// TestSuggestAdapterBuildsArtifactSelection verifies file carrier adaptation is concrete.
func TestSuggestAdapterBuildsArtifactSelection(t *testing.T) {
	source := contracts.ToolManifest{ID: "email", Output: contracts.Contract{
		Produces: []contracts.Carrier{{Kind: "files", MediaTypes: []string{"application/pdf"}}},
	}}
	target := contracts.ToolManifest{ID: "pdf", Input: contracts.Contract{
		Accepts: []contracts.Carrier{{Kind: "file", MediaTypes: []string{"application/pdf"}}},
	}}
	result := NewEngine().Check(source, target, adapters.Definition{})
	adapter := SuggestAdapter(source, target, result)

	if adapter.Kind != adapters.KindSelect || adapter.Strategy != adapters.StrategyFirstMatchingArtifact || adapter.MediaType != "application/pdf" {
		t.Fatalf("adapter = %#v, want first PDF artifact selection", adapter)
	}
}
