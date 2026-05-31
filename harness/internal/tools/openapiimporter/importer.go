// This file imports OpenAPI documents into command-backed tool packages.
package openapiimporter

import (
	"encoding/json"
	"fmt"
	"net/url"
	"path"
	"regexp"
	"sort"
	"strings"

	"agentawesome/internal/config/schema"
	"gopkg.in/yaml.v3"
)

var operationNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// Options stores OpenAPI importer settings.
type Options struct {
	Name    string
	BaseURL string
}

// Import parses one OpenAPI document into an AA tool package.
func Import(content []byte, opts Options) (schema.Tools, error) {
	doc, err := decodeDocument(content)
	if err != nil {
		return schema.Tools{}, err
	}
	openapi := stringField(doc, "openapi")
	swagger := stringField(doc, "swagger")
	if openapi == "" && swagger == "" {
		return schema.Tools{}, fmt.Errorf("schema is not an OpenAPI document")
	}
	title := firstNonEmpty(opts.Name, nestedString(doc, "info", "title"), "REST API")
	commandName := safeIdentifier(title, "rest_api")
	baseURL := strings.TrimRight(firstNonEmpty(opts.BaseURL, firstServerURL(doc)), "/")
	paths := mapField(doc, "paths")
	if len(paths) == 0 {
		return schema.Tools{}, fmt.Errorf("OpenAPI document has no paths")
	}
	operations := make([]schema.CommandOperation, 0)
	for pathTemplate, rawPath := range paths {
		pathItem := asMap(rawPath)
		pathParams := parametersFromList(listField(pathItem, "parameters"))
		for _, method := range []string{"get", "post", "put", "patch", "delete", "head"} {
			operationItem := mapField(pathItem, method)
			if len(operationItem) == 0 {
				continue
			}
			operation := buildOperation(method, pathTemplate, operationItem, pathParams, baseURL)
			if operation.Name != "" {
				operations = append(operations, operation)
			}
		}
	}
	if len(operations) == 0 {
		return schema.Tools{}, fmt.Errorf("OpenAPI document has no supported operations")
	}
	sort.SliceStable(operations, func(i, j int) bool {
		return operations[i].Name < operations[j].Name
	})
	return schema.Tools{
		Name: title,
		LocalExec: schema.LocalExec{
			Enabled:        true,
			DefaultTimeout: "30s",
			Commands: []schema.LocalExecCommand{{
				Name:        commandName,
				Executable:  "curl",
				Description: "Call " + title + " REST API operations.",
				Surface: schema.CommandSurface{
					GlobalFlags: []schema.CommandFlag{
						{Name: "-f", Description: "Fail on HTTP server errors."},
						{Name: "-s", Description: "Run silently except for output."},
						{Name: "-S", Description: "Show errors when silent mode fails."},
						{Name: "-L", Description: "Follow redirects."},
						{Name: "-X", Description: "Select the HTTP method."},
						{Name: "-H", Description: "Send one request header."},
						{Name: "-d", Description: "Send a request body."},
					},
				},
				Operations: operations,
			}},
		},
	}, nil
}

// MarshalYAML encodes an imported tool package with AA schema field names.
func MarshalYAML(tools schema.Tools) ([]byte, error) {
	encoded := map[string]any{
		"name": tools.Name,
		"local-exec": map[string]any{
			"enabled":         tools.LocalExec.Enabled,
			"default-timeout": tools.LocalExec.DefaultTimeout,
			"commands":        commandList(tools.LocalExec.Commands),
		},
	}
	if strings.TrimSpace(tools.Version) != "" {
		encoded["version"] = tools.Version
	}
	if strings.TrimSpace(tools.Extends) != "" {
		encoded["extends"] = tools.Extends
	}
	return yaml.Marshal(encoded)
}

// commandList encodes command entries with AA schema field names.
func commandList(commands []schema.LocalExecCommand) []map[string]any {
	out := make([]map[string]any, 0, len(commands))
	for _, command := range commands {
		out = append(out, map[string]any{
			"name":        command.Name,
			"executable":  command.Executable,
			"description": command.Description,
			"surface": map[string]any{
				"global-flags": commandFlags(command.Surface.GlobalFlags),
			},
			"operations": operationList(command.Operations),
		})
	}
	return out
}

// commandFlags encodes command flag metadata.
func commandFlags(flags []schema.CommandFlag) []map[string]any {
	out := make([]map[string]any, 0, len(flags))
	for _, flag := range flags {
		out = append(out, map[string]any{
			"name":        flag.Name,
			"description": flag.Description,
		})
	}
	return out
}

