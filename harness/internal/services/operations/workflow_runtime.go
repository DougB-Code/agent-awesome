// This file adapts workflow runtime services to the Operations executor port.
package operations

import (
	"context"
	"encoding/json"
	"fmt"

	workflowdefinition "agentawesome/internal/services/workflow/definition"
	workflowruntime "agentawesome/internal/services/workflow/runtime"
)

// RuntimeWorkflowExecutor adapts the workflow runtime to Operations.
type RuntimeWorkflowExecutor struct {
	service *workflowruntime.Service
}

// NewRuntimeWorkflowExecutor creates a workflow runtime adapter.
func NewRuntimeWorkflowExecutor(service *workflowruntime.Service) RuntimeWorkflowExecutor {
	return RuntimeWorkflowExecutor{service: service}
}

// StartWorkflow starts one workflow run through the runtime service.
func (e RuntimeWorkflowExecutor) StartWorkflow(ctx context.Context, definitionID string, input map[string]any) (WorkflowRun, error) {
	run, err := e.service.StartWorkflow(ctx, definitionID, input)
	if err != nil {
		return WorkflowRun{}, err
	}
	return WorkflowRun{ID: run.ID, DefinitionID: run.DefinitionID, Status: run.Status, Input: run.Input}, nil
}

// WorkflowDefaults returns workflow-level input defaults and definition hash.
func (e RuntimeWorkflowExecutor) WorkflowDefaults(ctx context.Context, definitionID string) (map[string]any, string, error) {
	if _, err := e.service.ListDefinitions(ctx); err != nil {
		return nil, "", err
	}
	def, ok := e.service.DescribeDefinition(definitionID)
	if !ok {
		return nil, "", fmt.Errorf("workflow definition %q not found", definitionID)
	}
	return authoringInputDefaults(def), definitionHash(def), nil
}

// authoringInputDefaults extracts workflow authoring defaults.
func authoringInputDefaults(def workflowdefinition.Definition) map[string]any {
	raw, _ := def.Authoring["input_defaults"].(map[string]any)
	out := map[string]any{}
	for key, value := range raw {
		out[key] = value
	}
	return out
}

// definitionHash creates a stable hash-like version string from a definition.
func definitionHash(def workflowdefinition.Definition) string {
	data, _ := json.Marshal(def)
	return hashString(data)
}
