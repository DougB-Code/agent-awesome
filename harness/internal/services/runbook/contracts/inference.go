// This file infers partial contracts from observed example data.
package contracts

import (
	"sort"
	"strings"

	"agentawesome/internal/services/runbook/envelope"
)

// InferObservedContract infers a partial output contract from example outputs.
func InferObservedContract(samples []map[string]any) (Contract, []ObservedField) {
	fields := map[string]ObservedField{}
	for _, sample := range samples {
		walkObservedFields("", sample, fields)
	}
	observed := make([]ObservedField, 0, len(fields))
	facets := []string{}
	paths := make([]string, 0, len(fields))
	for path := range fields {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	for _, path := range paths {
		field := fields[path]
		field.Facet, field.Confidence = inferredFacet(field.Path, field.Type)
		if field.Facet != "" {
			facets = append(facets, field.Facet)
		}
		observed = append(observed, field)
	}
	return Contract{
		Produces: []Carrier{{Kind: envelope.BodyKindObject}},
		Facets:   uniqueStrings(facets),
		Schema: map[string]any{
			"type":       "object",
			"properties": observedSchemaProperties(observed),
		},
	}, observed
}

// WithInferredExamples fills missing contract declarations from examples.
func WithInferredExamples(contract Contract) Contract {
	samples := exampleSamples(contract.Examples)
	if len(samples) == 0 {
		return contract
	}
	inferred, _ := InferObservedContract(samples)
	if len(contract.Produces) == 0 {
		contract.Produces = inferred.Produces
	}
	if len(contract.Accepts) == 0 {
		contract.Accepts = inferred.Produces
	}
	if len(contract.Facets) == 0 {
		contract.Facets = inferred.Facets
	}
	if len(contract.Schema) == 0 {
		contract.Schema = inferred.Schema
	}
	return contract
}

// exampleSamples extracts non-empty example output shapes.
func exampleSamples(examples []Example) []map[string]any {
	samples := make([]map[string]any, 0, len(examples))
	for _, example := range examples {
		if len(example.OutputShape) > 0 {
			samples = append(samples, example.OutputShape)
		}
	}
	return samples
}

// walkObservedFields records deterministic field paths and coarse JSON types.
func walkObservedFields(prefix string, value any, fields map[string]ObservedField) {
	if prefix != "" {
		recordObservedField(prefix, schemaTypeName(value), fields)
	}
	switch typed := value.(type) {
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			childPath := strings.TrimSpace(key)
			if childPath == "" {
				continue
			}
			if prefix != "" {
				childPath = prefix + "." + childPath
			}
			walkObservedFields(childPath, typed[key], fields)
		}
	case []any:
		for _, item := range typed {
			if _, ok := item.(map[string]any); ok {
				walkObservedFields(prefix+"[]", item, fields)
			}
		}
	}
}

// recordObservedField stores the first type or marks later conflicts as mixed.
func recordObservedField(path string, typeName string, fields map[string]ObservedField) {
	if existing, ok := fields[path]; ok {
		if existing.Type != typeName {
			existing.Type = "mixed"
			fields[path] = existing
		}
		return
	}
	fields[path] = ObservedField{Path: path, Type: typeName}
}

// schemaTypeName converts common Go values into JSON-schema type names.
func schemaTypeName(value any) string {
	switch value.(type) {
	case nil:
		return "null"
	case map[string]any:
		return "object"
	case []any:
		return "array"
	case string:
		return "string"
	case bool:
		return "boolean"
	case int, int8, int16, int32, int64:
		return "integer"
	case uint, uint8, uint16, uint32, uint64:
		return "integer"
	case float32, float64:
		return "number"
	default:
		return "string"
	}
}

// inferredFacet derives a semantic facet name from an observed field.
func inferredFacet(path string, typeName string) (string, string) {
	normalized := normalizeFacetPath(path)
	tokens := semanticTokenSet(normalized)
	if tokens["email"] && typeName == "string" {
		return normalized, "high"
	}
	if (tokens["total"] || tokens["amount"] || tokens["price"] || tokens["cost"]) && (typeName == "number" || typeName == "integer") {
		return normalized, "medium"
	}
	if tokens["id"] && typeName == "string" {
		return normalized, "low"
	}
	return "", ""
}

// normalizeFacetPath makes an observed path suitable for semantic matching.
func normalizeFacetPath(path string) string {
	normalized := strings.ToLower(strings.TrimSpace(path))
	normalized = strings.ReplaceAll(normalized, "[]", "")
	normalized = strings.NewReplacer("-", "_", "/", ".").Replace(normalized)
	for strings.Contains(normalized, "..") {
		normalized = strings.ReplaceAll(normalized, "..", ".")
	}
	return strings.Trim(normalized, ".")
}

// semanticTokenSet splits a normalized path into lookup tokens.
func semanticTokenSet(value string) map[string]bool {
	tokens := map[string]bool{}
	for _, token := range strings.FieldsFunc(value, func(r rune) bool {
		return r == '.' || r == '_' || r == '-' || r == '/' || r == ' '
	}) {
		trimmed := strings.TrimSpace(token)
		if trimmed != "" {
			tokens[trimmed] = true
		}
	}
	return tokens
}

// observedSchemaProperties converts flattened observations into object schema.
func observedSchemaProperties(observed []ObservedField) map[string]any {
	properties := map[string]any{}
	for _, field := range observed {
		path := normalizeFacetPath(field.Path)
		if path == "" || strings.Contains(path, "[]") {
			continue
		}
		addSchemaProperty(properties, strings.Split(path, "."), field.Type)
	}
	return properties
}

// addSchemaProperty inserts one observed path into a nested schema map.
func addSchemaProperty(properties map[string]any, parts []string, typeName string) {
	if len(parts) == 0 || strings.TrimSpace(parts[0]) == "" {
		return
	}
	name := strings.TrimSpace(parts[0])
	schema, _ := properties[name].(map[string]any)
	if schema == nil {
		schema = map[string]any{}
		properties[name] = schema
	}
	if len(parts) == 1 {
		if typeName != "mixed" {
			schema["type"] = typeName
		}
		return
	}
	schema["type"] = "object"
	childProperties, _ := schema["properties"].(map[string]any)
	if childProperties == nil {
		childProperties = map[string]any{}
		schema["properties"] = childProperties
	}
	addSchemaProperty(childProperties, parts[1:], typeName)
}
