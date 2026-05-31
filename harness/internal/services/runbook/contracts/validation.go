// This file validates runbook envelopes against declared contracts.
package contracts

import (
	"fmt"
	"strings"

	"agentawesome/internal/services/runbook/envelope"
	"agentawesome/internal/services/runbook/jsondata"
)

// ValidateInput validates an envelope against an input contract.
func ValidateInput(env envelope.Envelope, contract Contract) []envelope.Diagnostic {
	env.Normalize()
	contract = WithInferredExamples(contract)
	var diagnostics []envelope.Diagnostic
	diagnostics = append(diagnostics, validateCarriers(env, contract.Accepts, "input")...)
	diagnostics = append(diagnostics, validateRequiredFacets(env, contract.RequiredFacets)...)
	diagnostics = append(diagnostics, validateSchema(env.Body.Value, contract.Schema, "body.value")...)
	return diagnostics
}

// ValidateOutput validates an envelope against an output contract.
func ValidateOutput(env envelope.Envelope, contract Contract) []envelope.Diagnostic {
	env.Normalize()
	contract = WithInferredExamples(contract)
	var diagnostics []envelope.Diagnostic
	diagnostics = append(diagnostics, validateCarriers(env, contract.Produces, "output")...)
	diagnostics = append(diagnostics, validateDeclaredFacets(env, contract.Facets)...)
	diagnostics = append(diagnostics, validateSchema(env.Body.Value, contract.Schema, "body.value")...)
	return diagnostics
}

// validateCarriers checks the envelope body and artifacts against carrier declarations.
func validateCarriers(env envelope.Envelope, carriers []Carrier, label string) []envelope.Diagnostic {
	if len(carriers) == 0 {
		return nil
	}
	for _, carrier := range carriers {
		if carrierMatchesEnvelope(carrier, env) {
			return nil
		}
	}
	return []envelope.Diagnostic{{
		Severity: "error",
		Code:     label + "_carrier_mismatch",
		Path:     "body.kind",
		Message:  fmt.Sprintf("body kind %q does not satisfy declared %s carriers", env.Body.Kind, label),
	}}
}

// validateRequiredFacets checks that every required facet is present.
func validateRequiredFacets(env envelope.Envelope, facets []string) []envelope.Diagnostic {
	var diagnostics []envelope.Diagnostic
	for _, facet := range facets {
		name := strings.TrimSpace(facet)
		if name == "" {
			continue
		}
		if _, ok := env.Facets[name]; !ok {
			diagnostics = append(diagnostics, envelope.Diagnostic{
				Severity: "error",
				Code:     "required_facet_missing",
				Path:     "facets." + name,
				Message:  "required facet " + name + " is missing",
			})
		}
	}
	return diagnostics
}

// validateDeclaredFacets checks that declared output facets are present when required.
func validateDeclaredFacets(env envelope.Envelope, facets []string) []envelope.Diagnostic {
	var diagnostics []envelope.Diagnostic
	for _, facet := range facets {
		name := strings.TrimSpace(facet)
		if name == "" {
			continue
		}
		if _, ok := env.Facets[name]; !ok {
			diagnostics = append(diagnostics, envelope.Diagnostic{
				Severity: "warning",
				Code:     "declared_facet_missing",
				Path:     "facets." + name,
				Message:  "declared output facet " + name + " was not produced",
			})
		}
	}
	return diagnostics
}

// carrierMatchesEnvelope reports whether a carrier accepts the envelope.
func carrierMatchesEnvelope(carrier Carrier, env envelope.Envelope) bool {
	kind := strings.TrimSpace(carrier.Kind)
	if kind != "" && kind != env.Body.Kind {
		return false
	}
	if len(carrier.MediaTypes) == 0 {
		return true
	}
	allowed := stringSet(carrier.MediaTypes)
	for _, artifact := range env.Artifacts {
		if allowed[strings.TrimSpace(artifact.MediaType)] {
			return true
		}
	}
	return false
}

// validateSchema checks a deterministic JSON-schema subset.
func validateSchema(value any, schema map[string]any, path string) []envelope.Diagnostic {
	errors := jsondata.ValidateSchema(value, schema, path, false)
	diagnostics := make([]envelope.Diagnostic, 0, len(errors))
	for _, err := range errors {
		diagnostics = append(diagnostics, envelope.Diagnostic{
			Severity: "error",
			Code:     err.Code,
			Path:     err.Path,
			Message:  err.Message,
		})
	}
	return diagnostics
}
