// This file evaluates and applies request_command approval policies.
package requestcommand

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
)

// This file owns review decisions. Persisted policy storage lives behind
// reviewPolicyStore so approval rules stay separate from JSON and filesystem IO.

// ApprovalOption describes one action the user can choose during review.
type ApprovalOption struct {
	Action      string `json:"action"`
	Label       string `json:"label"`
	Description string `json:"description"`
}

// ReviewDecision is the selected review action returned by the confirmation UI.
type ReviewDecision struct {
	Action string `json:"action"`
	Prefix string `json:"prefix,omitempty"`
}

// approvalOptions lists the review actions supported for a proposal.
func approvalOptions(proposal Proposal) []ApprovalOption {
	return []ApprovalOption{
		{Action: "deny", Label: "Deny", Description: "Do not run this proposed command."},
		{Action: "approve_once", Label: "Approve exact command one time", Description: "Run only this proposed command now."},
		{Action: "always_exact_session", Label: "Always approve exact command for this session", Description: "Remember this exact command until the harness exits."},
		{Action: "always_exact_workspace", Label: "Always approve exact command for this workspace", Description: "Persist this exact command approval under .agentawesome."},
		{Action: "always_prefix_session", Label: "Always approve starts with for this session", Description: fmt.Sprintf("Remember command prefix %q until the harness exits.", proposal.CommandLine)},
		{Action: "always_prefix_workspace", Label: "Always approve starts with for this workspace", Description: fmt.Sprintf("Persist command prefix %q under .agentawesome.", proposal.CommandLine)},
		{Action: "always_tool_session", Label: "Always approve tool for this session", Description: "Approve all future request_command proposals until the harness exits."},
		{Action: "always_tool_workspace", Label: "Always approve tool for this workspace", Description: "Persist approval for all request_command proposals in this workspace."},
		{Action: "always_tool", Label: "(DANGEROUS) Always approve tool", Description: "Persist approval for all request_command proposals in every workspace for this user."},
	}
}

// decodeReviewDecision converts the runtime confirmation payload into a typed
// review decision, defaulting old/simple approvals to approve-once.
func decodeReviewDecision(value any) (ReviewDecision, error) {
	if value == nil {
		return ReviewDecision{Action: "approve_once"}, nil
	}
	data, err := json.Marshal(value)
	if err != nil {
		return ReviewDecision{}, fmt.Errorf("marshal review decision: %w", err)
	}
	var decision ReviewDecision
	if err := json.Unmarshal(data, &decision); err != nil {
		return ReviewDecision{}, fmt.Errorf("decode review decision: %w", err)
	}
	return decision, nil
}

// reviewPolicies stores session-scoped policy decisions and delegates persisted
// checks to a policy store.
type reviewPolicies struct {
	mu              sync.Mutex
	sessionExact    map[string]struct{}
	sessionPrefixes map[string]struct{}
	sessionTool     bool
	store           reviewPolicyStore
}

// newReviewPolicies initializes an empty in-memory policy set.
func newReviewPolicies() *reviewPolicies {
	return newReviewPoliciesWithStore(newFileReviewPolicyStore())
}

// newReviewPoliciesWithStore initializes an in-memory policy set backed by the
// provided persistent store.
func newReviewPoliciesWithStore(store reviewPolicyStore) *reviewPolicies {
	if store == nil {
		store = newFileReviewPolicyStore()
	}
	return &reviewPolicies{
		sessionExact:    make(map[string]struct{}),
		sessionPrefixes: make(map[string]struct{}),
		store:           store,
	}
}

// allows checks session, workspace, and global policy stores to decide whether
// a proposal can execute without asking the user again.
func (p *reviewPolicies) allows(base string, proposal Proposal) (bool, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if _, ok := p.sessionExact[proposal.Signature]; ok {
		return true, nil
	}
	allowed, err := p.store.allowsExact(base, proposal)
	if err != nil {
		return false, err
	}
	if allowed {
		return true, nil
	}
	// Stdin-bearing proposals require explicit review each time unless they have
	// an exact approval, because stdin can change the effect of the same command
	// line.
	if proposal.Stdin != "" {
		return false, nil
	}
	if p.sessionTool {
		return true, nil
	}
	allowed, err = p.store.allowsGlobalTool()
	if err != nil {
		return false, err
	}
	if allowed {
		return true, nil
	}
	if prefixAllows(p.sessionPrefixes, proposal.CommandLine) {
		return true, nil
	}
	allowed, err = p.store.allowsWorkspaceTool(base)
	if err != nil {
		return false, err
	}
	if allowed {
		return true, nil
	}
	return p.store.allowsWorkspacePrefix(base, proposal.CommandLine)
}

// apply records the selected policy decision in memory, the workspace file, or
// the user-level config file depending on the action.
func (p *reviewPolicies) apply(base string, proposal Proposal, decision ReviewDecision) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	switch decision.Action {
	case "", "approve_once":
		return nil
	case "always_exact_session":
		p.sessionExact[proposal.Signature] = struct{}{}
		return nil
	case "always_exact_workspace":
		return p.store.approveWorkspaceExact(base, proposal)
	case "always_prefix_session":
		prefix := decisionPrefix(decision, proposal)
		p.sessionPrefixes[prefix] = struct{}{}
		return nil
	case "always_prefix_workspace":
		prefix := decisionPrefix(decision, proposal)
		return p.store.approveWorkspacePrefix(base, prefix)
	case "always_tool_session":
		p.sessionTool = true
		return nil
	case "always_tool_workspace":
		return p.store.approveWorkspaceTool(base)
	case "always_tool":
		return p.store.approveGlobalTool()
	default:
		return fmt.Errorf("unsupported review decision action %q", decision.Action)
	}
}

// decisionPrefix chooses an explicit reviewed prefix, falling back to the full
// command line shown in the prompt.
func decisionPrefix(decision ReviewDecision, proposal Proposal) string {
	if strings.TrimSpace(decision.Prefix) != "" {
		return strings.TrimSpace(decision.Prefix)
	}
	return proposal.CommandLine
}

// prefixAllows reports whether any saved prefix matches the proposed command
// line.
func prefixAllows(prefixes map[string]struct{}, commandLine string) bool {
	for prefix := range prefixes {
		if strings.HasPrefix(commandLine, prefix) {
			return true
		}
	}
	return false
}
