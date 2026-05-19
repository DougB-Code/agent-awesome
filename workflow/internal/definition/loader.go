// This file loads workflow definitions from YAML files.
package definition

import (
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

// LoadDirectory reads and validates every YAML workflow definition in a directory.
func LoadDirectory(dir string, actions ActionCatalog) ([]LoadedDefinition, error) {
	trimmed := strings.TrimSpace(dir)
	if trimmed == "" {
		return nil, fmt.Errorf("definitions directory is required")
	}
	entries, err := os.ReadDir(trimmed)
	if err != nil {
		if os.IsNotExist(err) {
			return []LoadedDefinition{}, nil
		}
		return nil, fmt.Errorf("read workflow definitions directory %q: %w", trimmed, err)
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
	seen := map[string]struct{}{}
	for _, path := range paths {
		def, err := LoadFile(path, actions)
		if err != nil {
			return nil, err
		}
		if _, ok := seen[def.Definition.ID]; ok {
			return nil, fmt.Errorf("duplicate workflow definition %q", def.Definition.ID)
		}
		seen[def.Definition.ID] = struct{}{}
		loaded = append(loaded, def)
	}
	return loaded, nil
}

// LoadFile reads and validates one YAML workflow definition file.
func LoadFile(path string, actions ActionCatalog) (LoadedDefinition, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return LoadedDefinition{}, fmt.Errorf("read workflow definition %q: %w", path, err)
	}
	var def Definition
	if err := yaml.Unmarshal(body, &def); err != nil {
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
