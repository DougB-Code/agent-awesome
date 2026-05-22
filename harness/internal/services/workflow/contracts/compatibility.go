// This file evaluates contract compatibility for workflow edges.
package contracts

import (
	"fmt"
	"strings"
)

// CheckCompatibility reports whether a source output can feed a target input.
func CheckCompatibility(source Contract, target Contract) Compatibility {
	source = WithInferredExamples(source)
	target = WithInferredExamples(target)
	if carriersCompatible(source.Produces, target.Accepts) && facetsCover(source.Facets, target.RequiredFacets) {
		return Compatibility{Status: CompatibilityDirect, Confidence: "high", Explanation: "Output carrier and facets satisfy input."}
	}
	choices := semanticChoices(source.Facets, target.RequiredFacets)
	if len(choices) > 0 {
		if hasAmbiguousChoices(choices) {
			return Compatibility{Status: CompatibilityNeedsUserChoice, Confidence: "medium", Explanation: "Multiple semantic fields can satisfy the target input.", Choices: choices}
		}
		return Compatibility{Status: CompatibilityAdapted, Confidence: "medium", Explanation: "Semantic facets can be mapped deterministically.", Choices: choices}
	}
	if facetsOverlap(source.Facets, target.RequiredFacets) {
		return Compatibility{Status: CompatibilityAdapted, Confidence: "medium", Explanation: "Shared semantic facets can be mapped deterministically."}
	}
	if carriersMayAdapt(source.Produces, target.Accepts) {
		return Compatibility{Status: CompatibilityAdapted, Confidence: "medium", Explanation: "Carrier kinds can be adapted with an explicit edge adapter."}
	}
	return Compatibility{Status: CompatibilityBlocked, Confidence: "high", Explanation: "No compatible carrier, facet, or adapter path is declared."}
}

// semanticChoices finds source facets that can satisfy missing target facets.
func semanticChoices(sourceFacets []string, requiredFacets []string) []CompatibilityChoice {
	var choices []CompatibilityChoice
	for _, required := range requiredFacets {
		target := strings.TrimSpace(required)
		if target == "" {
			continue
		}
		if containsString(sourceFacets, target) {
			continue
		}
		for _, source := range sourceFacets {
			candidate := strings.TrimSpace(source)
			if candidate == "" || !semanticallyRelated(candidate, target) {
				continue
			}
			choices = append(choices, CompatibilityChoice{
				ID:          choiceID(candidate, target),
				Label:       fmt.Sprintf("Map %s to %s", candidate, target),
				SourcePath:  "input.facets." + candidate,
				TargetFacet: target,
				Confidence:  "medium",
			})
		}
	}
	return choices
}

// hasAmbiguousChoices reports whether any target facet has multiple candidates.
func hasAmbiguousChoices(choices []CompatibilityChoice) bool {
	counts := map[string]int{}
	for _, choice := range choices {
		counts[choice.TargetFacet]++
	}
	for _, count := range counts {
		if count > 1 {
			return true
		}
	}
	return false
}

// semanticallyRelated reports whether two facet names share meaningful tokens.
func semanticallyRelated(source string, target string) bool {
	sourceTokens := semanticTokenSet(source)
	for _, token := range semanticTokens(target) {
		if sourceTokens[token] {
			return true
		}
	}
	return false
}

// semanticTokenSet builds a lookup of meaningful facet tokens.
func semanticTokenSet(value string) map[string]bool {
	set := map[string]bool{}
	for _, token := range semanticTokens(value) {
		set[token] = true
	}
	return set
}

// semanticTokens splits a facet into matching tokens.
func semanticTokens(value string) []string {
	parts := strings.FieldsFunc(strings.ToLower(strings.TrimSpace(value)), func(r rune) bool {
		return r == '.' || r == '_' || r == '-' || r == '/'
	})
	out := []string{}
	for _, part := range parts {
		if len(part) < 3 || part == "the" || part == "and" {
			continue
		}
		out = append(out, part)
	}
	return out
}

// choiceID creates a stable id for a compatibility choice.
func choiceID(source string, target string) string {
	return strings.NewReplacer(".", "_", "-", "_", "/", "_").Replace(strings.TrimSpace(source) + "__to__" + strings.TrimSpace(target))
}

// carriersCompatible reports whether source and target carriers directly match.
func carriersCompatible(source []Carrier, target []Carrier) bool {
	if len(target) == 0 {
		return true
	}
	if len(source) == 0 {
		return false
	}
	for _, produced := range source {
		for _, accepted := range target {
			if strings.TrimSpace(accepted.Kind) != "" && strings.TrimSpace(produced.Kind) != strings.TrimSpace(accepted.Kind) {
				continue
			}
			if mediaTypesCompatible(produced.MediaTypes, accepted.MediaTypes) {
				return true
			}
		}
	}
	return false
}

// carriersMayAdapt reports whether carrier declarations leave room for adapters.
func carriersMayAdapt(source []Carrier, target []Carrier) bool {
	return len(source) > 0 && len(target) > 0
}

// mediaTypesCompatible reports whether media type constraints overlap.
func mediaTypesCompatible(source []string, target []string) bool {
	if len(target) == 0 {
		return true
	}
	if len(source) == 0 {
		return false
	}
	available := stringSet(source)
	for _, mediaType := range target {
		if available[strings.TrimSpace(mediaType)] {
			return true
		}
	}
	return false
}

// facetsCover reports whether all required facets are produced.
func facetsCover(produced []string, required []string) bool {
	if len(required) == 0 {
		return true
	}
	available := stringSet(produced)
	for _, facet := range required {
		if !available[strings.TrimSpace(facet)] {
			return false
		}
	}
	return true
}

// facetsOverlap reports whether produced facets include at least one requirement.
func facetsOverlap(produced []string, required []string) bool {
	if len(produced) == 0 || len(required) == 0 {
		return false
	}
	available := stringSet(produced)
	for _, facet := range required {
		if available[strings.TrimSpace(facet)] {
			return true
		}
	}
	return false
}
