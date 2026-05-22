// This file defines workflow runtime configuration.
package runtime

import (
	"context"
	"time"

	"agentawesome/internal/services/workflow/actions"
)

// ContextToolClient invokes harness-owned context tools for workflow actions.
type ContextToolClient interface {
	List(context.Context) ([]string, error)
	Call(context.Context, actions.ToolRequest) (map[string]any, error)
}

// Config stores service endpoints and durable paths for workflow execution.
type Config struct {
	DefinitionsDir        string
	DatabasePath          string
	HarnessContextBaseURL string
	RequestTimeout        time.Duration
	ToolClient            ContextToolClient
}
