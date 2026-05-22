// This file implements the edge compatibility chain of responsibility.
package compatibility

import (
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/mapping"
)

// Result reports the compatibility decision for an edge.
type Result = contracts.Compatibility

// Engine stores reusable adapter ids by source and target tool pair.
type Engine struct {
	reusable map[string]string
}

// NewEngine creates a compatibility engine with no reusable adapters.
func NewEngine() *Engine {
	return &Engine{reusable: map[string]string{}}
}

// RegisterAdapter remembers one reusable adapter for a source-target pair.
func (e *Engine) RegisterAdapter(sourceTool string, targetTool string, adapterRef string) {
	if e.reusable == nil {
		e.reusable = map[string]string{}
	}
	e.reusable[pairKey(sourceTool, targetTool)] = strings.TrimSpace(adapterRef)
}

// Check runs the compatibility pipeline for one prospective edge.
func (e *Engine) Check(source contracts.ToolManifest, target contracts.ToolManifest, adapter adapters.Definition) Result {
	if adapters.Declared(adapter) {
		base := contracts.CheckCompatibility(source.Output, target.Input)
		if base.Status == contracts.CompatibilityBlocked {
			return Result{Status: contracts.CompatibilityAdapted, Confidence: "medium", Explanation: "Explicit adapter will transform the source output."}
		}
		base.Status = contracts.CompatibilityAdapted
		base.Explanation = "Explicit adapter will transform the source output."
		return base
	}
	if ref, ok := e.reusable[pairKey(source.ID, target.ID)]; ok {
		return Result{Status: contracts.CompatibilityAdapted, Confidence: "high", AdapterRef: ref, Explanation: "Reusable adapter exists for this source and target."}
	}
	return contracts.CheckCompatibility(source.Output, target.Input)
}

// SuggestAdapter creates a deterministic adapter when a compatibility result is actionable.
func SuggestAdapter(source contracts.ToolManifest, target contracts.ToolManifest, result Result) adapters.Definition {
	switch result.Status {
	case contracts.CompatibilityDirect:
		return adapters.Definition{Kind: adapters.KindDirect}
	case contracts.CompatibilityAdapted:
		if len(result.Choices) > 0 {
			return AdapterForChoices(source, target, result.Choices)
		}
		if adapter := artifactAdapter(source.Output, target.Input); strings.TrimSpace(adapter.Kind) != "" {
			return adapter
		}
	}
	return adapters.Definition{}
}

// AdapterForChoices creates a mapping adapter from confirmed semantic choices.
func AdapterForChoices(source contracts.ToolManifest, target contracts.ToolManifest, choices []contracts.CompatibilityChoice) adapters.Definition {
	if len(choices) == 0 {
		return adapters.Definition{}
	}
	return facetMappingAdapter(source.ID, target.ID, choices)
}

// facetMappingAdapter builds a deterministic mapping adapter for semantic choices.
func facetMappingAdapter(sourceID string, targetID string, choices []contracts.CompatibilityChoice) adapters.Definition {
	spec := mapping.Spec{
		APIVersion: "aa.mapping/v1",
		Kind:       "Mapping",
		Name:       adapterName(sourceID, targetID),
		Steps:      make([]mapping.StepDefinition, 0, len(choices)),
	}
	for _, choice := range choices {
		spec.Steps = append(spec.Steps, mapping.StepDefinition{Set: &mapping.SetStep{
			Target: "output.facets." + strings.TrimSpace(choice.TargetFacet),
			Value:  mapping.ValueSpec{Path: strings.TrimSpace(choice.SourcePath)},
		}})
	}
	return adapters.Definition{Kind: adapters.KindMapping, Mapping: &spec}
}

// artifactAdapter returns a first-matching artifact adapter for file carriers.
func artifactAdapter(source contracts.Contract, target contracts.Contract) adapters.Definition {
	for _, accepted := range target.Accepts {
		if strings.TrimSpace(accepted.Kind) != "file" && strings.TrimSpace(accepted.Kind) != "files" {
			continue
		}
		for _, produced := range source.Produces {
			if strings.TrimSpace(produced.Kind) != "file" && strings.TrimSpace(produced.Kind) != "files" {
				continue
			}
			mediaType := firstMediaType(produced.MediaTypes, accepted.MediaTypes)
			return adapters.Definition{
				Kind:      adapters.KindSelect,
				Strategy:  adapters.StrategyFirstMatchingArtifact,
				MediaType: mediaType,
				Target:    "input",
			}
		}
	}
	return adapters.Definition{}
}

// firstMediaType returns the most specific shared media type.
func firstMediaType(source []string, target []string) string {
	if len(target) == 0 {
		if len(source) == 0 {
			return ""
		}
		return strings.TrimSpace(source[0])
	}
	sourceSet := map[string]bool{}
	for _, mediaType := range source {
		sourceSet[strings.TrimSpace(mediaType)] = true
	}
	for _, mediaType := range target {
		trimmed := strings.TrimSpace(mediaType)
		if len(source) == 0 || sourceSet[trimmed] {
			return trimmed
		}
	}
	return ""
}

// adapterName creates a readable generated mapping name.
func adapterName(sourceID string, targetID string) string {
	name := strings.TrimSpace(sourceID) + "-to-" + strings.TrimSpace(targetID)
	name = strings.NewReplacer(".", "-", "_", "-", "/", "-").Replace(name)
	if strings.Trim(name, "-") == "" {
		return "generated-mapping"
	}
	return fmt.Sprintf("generated-%s", strings.Trim(name, "-"))
}

// pairKey creates a stable source-target lookup key.
func pairKey(sourceTool string, targetTool string) string {
	return strings.TrimSpace(sourceTool) + "->" + strings.TrimSpace(targetTool)
}
