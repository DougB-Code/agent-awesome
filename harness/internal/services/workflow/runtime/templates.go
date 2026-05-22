// This file loads built-in workflow templates from embedded YAML assets.
package runtime

import (
	"embed"
	"fmt"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"agentawesome/internal/services/workflow/store"
)

//go:embed templates/*.yaml
var builtInTemplateFS embed.FS

// builtInTemplates returns starter templates backed by package-shaped bodies.
func builtInTemplates() ([]store.TemplateRecord, error) {
	entries, err := builtInTemplateFS.ReadDir("templates")
	if err != nil {
		return nil, fmt.Errorf("read built-in workflow templates: %w", err)
	}
	templates := make([]store.TemplateRecord, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		path := "templates/" + entry.Name()
		data, err := builtInTemplateFS.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read built-in workflow template %s: %w", path, err)
		}
		var record store.TemplateRecord
		if err := yaml.Unmarshal(data, &record); err != nil {
			return nil, fmt.Errorf("decode built-in workflow template %s: %w", path, err)
		}
		if strings.TrimSpace(record.ID) == "" {
			return nil, fmt.Errorf("built-in workflow template %s has no id", path)
		}
		templates = append(templates, record)
	}
	sort.Slice(templates, func(i, j int) bool {
		return templates[i].ID < templates[j].ID
	})
	return templates, nil
}
