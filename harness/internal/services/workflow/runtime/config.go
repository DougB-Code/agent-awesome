// This file defines workflow runtime configuration.
package runtime

import (
	"context"
	"time"

	"agentawesome/internal/services/command/command"
	"agentawesome/internal/services/workflow/actions"
	"agentawesome/internal/services/workflow/contracts"
)

// ContextToolClient invokes harness-owned context tools for workflow actions.
type ContextToolClient interface {
	List(context.Context) ([]string, error)
	Call(context.Context, actions.ToolRequest) (map[string]any, error)
}

// CommandClient executes configured command templates for workflow actions.
type CommandClient interface {
	Execute(context.Context, command.ExecuteRequest) (command.StatusResult, error)
}

// LLMClient generates structured workflow output through a configured model boundary.
type LLMClient interface {
	GenerateWorkflowJSON(context.Context, actions.LLMRequest) (map[string]any, error)
}

// DesignAssistant proposes deterministic workflow artifacts at design time.
type DesignAssistant interface {
	SuggestDesignArtifacts(context.Context, DesignSuggestionRequest) ([]DesignArtifact, error)
}

// Config stores service endpoints and durable paths for workflow execution.
type Config struct {
	DefinitionsDir                  string
	DatabasePath                    string
	HarnessContextBaseURL           string
	RequestTimeout                  time.Duration
	ToolClient                      ContextToolClient
	CommandClient                   CommandClient
	MCPServerEndpoints              map[string]string
	LLMClient                       LLMClient
	DesignAssistant                 DesignAssistant
	TrustedSigners                  []contracts.TrustedSigner
	ObservedContractReviewThreshold int
	SkipInvalidDefinitions          bool
}
