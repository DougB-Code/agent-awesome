// This file coordinates the request_command review and execution workflow.
package requestcommand

import (
	"context"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/localexec/execspec"
	"agentawesome/internal/tools/localexec/workdir"

	"github.com/rs/zerolog/log"
)

type commandExecutor interface {
	Execute(context.Context, execspec.ToolCall) (execspec.Output, error)
}

// requestCommandFlow coordinates proposal validation, review, policy checks,
// and command execution.
type requestCommandFlow struct {
	cfg       schema.LocalExec
	policies  *reviewPolicies
	executor  commandExecutor
	proposals proposalBuilder
}

// newRequestCommandFlow creates a request-command workflow with default
// policies when none are provided.
func newRequestCommandFlow(cfg schema.LocalExec, policies *reviewPolicies, executor commandExecutor) requestCommandFlow {
	if policies == nil {
		policies = newReviewPolicies()
	}
	return requestCommandFlow{
		cfg:       cfg,
		policies:  policies,
		executor:  executor,
		proposals: proposalBuilder{},
	}
}

// run processes one request_command proposal from review through execution.
func (f requestCommandFlow) run(ctx confirmationRequester, input RequestCommandInput) (RequestCommandOutput, error) {
	proposal := f.proposals.Build(input)
	base, err := workdir.ExecutionBase()
	if err != nil {
		return requestCommandError(proposal, nil, err)
	}
	call, err := requestedToolCall(base, f.cfg, input)
	if err != nil {
		return requestCommandError(proposal, nil, err)
	}

	allowed, err := f.policies.allows(base, proposal, f.cfg.AllowPersistentApprovals)
	if err != nil {
		return requestCommandError(proposal, nil, err)
	}
	if !allowed {
		out, err := f.review(ctx, base, proposal)
		if out != nil || err != nil {
			if out == nil {
				return requestCommandError(proposal, nil, err)
			}
			return *out, err
		}
	}

	result, err := f.executor.Execute(ctx, call)
	if err != nil {
		return requestCommandError(proposal, &result, err)
	}
	return RequestCommandOutput{
		Status:   "executed",
		Proposal: proposal,
		Result:   &result,
	}, nil
}

// review requests or applies a user decision for a command proposal.
func (f requestCommandFlow) review(ctx confirmationRequester, base string, proposal Proposal) (*RequestCommandOutput, error) {
	persistentState := persistentApprovalState(base, f.cfg.AllowPersistentApprovals)
	confirmation := ctx.ToolConfirmation()
	if confirmation == nil {
		log.Info().
			Bool("persistent_approvals_enabled", persistentState.Enabled).
			Str("command", proposal.CommandLine).
			Str("cwd", proposal.CWD).
			Msg("request_command review requested")
		// Returning without executing lets the runtime pause and resume this tool
		// call once the user has made a review decision.
		if err := ctx.RequestConfirmation(proposalHint(proposal, persistentState), ReviewRequestPayload{
			Proposal:            proposal,
			Options:             approvalOptions(proposal, persistentState.Enabled),
			PersistentApprovals: persistentState,
		}); err != nil {
			out, err := requestCommandError(proposal, nil, err)
			return &out, err
		}
		return &RequestCommandOutput{
			Status:   "pending_review",
			Proposal: proposal,
			Message:  "Command proposal is waiting for user review.",
		}, nil
	}
	if !confirmation.Confirmed {
		return deniedRequestCommand(proposal), nil
	}
	decision, err := decodeReviewDecision(confirmation.Payload)
	if err != nil {
		out, err := requestCommandError(proposal, nil, err)
		return &out, err
	}
	if decision.Action == "deny" {
		return deniedRequestCommand(proposal), nil
	}
	if isPersistentReviewAction(decision.Action) && !f.cfg.AllowPersistentApprovals {
		out, err := requestCommandError(proposal, nil, persistentApprovalsDisabledError())
		return &out, err
	}
	if err := f.policies.apply(base, proposal, decision); err != nil {
		out, err := requestCommandError(proposal, nil, err)
		return &out, err
	}
	if isPersistentReviewAction(decision.Action) {
		log.Info().
			Str("action", decision.Action).
			Str("command", proposal.CommandLine).
			Str("workspace", base).
			Msg("request_command persistent approval stored")
	}
	return nil, nil
}

// persistentApprovalsDisabledError explains how to enable saved approvals.
func persistentApprovalsDisabledError() error {
	return errPersistentApprovalsDisabled{}
}

type errPersistentApprovalsDisabled struct{}

// Error renders a user-facing persistent approval configuration error.
func (errPersistentApprovalsDisabled) Error() string {
	return "persistent request_command approvals are disabled; set local-exec allow-persistent-approvals: true to save workspace/global approvals"
}

// deniedRequestCommand builds the output returned for denied proposals.
func deniedRequestCommand(proposal Proposal) *RequestCommandOutput {
	return &RequestCommandOutput{
		Status:   "denied",
		Proposal: proposal,
		Message:  "User denied the command proposal.",
	}
}

// requestCommandError builds a tool output that preserves proposal details
// alongside the execution error.
func requestCommandError(proposal Proposal, result *execspec.Output, err error) (RequestCommandOutput, error) {
	message := ""
	if err != nil {
		message = err.Error()
	}
	return RequestCommandOutput{
		Status:   "error",
		Proposal: proposal,
		Result:   result,
		Message:  message,
	}, err
}

// requestedToolCall resolves an arbitrary reviewed command proposal into a
// ToolCall.
func requestedToolCall(base string, cfg schema.LocalExec, input RequestCommandInput) (execspec.ToolCall, error) {
	cwd, err := workdir.ResolveCWD(base, input.CWD, cfg.AllowedWorkdirs)
	if err != nil {
		return execspec.ToolCall{}, err
	}
	return execspec.ToolCall{
		Executable:  strings.TrimSpace(input.Executable),
		Args:        append([]string(nil), input.Args...),
		CWD:         cwd,
		Stdin:       input.Stdin,
		Timeout:     cfg.DefaultTimeoutDuration(),
		OutputLimit: cfg.DefaultOutputLimit(),
	}, nil
}
