// This file defines runbook runtime configuration.
package runtime

import (
	"context"
	"time"

	"agentawesome/internal/services/capabilities"
	"agentawesome/internal/services/command/command"
	"agentawesome/internal/services/runbook/actions"
	"agentawesome/internal/services/runbook/contracts"
)

// ContextToolClient invokes harness-owned context tools for runbook actions.
type ContextToolClient interface {
	List(context.Context) ([]string, error)
	Call(context.Context, actions.ToolRequest) (map[string]any, error)
}

// CommandClient executes configured command templates for runbook actions.
type CommandClient interface {
	Execute(context.Context, command.ExecuteRequest) (command.StatusResult, error)
}

// LLMClient generates structured runbook output through a configured model boundary.
type LLMClient interface {
	GenerateRunbookJSON(context.Context, actions.LLMRequest) (map[string]any, error)
}

// DesignAssistant proposes deterministic runbook artifacts at design time.
type DesignAssistant interface {
	SuggestDesignArtifacts(context.Context, DesignSuggestionRequest) ([]DesignArtifact, error)
}

// Config stores service endpoints and durable paths for runbook execution.
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
	Capabilities                    *capabilities.Registry
	TrustedSigners                  []contracts.TrustedSigner
	ObservedContractReviewThreshold int
	SkipInvalidDefinitions          bool
}
