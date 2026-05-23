// This file loads workflow definitions from YAML files.
package definition

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// LoadedDefinition couples a validated definition with its source metadata.
type LoadedDefinition struct {
	Definition Definition `json:"definition"`
	Path       string     `json:"path"`
	Hash       string     `json:"hash"`
	Body       []byte     `json:"-"`
}

// LoadWarning records one definition file skipped during tolerant loading.
type LoadWarning struct {
	Path    string `json:"path"`
	Message string `json:"message"`
}

// LoadDirectory reads and validates every YAML workflow definition in a directory.
func LoadDirectory(dir string, actions ActionCatalog) ([]LoadedDefinition, error) {
	loaded, warnings, err := loadDirectory(dir, actions, false)
	if err != nil {
		return nil, err
	}
	if len(warnings) > 0 {
		return nil, fmt.Errorf("%s: %s", warnings[0].Path, warnings[0].Message)
	}
	return loaded, nil
}

// LoadDirectorySkippingInvalid reads valid workflow definitions and reports skipped files.
func LoadDirectorySkippingInvalid(dir string, actions ActionCatalog) ([]LoadedDefinition, []LoadWarning, error) {
	return loadDirectory(dir, actions, true)
}

// loadDirectory implements strict and tolerant directory loading.
func loadDirectory(dir string, actions ActionCatalog, skipInvalid bool) ([]LoadedDefinition, []LoadWarning, error) {
	trimmed := strings.TrimSpace(dir)
	if trimmed == "" {
		return nil, nil, fmt.Errorf("definitions directory is required")
	}
	entries, err := os.ReadDir(trimmed)
	if err != nil {
		if os.IsNotExist(err) {
			return []LoadedDefinition{}, nil, nil
		}
		return nil, nil, fmt.Errorf("read workflow definitions directory %q: %w", trimmed, err)
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, ".yaml") || strings.HasSuffix(name, ".yml") {
			paths = append(paths, filepath.Join(trimmed, name))
		}
	}
	sort.Strings(paths)

	loaded := make([]LoadedDefinition, 0, len(paths))
	warnings := []LoadWarning{}
	seen := map[string]struct{}{}
	for _, path := range paths {
		def, err := LoadFile(path, actions)
		if err != nil {
			if skipInvalid {
				warnings = append(warnings, LoadWarning{Path: path, Message: err.Error()})
				continue
			}
			return nil, nil, err
		}
		if _, ok := seen[def.Definition.ID]; ok {
			return nil, warnings, fmt.Errorf("duplicate workflow definition %q", def.Definition.ID)
		}
		seen[def.Definition.ID] = struct{}{}
		loaded = append(loaded, def)
	}
	return loaded, warnings, nil
}

// LoadFile reads and validates one YAML workflow definition file.
func LoadFile(path string, actions ActionCatalog) (LoadedDefinition, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return LoadedDefinition{}, fmt.Errorf("read workflow definition %q: %w", path, err)
	}
	var def Definition
	decoder := yaml.NewDecoder(bytes.NewReader(body))
	decoder.KnownFields(true)
	if err := decoder.Decode(&def); err != nil {
		return LoadedDefinition{}, fmt.Errorf("decode workflow definition %q: %w", path, err)
	}
	if err := Validate(def, actions); err != nil {
		return LoadedDefinition{}, fmt.Errorf("%s: %w", path, err)
	}
	normalized, err := json.Marshal(def)
	if err != nil {
		return LoadedDefinition{}, fmt.Errorf("normalize workflow definition %q: %w", path, err)
	}
	hash := sha256.Sum256(normalized)
	return LoadedDefinition{
		Definition: def,
		Path:       path,
		Hash:       hex.EncodeToString(hash[:]),
		Body:       normalized,
	}, nil
}