// operationList encodes command operation entries.
func operationList(operations []schema.CommandOperation) []map[string]any {
	out := make([]map[string]any, 0, len(operations))
	for _, operation := range operations {
		out = append(out, map[string]any{
			"name":         operation.Name,
			"description":  operation.Description,
			"args":         operation.Args,
			"input-schema": operation.InputSchema,
			"output": map[string]any{
				"format": operation.Output.Format,
				"source": operation.Output.Source,
			},
		})
	}
	return out
}

// buildOperation creates one curl-backed command operation.
func buildOperation(method string, pathTemplate string, operation map[string]any, pathParams []apiParameter, baseURL string) schema.CommandOperation {
	name := operationName(operation, method, pathTemplate)
	params := mergeParameters(pathParams, parametersFromList(listField(operation, "parameters")))
	required := []string{}
	properties := map[string]any{}
	urlValue := operationURL(baseURL, pathTemplate, params)
	if baseURL == "" {
		required = append(required, "base_url")
		properties["base_url"] = map[string]any{"type": "string", "description": "REST API base URL."}
	}
	for _, param := range params {
		if !param.Required {
			continue
		}
		required = append(required, param.Name)
		properties[param.Name] = param.schema()
	}
	args := []string{"-fsSL", "-X", strings.ToUpper(method), "-H", "Accept: application/json"}
	for _, param := range params {
		if param.In == "header" && param.Required {
			args = append(args, "-H", param.Name+": {{"+param.Name+"}}")
		}
	}
	if requestBodyRequired(operation) {
		required = append(required, "body")
		properties["body"] = map[string]any{"type": "string", "description": "Serialized request body."}
		args = append(args, "-H", "Content-Type: application/json", "-d", "{{body}}")
	}
	args = append(args, urlValue)
	return schema.CommandOperation{
		Name:        name,
		Description: operationDescription(operation, method, pathTemplate),
		Args:        args,
		InputSchema: map[string]any{
			"type":       "object",
			"required":   required,
			"properties": properties,
		},
		Output: schema.CommandOutput{Format: "json", Source: "stdout"},
	}
}

// operationName returns a stable AA operation name.
func operationName(operation map[string]any, method string, pathTemplate string) string {
	if id := stringField(operation, "operationId"); id != "" {
		return safeIdentifier(id, "")
	}
	return safeIdentifier(strings.ToLower(method)+"_"+pathTemplate, "operation")
}

// operationDescription returns a compact user-facing operation description.
func operationDescription(operation map[string]any, method string, pathTemplate string) string {
	for _, key := range []string{"summary", "description"} {
		if value := stringField(operation, key); value != "" {
			return value
		}
	}
	return strings.ToUpper(method) + " " + pathTemplate
}

// operationURL builds the curl URL template for required path and query params.
func operationURL(baseURL string, pathTemplate string, params []apiParameter) string {
	prefix := strings.TrimRight(baseURL, "/")
	if prefix == "" {
		prefix = "{{base_url}}"
	}
	value := prefix + normalizeAPIPath(pathTemplate)
	queryParts := []string{}
	for _, param := range params {
		if param.In != "query" || !param.Required {
			continue
		}
		queryParts = append(queryParts, url.QueryEscape(param.Name)+"={{"+param.Name+"}}")
	}
	if len(queryParts) > 0 {
		value += "?" + strings.Join(queryParts, "&")
	}
	return value
}

// normalizeAPIPath converts OpenAPI path parameters to command placeholders.
func normalizeAPIPath(value string) string {
	if strings.TrimSpace(value) == "" {
		return "/"
	}
	cleaned := path.Clean("/" + strings.TrimLeft(value, "/"))
	parts := strings.Split(cleaned, "/")
	for index, part := range parts {
		if strings.HasPrefix(part, "{") && strings.HasSuffix(part, "}") {
			parts[index] = "{{" + safeIdentifier(strings.Trim(part, "{}"), "param") + "}}"
		}
	}
	return strings.Join(parts, "/")
}

// requestBodyRequired reports whether the operation requires a JSON body.
func requestBodyRequired(operation map[string]any) bool {
	body := mapField(operation, "requestBody")
	return boolField(body, "required")
}

// apiParameter stores the OpenAPI parameter fields the importer needs.
type apiParameter struct {
	Name     string
	In       string
	Required bool
	Schema   map[string]any
}

// schema returns the JSON-schema fragment used by command input validation.
func (p apiParameter) schema() map[string]any {
	out := cloneMap(p.Schema)
	if len(out) == 0 {
		out["type"] = "string"
	}
	return out
}

