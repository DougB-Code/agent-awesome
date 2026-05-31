// This file executes Starlark app plugin entrypoints.
package appplugins

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"go.starlark.net/starlark"
)

const defaultMaxExecutionSteps = 1_000_000

// RenderPackage executes one package-local Starlark entrypoint and returns the
// rendered app plugin manifest.
func RenderPackage(ctx context.Context, packageDir, entrypoint string) (map[string]any, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	path, err := entrypointPath(packageDir, entrypoint)
	if err != nil {
		return nil, err
	}
	return RenderFile(ctx, path)
}

// RenderFile executes one Starlark file that exports render().
func RenderFile(ctx context.Context, path string) (map[string]any, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return nil, fmt.Errorf("app plugin entrypoint path is required")
	}
	loadThread, stopLoadCancel := starlarkThread(ctx, "app-plugin:"+filepath.Base(trimmed))
	defer stopLoadCancel()
	globals, err := starlark.ExecFile(loadThread, trimmed, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("load app plugin entrypoint: %w", err)
	}
	renderValue, ok := globals["render"]
	if !ok {
		return nil, fmt.Errorf("app plugin entrypoint must export render")
	}
	renderFn, ok := renderValue.(*starlark.Function)
	if !ok {
		return nil, fmt.Errorf("app plugin render export must be a function")
	}
	if err := validateRenderFunction(renderFn); err != nil {
		return nil, err
	}
	renderThread, stopRenderCancel := starlarkThread(ctx, "app-plugin-render")
	defer stopRenderCancel()
	result, err := starlark.Call(renderThread, renderFn, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("run app plugin render: %w", err)
	}
	converted, err := toGoValue(result)
	if err != nil {
		return nil, fmt.Errorf("convert app plugin render result: %w", err)
	}
	resultMap, ok := converted.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("app plugin render result must be a dictionary")
	}
	return resultMap, nil
}

// starlarkThread creates a bounded Starlark thread linked to context cancelation.
func starlarkThread(ctx context.Context, name string) (*starlark.Thread, func()) {
	thread := &starlark.Thread{Name: name}
	thread.SetMaxExecutionSteps(defaultMaxExecutionSteps)
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			thread.Cancel(ctx.Err().Error())
		case <-done:
		}
	}()
	return thread, func() { close(done) }
}

// entrypointPath returns a package-local entrypoint path.
func entrypointPath(packageDir, entrypoint string) (string, error) {
	root := strings.TrimSpace(packageDir)
	if root == "" {
		return "", fmt.Errorf("app plugin package directory is required")
	}
	entry := filepath.Clean(strings.TrimSpace(entrypoint))
	if entry == "." || entry == "" {
		entry = "app.star"
	}
	if filepath.IsAbs(entry) || strings.HasPrefix(entry, ".."+string(filepath.Separator)) || entry == ".." {
		return "", fmt.Errorf("app plugin entrypoint must be package-local")
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve app plugin package directory: %w", err)
	}
	path := filepath.Join(absRoot, entry)
	absPath, err := filepath.Abs(path)
	if err != nil {
		return "", fmt.Errorf("resolve app plugin entrypoint: %w", err)
	}
	relative, err := filepath.Rel(absRoot, absPath)
	if err != nil {
		return "", fmt.Errorf("check app plugin entrypoint boundary: %w", err)
	}
	if strings.HasPrefix(relative, ".."+string(filepath.Separator)) || relative == ".." {
		return "", fmt.Errorf("app plugin entrypoint escapes package directory")
	}
	if _, err := os.Stat(absPath); err != nil {
		return "", fmt.Errorf("app plugin entrypoint: %w", err)
	}
	return absPath, nil
}

// validateRenderFunction enforces the app plugin render ABI.
func validateRenderFunction(fn *starlark.Function) error {
	if fn.NumParams() != 0 || fn.NumKwonlyParams() != 0 {
		return fmt.Errorf("app plugin render must accept no parameters")
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
