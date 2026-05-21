// This file decodes JSON-backed command template configuration.
package command

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// ParseTemplatesJSON decodes JSON command templates from host configuration.
func ParseTemplatesJSON(value string) ([]Template, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	var raw []rawTemplate
	if err := json.Unmarshal([]byte(value), &raw); err != nil {
		return nil, fmt.Errorf("decode command templates: %w", err)
	}
	templates := make([]Template, 0, len(raw))
	for _, item := range raw {
		timeout, err := parseOptionalDuration(item.Timeout)
		if err != nil {
			return nil, fmt.Errorf("template %q timeout: %w", item.ID, err)
		}
		templates = append(templates, Template{
			ID:                     item.ID,
			Description:            item.Description,
			Executable:             item.Executable,
			Args:                   item.Args,
			Stdin:                  item.Stdin,
			WorkingDir:             item.WorkingDir,
			Env:                    item.Env,
			Timeout:                timeout,
			MaxOutputBytes:         item.MaxOutputBytes,
			RequireApproval:        item.RequireApproval,
			ParameterSchema:        item.ParameterSchema,
			OutputContract:         item.OutputContract,
			ParserID:               item.ParserID,
			OutputSource:           item.OutputSource,
			ArtifactGlobs:          item.ArtifactGlobs,
			EnvironmentPolicy:      item.EnvironmentPolicy,
			WorkingDirectoryPolicy: item.WorkingDirectoryPolicy,
			ValidationSchema:       item.ValidationSchema,
		})
	}
	return templates, nil
}

// parseOptionalDuration parses an optional duration string.
func parseOptionalDuration(value string) (time.Duration, error) {
	if strings.TrimSpace(value) == "" {
		return 0, nil
	}
	return time.ParseDuration(value)
}

// rawTemplate stores JSON-friendly command template fields.
type rawTemplate struct {
	ID                     string            `json:"id"`
	Description            string            `json:"description"`
	Executable             string            `json:"executable"`
	Args                   []string          `json:"args"`
	Stdin                  string            `json:"stdin"`
	WorkingDir             string            `json:"working_dir"`
	Env                    map[string]string `json:"env"`
	Timeout                string            `json:"timeout"`
	MaxOutputBytes         int64             `json:"max_output_bytes"`
	RequireApproval        bool              `json:"require_approval"`
	ParameterSchema        map[string]any    `json:"parameter_schema"`
	OutputContract         OutputContract    `json:"output_contract"`
	ParserID               string            `json:"parser_id"`
	OutputSource           string            `json:"output_source"`
	ArtifactGlobs          []string          `json:"artifact_globs"`
	EnvironmentPolicy      map[string]any    `json:"environment_policy"`
	WorkingDirectoryPolicy string            `json:"working_directory_policy"`
	ValidationSchema       map[string]any    `json:"validation_schema"`
}
