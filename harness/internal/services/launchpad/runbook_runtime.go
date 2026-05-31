// This file adapts runbook runtime services to the Launchpad executor port.
package launchpad

import (
	"context"
	"encoding/json"
	"fmt"

	runbookdefinition "agentawesome/internal/services/runbook/definition"
	runbookruntime "agentawesome/internal/services/runbook/runtime"
)

// RuntimeRunbookExecutor adapts the runbook runtime to Launchpad.
type RuntimeRunbookExecutor struct {
	service *runbookruntime.Service
}

// NewRuntimeRunbookExecutor creates a runbook runtime adapter.
func NewRuntimeRunbookExecutor(service *runbookruntime.Service) RuntimeRunbookExecutor {
	return RuntimeRunbookExecutor{service: service}
}

// StartRunbook starts one runbook run through the runtime service.
func (e RuntimeRunbookExecutor) StartRunbook(ctx context.Context, definitionID string, input map[string]any) (RunbookRun, error) {
	run, err := e.service.StartRunbook(ctx, definitionID, input)
	if err != nil {
		return RunbookRun{}, err
	}
	return RunbookRun{ID: run.ID, DefinitionID: run.DefinitionID, Status: run.Status, Input: run.Input}, nil
}

// RunbookDefaults returns runbook-level input defaults and definition hash.
func (e RuntimeRunbookExecutor) RunbookDefaults(ctx context.Context, definitionID string) (map[string]any, string, error) {
	if _, err := e.service.ListDefinitions(ctx); err != nil {
		return nil, "", err
	}
	def, ok := e.service.DescribeDefinition(definitionID)
	if !ok {
		return nil, "", fmt.Errorf("runbook definition %q not found", definitionID)
	}
	return authoringInputDefaults(def), definitionHash(def), nil
}

// authoringInputDefaults extracts runbook authoring defaults.
func authoringInputDefaults(def runbookdefinition.Definition) map[string]any {
	raw, _ := def.Authoring["input_defaults"].(map[string]any)
	out := map[string]any{}
	for key, value := range raw {
		out[key] = value
	}
	return out
}

// definitionHash creates a stable hash-like version string from a definition.
func definitionHash(def runbookdefinition.Definition) string {
	data, _ := json.Marshal(def)
	return hashString(data)
}
