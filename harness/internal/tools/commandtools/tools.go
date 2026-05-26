// This file exposes command service operations as direct ADK function tools.
package commandtools

import (
	"fmt"

	"agentawesome/internal/services/command/command"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/functiontool"
)

const (
	executeToolName  = "command_execute"
	templateToolName = "command_template_list"
	statusToolName   = "command_status"
)

// TemplateListRequest stores the argument object for listing command templates.
type TemplateListRequest struct{}

// TemplateListResult stores sanitized command templates visible to agents.
type TemplateListResult struct {
	Templates []TemplateSummary `json:"templates"`
}

// TemplateSummary describes one configured command template for ADK tools.
type TemplateSummary struct {
	ID                     string                 `json:"id"`
	Description            string                 `json:"description"`
	Parameters             []string               `json:"parameters,omitempty"`
	Timeout                string                 `json:"timeout,omitempty"`
	MaxOutputBytes         int64                  `json:"max_output_bytes,omitempty"`
	ParameterSchema        map[string]any         `json:"parameter_schema,omitempty"`
	OutputContract         command.OutputContract `json:"output_contract,omitempty"`
	ParserID               string                 `json:"parser_id,omitempty"`
	OutputSource           string                 `json:"output_source,omitempty"`
	ArtifactGlobs          []string               `json:"artifact_globs,omitempty"`
	EnvironmentPolicy      map[string]any         `json:"environment_policy,omitempty"`
	WorkingDirectoryPolicy string                 `json:"working_directory_policy,omitempty"`
	Surface                CommandSurfaceSummary  `json:"surface,omitempty"`
	Annotations            map[string]any         `json:"annotations,omitempty"`
}

// CommandSurfaceSummary stores non-recursive CLI surface metadata for ADK schema generation.
type CommandSurfaceSummary struct {
	GlobalFlags []command.CommandFlag      `json:"global_flags,omitempty"`
	Subcommands []CommandSubcommandSummary `json:"subcommands,omitempty"`
}

// CommandSubcommandSummary describes one flattened CLI command path.
type CommandSubcommandSummary struct {
	Command     string                `json:"command"`
	Description string                `json:"description,omitempty"`
	Flags       []command.CommandFlag `json:"flags,omitempty"`
}

// StatusRequest stores the command job id to inspect.
type StatusRequest struct {
	JobID string `json:"job_id"`
}

// New creates ADK function tools backed by the command service.
func New(service *command.Service) ([]tool.Tool, error) {
	if service == nil {
		return nil, fmt.Errorf("command service is required")
	}
	executeTool, err := functiontool.New(functiontool.Config{
		Name:                executeToolName,
		Description:         "Run one configured command template and return its bounded structured result.",
		RequireConfirmation: true,
	}, func(ctx tool.Context, req command.ExecuteRequest) (command.StatusResult, error) {
		return service.Execute(ctx, req)
	})
	if err != nil {
		return nil, fmt.Errorf("create %s tool: %w", executeToolName, err)
	}
	templateTool, err := functiontool.New(functiontool.Config{
		Name:        templateToolName,
		Description: "List configured command templates.",
	}, func(_ tool.Context, _ TemplateListRequest) (TemplateListResult, error) {
		return TemplateListResult{Templates: commandToolTemplateSummaries(service.Templates())}, nil
	})
	if err != nil {
		return nil, fmt.Errorf("create %s tool: %w", templateToolName, err)
	}
	statusTool, err := functiontool.New(functiontool.Config{
		Name:        statusToolName,
		Description: "Read command job status and bounded output tails.",
	}, func(ctx tool.Context, req StatusRequest) (command.StatusResult, error) {
		return service.Status(ctx, req.JobID)
	})
	if err != nil {
		return nil, fmt.Errorf("create %s tool: %w", statusToolName, err)
	}
	return []tool.Tool{executeTool, templateTool, statusTool}, nil
}

// commandToolTemplateSummaries converts service summaries to ADK-friendly DTOs.
func commandToolTemplateSummaries(values []command.TemplateSummary) []TemplateSummary {
	summaries := make([]TemplateSummary, 0, len(values))
	for _, value := range values {
		summaries = append(summaries, commandToolTemplateSummary(value))
	}
	return summaries
}

// commandToolTemplateSummary converts one command template summary.
func commandToolTemplateSummary(value command.TemplateSummary) TemplateSummary {
	return TemplateSummary{
		ID:                     value.ID,
		Description:            value.Description,
		Parameters:             append([]string(nil), value.Parameters...),
		Timeout:                value.Timeout,
		MaxOutputBytes:         value.MaxOutputBytes,
		ParameterSchema:        value.ParameterSchema,
		OutputContract:         value.OutputContract,
		ParserID:               value.ParserID,
		OutputSource:           value.OutputSource,
		ArtifactGlobs:          append([]string(nil), value.ArtifactGlobs...),
		EnvironmentPolicy:      value.EnvironmentPolicy,
		WorkingDirectoryPolicy: value.WorkingDirectoryPolicy,
		Surface:                commandToolSurfaceSummary(value.Surface),
		Annotations:            value.Annotations,
	}
}

// commandToolSurfaceSummary flattens recursive CLI metadata for schema-safe output.
func commandToolSurfaceSummary(surface command.CommandSurface) CommandSurfaceSummary {
	subcommands := []CommandSubcommandSummary{}
	appendCommandToolSubcommands(&subcommands, nil, surface.Subcommands)
	return CommandSurfaceSummary{
		GlobalFlags: append([]command.CommandFlag(nil), surface.GlobalFlags...),
		Subcommands: subcommands,
	}
}

// appendCommandToolSubcommands appends one flattened row for each command path.
func appendCommandToolSubcommands(rows *[]CommandSubcommandSummary, parent []string, values []command.CommandSubcommand) {
	for _, value := range values {
		path := append(append([]string(nil), parent...), value.Name)
		*rows = append(*rows, CommandSubcommandSummary{
			Command:     joinCommandPath(path),
			Description: value.Description,
			Flags:       append([]command.CommandFlag(nil), value.Flags...),
		})
		appendCommandToolSubcommands(rows, path, value.Subcommands)
	}
}

// joinCommandPath returns a readable CLI path from subcommand tokens.
func joinCommandPath(values []string) string {
	result := ""
	for _, value := range values {
		if value == "" {
			continue
		}
		if result != "" {
			result += " "
		}
		result += value
	}
	return result
}
