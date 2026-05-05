// This file exposes request_command as an ADK function tool.
package requestcommand

import (
	"context"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/localexec/execspec"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/functiontool"
)

// This file implements the ADK adapter for the reviewed arbitrary-command tool.

// RequestCommandToolName is the arbitrary command proposal tool name.
const RequestCommandToolName = "request_command"

// Executor runs an already-reviewed command proposal.
type Executor interface {
	Execute(context.Context, execspec.ToolCall) (execspec.Output, error)
}

// requestCommandTool owns request_command dependencies and delegates the review
// workflow to requestCommandFlow.
type requestCommandTool struct {
	cfg      schema.LocalExec
	policies *reviewPolicies
	executor Executor
}

// NewTool creates the arbitrary-command proposal tool.
func NewTool(cfg schema.LocalExec, executor Executor) (tool.Tool, error) {
	t := &requestCommandTool{
		cfg:      cfg,
		policies: newReviewPolicies(),
		executor: executor,
	}
	return functiontool.New(functiontool.Config{
		Name:        RequestCommandToolName,
		Description: "Propose an arbitrary local OS command for user review. This tool does not execute until the user approves the proposal.",
	}, t.run)
}

// run adapts the ADK function-tool signature to the reviewed-command workflow.
func (t *requestCommandTool) run(ctx tool.Context, input RequestCommandInput) (RequestCommandOutput, error) {
	return t.runWithConfirmation(ctx, input)
}

// runWithConfirmation exposes the workflow behind the narrow confirmation
// interface used by tests and the ADK adapter.
func (t *requestCommandTool) runWithConfirmation(ctx confirmationRequester, input RequestCommandInput) (RequestCommandOutput, error) {
	return t.flow().run(ctx, input)
}

// flow creates the workflow object for a single request_command invocation.
func (t *requestCommandTool) flow() requestCommandFlow {
	return newRequestCommandFlow(t.cfg, t.policies, t.executor)
}
