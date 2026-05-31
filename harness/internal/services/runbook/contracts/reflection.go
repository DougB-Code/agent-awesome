// This file generates initial contracts from AA-authored Go structs.
package contracts

import (
	"fmt"
	"reflect"
	"strings"
)

// InputContractFromStruct returns an object input contract inferred from a Go struct.
func InputContractFromStruct(value any) (Contract, error) {
	contract, err := StructContract(value)
	if err != nil {
		return Contract{}, err
	}
	contract.Accepts = []Carrier{{Kind: "object"}}
	return contract, nil
}

// OutputContractFromStruct returns an object output contract inferred from a Go struct.
func OutputContractFromStruct(value any) (Contract, error) {
	contract, err := StructContract(value)
	if err != nil {
		return Contract{}, err
	}
	contract.Produces = []Carrier{{Kind: "object"}}
	return contract, nil
}

// StructContract converts exported JSON fields and AA tags into a contract.
func StructContract(value any) (Contract, error) {
	typ := reflect.TypeOf(value)
	for typ != nil && typ.Kind() == reflect.Pointer {
		typ = typ.Elem()
	}
	if typ == nil || typ.Kind() != reflect.Struct {
		return Contract{}, fmt.Errorf("contract reflection requires a struct value")
	}
	properties := map[string]any{}
	requiredFields := []any{}
	facets := []string{}
	requiredFacets := []string{}
	for index := 0; index < typ.NumField(); index++ {
		field := typ.Field(index)
		if field.PkgPath != "" {
			continue
		}
		name, omitEmpty, ok := jsonFieldName(field)
		if !ok {
			continue
		}
		properties[name] = schemaForType(field.Type)
		tag := parseAATag(field.Tag.Get("aa"))
		if tag.Required {
			requiredFields = append(requiredFields, name)
		}
		if tag.Facet != "" {
			facets = append(facets, tag.Facet)
			if tag.Required || !omitEmpty {
				requiredFacets = append(requiredFacets, tag.Facet)
			}
		}
	}
	schema := map[string]any{
		"type":       "object",
		"properties": properties,
	}
	if len(requiredFields) > 0 {
		schema["required"] = requiredFields
	}
	return Contract{
		Schema:         schema,
		Facets:         facets,
		RequiredFacets: requiredFacets,
	}, nil
}

// jsonFieldName resolves the JSON property name for an exported struct field.
func jsonFieldName(field reflect.StructField) (string, bool, bool) {
	tag := field.Tag.Get("json")
	if tag == "-" {
		return "", false, false
	}
	parts := strings.Split(tag, ",")
	name := strings.TrimSpace(parts[0])
	if name == "" {
		name = strings.ToLower(field.Name[:1]) + field.Name[1:]
	}
	omitEmpty := false
	for _, option := range parts[1:] {
		if strings.TrimSpace(option) == "omitempty" {
			omitEmpty = true
		}
	}
	return name, omitEmpty, true
}

// schemaForType maps a Go type to the deterministic JSON-schema subset.
func schemaForType(typ reflect.Type) map[string]any {
	for typ.Kind() == reflect.Pointer {
		typ = typ.Elem()
	}
	switch typ.Kind() {
	case reflect.Bool:
		return map[string]any{"type": "boolean"}
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return map[string]any{"type": "integer"}
	case reflect.Float32, reflect.Float64:
		return map[string]any{"type": "number"}
	case reflect.Slice, reflect.Array:
		return map[string]any{"type": "array", "items": schemaForType(typ.Elem())}
	case reflect.Map, reflect.Struct:
		return map[string]any{"type": "object"}
	default:
		return map[string]any{"type": "string"}
	}
}

// parseAATag extracts runbook contract metadata from an aa struct tag.
func parseAATag(value string) aaTag {
	result := aaTag{}
	for _, part := range strings.Split(value, ",") {
		trimmed := strings.TrimSpace(part)
		switch {
		case trimmed == "required":
			result.Required = true
		case strings.HasPrefix(trimmed, "facet="):
			result.Facet = strings.TrimSpace(strings.TrimPrefix(trimmed, "facet="))
		}
	}
	return result
}

// aaTag stores supported AA reflection tag options.
type aaTag struct {
	Facet    string
	Required bool
}
