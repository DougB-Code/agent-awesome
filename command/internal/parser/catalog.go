// This file loads and executes Starlark parser files from a local catalog.
package parser

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"go.starlark.net/starlark"
)

var safeParserIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// Catalog resolves parser ids to Starlark files.
type Catalog struct {
	dir string
}

// Input carries one completed process result into a parser.
type Input struct {
	Stdout   string
	Stderr   string
	ExitCode int
	Status   string
}

// NewCatalog creates a parser catalog rooted at dir.
func NewCatalog(dir string) (*Catalog, error) {
	trimmed := strings.TrimSpace(dir)
	if trimmed == "" {
		return nil, fmt.Errorf("parser directory is required")
	}
	abs, err := filepath.Abs(trimmed)
	if err != nil {
		return nil, fmt.Errorf("resolve parser directory: %w", err)
	}
	return &Catalog{dir: filepath.Clean(abs)}, nil
}

// Dir returns the normalized parser catalog directory.
func (c *Catalog) Dir() string {
	if c == nil {
		return ""
	}
	return c.dir
}

// Parse loads one parser file, validates parse(), and returns its generic map.
func (c *Catalog) Parse(ctx context.Context, id string, input Input) (map[string]any, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	path, err := c.parserPath(id)
	if err != nil {
		return nil, err
	}
	globals, err := starlark.ExecFile(&starlark.Thread{Name: "command-parser:" + id}, path, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("load parser %q: %w", id, err)
	}
	parseValue, ok := globals["parse"]
	if !ok {
		return nil, fmt.Errorf("parser %q must export parse", id)
	}
	parseFn, ok := parseValue.(*starlark.Function)
	if !ok {
		return nil, fmt.Errorf("parser %q parse export must be a function", id)
	}
	if err := validateParseFunction(id, parseFn); err != nil {
		return nil, err
	}
	result, err := starlark.Call(
		&starlark.Thread{Name: "command-parser-call:" + id},
		parseFn,
		starlark.Tuple{
			starlark.String(input.Stdout),
			starlark.String(input.Stderr),
			starlark.MakeInt(input.ExitCode),
			starlark.String(input.Status),
		},
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("run parser %q: %w", id, err)
	}
	converted, err := toGoValue(result)
	if err != nil {
		return nil, fmt.Errorf("convert parser %q result: %w", id, err)
	}
	resultMap, ok := converted.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("parser %q result must be a dictionary", id)
	}
	return resultMap, nil
}

// parserPath resolves one safe parser id to its catalog file.
func (c *Catalog) parserPath(id string) (string, error) {
	if c == nil {
		return "", fmt.Errorf("parser catalog is not configured")
	}
	trimmed := strings.TrimSpace(id)
	if trimmed == "" {
		return "", fmt.Errorf("parser id is required")
	}
	if !safeParserIDPattern.MatchString(trimmed) {
		return "", fmt.Errorf("parser id %q is invalid", trimmed)
	}
	path := filepath.Join(c.dir, trimmed+".star")
	if _, err := os.Stat(path); err != nil {
		return "", fmt.Errorf("parser %q: %w", trimmed, err)
	}
	return path, nil
}

// validateParseFunction enforces the parser ABI using Starlark metadata.
func validateParseFunction(id string, fn *starlark.Function) error {
	want := []string{"stdout", "stderr", "exit_code", "status"}
	if fn.NumParams() != len(want) || fn.NumKwonlyParams() != 0 {
		return fmt.Errorf("parser %q parse must accept stdout, stderr, exit_code, status", id)
	}
	for index, name := range want {
		got, _ := fn.Param(index)
		if got != name {
			return fmt.Errorf("parser %q parse parameter %d = %q, want %q", id, index+1, got, name)
		}
	}
	return nil
}

// toGoValue converts Starlark values into JSON-compatible Go values.
func toGoValue(value starlark.Value) (any, error) {
	switch typed := value.(type) {
	case starlark.NoneType:
		return nil, nil
	case starlark.Bool:
		return bool(typed), nil
	case starlark.String:
		return typed.GoString(), nil
	case starlark.Int:
		if intValue, ok := typed.Int64(); ok {
			return intValue, nil
		}
		return typed.String(), nil
	case starlark.Float:
		return float64(typed), nil
	case *starlark.Dict:
		out := map[string]any{}
		for _, item := range typed.Items() {
			key, err := toGoValue(item[0])
			if err != nil {
				return nil, err
			}
			keyString, ok := key.(string)
			if !ok {
				return nil, fmt.Errorf("dictionary key %s is not a string", item[0].String())
			}
			value, err := toGoValue(item[1])
			if err != nil {
				return nil, err
			}
			out[keyString] = value
		}
		return out, nil
	case *starlark.List:
		return iterableToSlice(typed)
	case starlark.Tuple:
		return iterableToSlice(typed)
	default:
		return nil, fmt.Errorf("unsupported value type %s", value.Type())
	}
}

// iterableToSlice converts an iterable Starlark sequence to a Go slice.
func iterableToSlice(value starlark.Iterable) ([]any, error) {
	var items []any
	iter := value.Iterate()
	defer iter.Done()
	var item starlark.Value
	for iter.Next(&item) {
		converted, err := toGoValue(item)
		if err != nil {
			return nil, err
		}
		items = append(items, converted)
	}
	return items, nil
}
