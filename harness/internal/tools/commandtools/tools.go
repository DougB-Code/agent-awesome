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
	Templates []command.TemplateSummary `json:"templates"`
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
		return TemplateListResult{Templates: service.Templates()}, nil
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
