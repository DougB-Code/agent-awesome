// This file normalizes runtime tool schemas for OpenAI function declarations.
package openai

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/jsonschema-go/jsonschema"
	"github.com/openai/openai-go/shared"
	"google.golang.org/genai"
)

// openAIParametersSchema converts a runtime declaration schema into OpenAI
// function parameters.
func openAIParametersSchema(value any) (shared.FunctionParameters, error) {
	normalized, err := openAIJSONSchema(value)
	if err != nil {
		return nil, err
	}
	if normalized == nil {
		return shared.FunctionParameters{
			"type":       "object",
			"properties": map[string]any{},
		}, nil
	}
	if schemaBool, ok := normalized.(bool); ok {
		if !schemaBool {
			return nil, fmt.Errorf("parameters schema must allow an object")
		}
		return shared.FunctionParameters{
			"type":       "object",
			"properties": map[string]any{},
		}, nil
	}
	schema, ok := normalized.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("parameters schema must be an object, got %T", normalized)
	}
	if len(schema) == 0 {
		schema["type"] = "object"
		schema["properties"] = map[string]any{}
	}
	if _, ok := schema["type"]; !ok {
		schema["type"] = "object"
	}
	if schema["type"] == "object" {
		if _, ok := schema["properties"]; !ok {
			schema["properties"] = map[string]any{}
		}
	}
	return shared.FunctionParameters(schema), nil
}

// openAIJSONSchema recursively converts supported schema values into plain JSON
// Schema-compatible values.
func openAIJSONSchema(value any) (any, error) {
	switch typed := value.(type) {
	case nil:
		return nil, nil
	case *jsonschema.Schema:
		return openAIGoogleJSONSchema(typed)
	case jsonschema.Schema:
		return openAIGoogleJSONSchema(&typed)
	case *genai.Schema:
		return openAIGenAISchema(typed)
	case genai.Schema:
		return openAIGenAISchema(&typed)
	case map[string]any:
		return openAIMapSchema(typed)
	case map[string]*genai.Schema:
		return openAIGenAIProperties(typed)
	case map[string]genai.Schema:
		return openAIGenAIValueProperties(typed)
	case []any:
		return openAISliceSchema(typed)
	case []*genai.Schema:
		return openAIGenAIAnyOf(typed)
	case []string:
		return append([]string(nil), typed...), nil
	case string, bool, float64, float32, int, int8, int16, int32, int64, uint, uint8, uint16, uint32, uint64:
		return typed, nil
	default:
		return nil, fmt.Errorf("unsupported schema value %T", value)
	}
}

// openAIGoogleJSONSchema converts an ADK JSON schema into plain JSON values.
func openAIGoogleJSONSchema(schema *jsonschema.Schema) (any, error) {
	if schema == nil {
		return nil, nil
	}
	raw, err := json.Marshal(schema)
	if err != nil {
		return nil, fmt.Errorf("marshal json schema: %w", err)
	}
	var decoded any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, fmt.Errorf("decode json schema: %w", err)
	}
	return openAIJSONSchema(decoded)
}

// openAIGenAISchema converts a Google GenAI schema into OpenAI-compatible JSON
// Schema fields.
func openAIGenAISchema(schema *genai.Schema) (map[string]any, error) {
	if schema == nil {
		return map[string]any{}, nil
	}
	out := make(map[string]any)
	if schemaType := openAITypeName(string(schema.Type)); schemaType != "" {
		out["type"] = schemaType
	}
	if schema.Title != "" {
		out["title"] = schema.Title
	}
	if schema.Description != "" {
		out["description"] = schema.Description
	}
	if schema.Format != "" && !strings.EqualFold(schema.Format, "enum") {
		out["format"] = schema.Format
	}
	if len(schema.Enum) > 0 {
		out["enum"] = append([]string(nil), schema.Enum...)
	}
	if schema.Default != nil {
		value, err := openAIJSONSchema(schema.Default)
		if err != nil {
			return nil, fmt.Errorf("default: %w", err)
		}
		out["default"] = value
	}
	if schema.Example != nil {
		value, err := openAIJSONSchema(schema.Example)
		if err != nil {
			return nil, fmt.Errorf("example: %w", err)
		}
		out["example"] = value
	}
	if schema.Items != nil {
		items, err := openAIGenAISchema(schema.Items)
		if err != nil {
			return nil, fmt.Errorf("items: %w", err)
		}
		out["items"] = items
	}
	if len(schema.Properties) > 0 {
		properties, err := openAIGenAIProperties(schema.Properties)
		if err != nil {
			return nil, fmt.Errorf("properties: %w", err)
		}
		out["properties"] = properties
	} else if out["type"] == "object" {
		out["properties"] = map[string]any{}
	}
	if len(schema.Required) > 0 {
		out["required"] = append([]string(nil), schema.Required...)
	}
	if len(schema.AnyOf) > 0 {
		anyOf, err := openAIGenAIAnyOf(schema.AnyOf)
		if err != nil {
			return nil, fmt.Errorf("anyOf: %w", err)
		}
		out["anyOf"] = anyOf
	}
	if schema.Pattern != "" {
		out["pattern"] = schema.Pattern
	}
	openAISetIntPointer(out, "maxItems", schema.MaxItems)
	openAISetIntPointer(out, "minItems", schema.MinItems)
	openAISetIntPointer(out, "maxLength", schema.MaxLength)
	openAISetIntPointer(out, "minLength", schema.MinLength)
	openAISetIntPointer(out, "maxProperties", schema.MaxProperties)
	openAISetIntPointer(out, "minProperties", schema.MinProperties)
	openAISetFloatPointer(out, "maximum", schema.Maximum)
	openAISetFloatPointer(out, "minimum", schema.Minimum)
	if schema.Nullable != nil && *schema.Nullable {
		openAIAddNullableType(out)
	}
	return out, nil
}