// parametersFromList parses an OpenAPI parameters array.
func parametersFromList(values []any) []apiParameter {
	params := make([]apiParameter, 0, len(values))
	for _, value := range values {
		item := asMap(value)
		name := safeIdentifier(stringField(item, "name"), "")
		location := strings.TrimSpace(stringField(item, "in"))
		if name == "" || location == "" {
			continue
		}
		params = append(params, apiParameter{
			Name:     name,
			In:       location,
			Required: boolField(item, "required") || location == "path",
			Schema:   mapField(item, "schema"),
		})
	}
	return params
}

// mergeParameters overlays operation parameters on path-level parameters.
func mergeParameters(base []apiParameter, delta []apiParameter) []apiParameter {
	out := append([]apiParameter{}, base...)
	indexByKey := map[string]int{}
	for index, param := range out {
		indexByKey[param.In+":"+param.Name] = index
	}
	for _, param := range delta {
		key := param.In + ":" + param.Name
		if index, ok := indexByKey[key]; ok {
			out[index] = param
			continue
		}
		indexByKey[key] = len(out)
		out = append(out, param)
	}
	return out
}

// decodeDocument decodes JSON or YAML OpenAPI content.
func decodeDocument(content []byte) (map[string]any, error) {
	var decoded any
	if err := json.Unmarshal(content, &decoded); err != nil {
		if err := yaml.Unmarshal(content, &decoded); err != nil {
			return nil, fmt.Errorf("decode OpenAPI schema: %w", err)
		}
	}
	doc := asMap(decoded)
	if len(doc) == 0 {
		return nil, fmt.Errorf("OpenAPI schema must be an object")
	}
	return doc, nil
}

// firstServerURL returns the first configured OpenAPI server URL.
func firstServerURL(doc map[string]any) string {
	servers := listField(doc, "servers")
	if len(servers) == 0 {
		return ""
	}
	return stringField(asMap(servers[0]), "url")
}

// safeIdentifier converts arbitrary OpenAPI names into AA command identifiers.
func safeIdentifier(value string, fallback string) string {
	var builder strings.Builder
	lastUnderscore := false
	for _, r := range strings.TrimSpace(value) {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			builder.WriteRune(r)
			lastUnderscore = false
		default:
			if !lastUnderscore && builder.Len() > 0 {
				builder.WriteByte('_')
				lastUnderscore = true
			}
		}
	}
	out := strings.Trim(builder.String(), "_")
	if out == "" {
		out = fallback
	}
	if out == "" {
		return ""
	}
	if !operationNamePattern.MatchString(out) {
		out = "_" + out
	}
	return out
}

// asMap converts decoded JSON/YAML objects into string-keyed maps.
func asMap(value any) map[string]any {
	switch typed := value.(type) {
	case map[string]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[key] = normalizeValue(item)
		}
		return out
	case map[any]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			out[fmt.Sprint(key)] = normalizeValue(item)
		}
		return out
	default:
		return map[string]any{}
	}
}

// normalizeValue converts YAML maps and slices into JSON-like values.
func normalizeValue(value any) any {
	switch typed := value.(type) {
	case map[string]any, map[any]any:
		return asMap(typed)
	case []any:
		out := make([]any, 0, len(typed))
		for _, item := range typed {
			out = append(out, normalizeValue(item))
		}
		return out
	default:
		return typed
	}
}

// mapField returns one object field as a map.
func mapField(values map[string]any, key string) map[string]any {
	return asMap(values[key])
}

// listField returns one object field as a list.
func listField(values map[string]any, key string) []any {
	if list, ok := values[key].([]any); ok {
		return list
	}
	return nil
}

// stringField returns one object field as a trimmed string.
func stringField(values map[string]any, key string) string {
	if value, ok := values[key].(string); ok {
		return strings.TrimSpace(value)
	}
	return ""
}

// nestedString returns one nested string field.
func nestedString(values map[string]any, outer string, inner string) string {
	return stringField(mapField(values, outer), inner)
}

// boolField returns one object field as a bool.
func boolField(values map[string]any, key string) bool {
	value, _ := values[key].(bool)
	return value
}

// cloneMap copies JSON-like schema data.
func cloneMap(values map[string]any) map[string]any {
	out := make(map[string]any, len(values))
	for key, value := range values {
		out[key] = normalizeValue(value)
	}
	return out
}

// firstNonEmpty returns the first non-empty trimmed value.
func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
}
