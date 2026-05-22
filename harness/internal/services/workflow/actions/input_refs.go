// This file resolves simple data references in action arguments.
package actions

import (
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/jsondata"
)

// resolveInputRefs recursively replaces ${path.to.value} references from input.
func resolveInputRefs(value any, input map[string]any) any {
	switch typed := value.(type) {
	case string:
		return resolveInputRefString(typed, input)
	case map[string]any:
		next := make(map[string]any, len(typed))
		for key, item := range typed {
			next[key] = resolveInputRefs(item, input)
		}
		return next
	case []any:
		next := make([]any, len(typed))
		for index, item := range typed {
			next[index] = resolveInputRefs(item, input)
		}
		return next
	default:
		return value
	}
}

// resolveInputRefString resolves whole-string and embedded input references.
func resolveInputRefString(value string, input map[string]any) any {
	trimmed := strings.TrimSpace(value)
	if strings.HasPrefix(trimmed, "${") && strings.HasSuffix(trimmed, "}") && strings.Count(trimmed, "${") == 1 {
		if resolved, ok := resolveReferencePath(input, strings.TrimSuffix(strings.TrimPrefix(trimmed, "${"), "}")); ok {
			return resolved
		}
		return value
	}
	result := value
	for {
		start := strings.Index(result, "${")
		if start < 0 {
			return result
		}
		end := strings.Index(result[start:], "}")
		if end < 0 {
			return result
		}
		end += start
		path := result[start+2 : end]
		resolved, ok := resolveReferencePath(input, path)
		if !ok {
			return result
		}
		result = result[:start] + fmt.Sprint(resolved) + result[end+1:]
	}
}

// resolveReferencePath looks up a dotted path in action input.
func resolveReferencePath(input map[string]any, path string) (any, bool) {
	return jsondata.Dotted(input, strings.TrimSpace(path))
}

// resolvedStringArg returns a string action argument after reference resolution.
func resolvedStringArg(args map[string]any, key string, input map[string]any) string {
	value, ok := args[key]
	if !ok {
		return ""
	}
	resolved := resolveInputRefs(value, input)
	text, _ := resolved.(string)
	return strings.TrimSpace(text)
}

// resolvedMapArg returns a map action argument after reference resolution.
func resolvedMapArg(args map[string]any, key string, fallback map[string]any, input map[string]any) map[string]any {
	value, ok := args[key]
	if !ok {
		return fallback
	}
	resolved := resolveInputRefs(value, input)
	if resolvedMap, ok := resolved.(map[string]any); ok {
		return resolvedMap
	}
	return fallback
}