// openAIMapSchema recursively normalizes map-backed JSON schema values.
func openAIMapSchema(schema map[string]any) (map[string]any, error) {
	out := make(map[string]any, len(schema))
	for key, value := range schema {
		if key == "nullable" || key == "propertyOrdering" {
			continue
		}
		normalized, err := openAIJSONSchema(value)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", key, err)
		}
		if key == "type" {
			schemaType := openAIJSONSchemaType(normalized)
			if openAISchemaTypeEmpty(schemaType) {
				continue
			}
			out[key] = schemaType
			continue
		}
		out[key] = normalized
	}
	return out, nil
}

// openAIGenAIProperties converts GenAI object properties into JSON schema
// property values.
func openAIGenAIProperties(properties map[string]*genai.Schema) (map[string]any, error) {
	out := make(map[string]any, len(properties))
	for name, property := range properties {
		normalized, err := openAIGenAISchema(property)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		out[name] = normalized
	}
	return out, nil
}

// openAIGenAIValueProperties converts value-backed GenAI properties into JSON
// schema property values.
func openAIGenAIValueProperties(properties map[string]genai.Schema) (map[string]any, error) {
	out := make(map[string]any, len(properties))
	for name, property := range properties {
		normalized, err := openAIGenAISchema(&property)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		out[name] = normalized
	}
	return out, nil
}

// openAISliceSchema recursively normalizes JSON schema arrays.
func openAISliceSchema(values []any) ([]any, error) {
	out := make([]any, 0, len(values))
	for i, value := range values {
		normalized, err := openAIJSONSchema(value)
		if err != nil {
			return nil, fmt.Errorf("[%d]: %w", i, err)
		}
		out = append(out, normalized)
	}
	return out, nil
}

// openAIGenAIAnyOf converts GenAI subschemas into JSON schema arrays.
func openAIGenAIAnyOf(values []*genai.Schema) ([]any, error) {
	out := make([]any, 0, len(values))
	for i, value := range values {
		normalized, err := openAIGenAISchema(value)
		if err != nil {
			return nil, fmt.Errorf("[%d]: %w", i, err)
		}
		out = append(out, normalized)
	}
	return out, nil
}

// openAIJSONSchemaType normalizes JSON schema type declarations.
func openAIJSONSchemaType(value any) any {
	switch typed := value.(type) {
	case string:
		return openAITypeName(typed)
	case []string:
		out := make([]string, 0, len(typed))
		for _, item := range typed {
			if name := openAITypeName(item); name != "" {
				out = append(out, name)
			}
		}
		return out
	case []any:
		out := make([]any, 0, len(typed))
		for _, item := range typed {
			normalized := openAIJSONSchemaType(item)
			if !openAISchemaTypeEmpty(normalized) {
				out = append(out, normalized)
			}
		}
		return out
	default:
		return value
	}
}

// openAITypeName maps Google/OpenAPI type names to JSON schema type names.
func openAITypeName(value string) string {
	switch strings.ToUpper(strings.TrimSpace(value)) {
	case "", string(genai.TypeUnspecified):
		return ""
	case string(genai.TypeString):
		return "string"
	case string(genai.TypeNumber):
		return "number"
	case string(genai.TypeInteger):
		return "integer"
	case string(genai.TypeBoolean):
		return "boolean"
	case string(genai.TypeArray):
		return "array"
	case string(genai.TypeObject):
		return "object"
	case string(genai.TypeNULL):
		return "null"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

// openAISchemaTypeEmpty reports whether a normalized type should be omitted.
func openAISchemaTypeEmpty(value any) bool {
	switch typed := value.(type) {
	case string:
		return typed == ""
	case []string:
		return len(typed) == 0
	case []any:
		return len(typed) == 0
	default:
		return value == nil
	}
}

// openAIAddNullableType appends null to the schema type without using OpenAPI's
// nullable extension.
func openAIAddNullableType(schema map[string]any) {
	schemaType, ok := schema["type"]
	if !ok {
		return
	}
	switch typed := schemaType.(type) {
	case string:
		if typed != "null" {
			schema["type"] = []string{typed, "null"}
		}
	case []string:
		for _, item := range typed {
			if item == "null" {
				return
			}
		}
		schema["type"] = append(append([]string(nil), typed...), "null")
	case []any:
		for _, item := range typed {
			if item == "null" {
				return
			}
		}
		schema["type"] = append(append([]any(nil), typed...), "null")
	}
}

// openAISetIntPointer copies integer constraints when present.
func openAISetIntPointer(schema map[string]any, key string, value *int64) {
	if value != nil {
		schema[key] = *value
	}
}

// openAISetFloatPointer copies numeric constraints when present.
func openAISetFloatPointer(schema map[string]any, key string, value *float64) {
	if value != nil {
		schema[key] = *value
	}
}
