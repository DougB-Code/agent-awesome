// This file defines request_command input, output, and review payloads.
package requestcommand

import "agentawesome/internal/tools/localexec/execspec"

// RequestCommandInput is the model-proposed arbitrary command that must be
// reviewed before execution unless a saved policy already allows it.
type RequestCommandInput struct {
	Executable string   `json:"executable"`
	Args       []string `json:"args"`
	CWD        string   `json:"cwd,omitempty"`
	Stdin      string   `json:"stdin,omitempty"`
	Reason     string   `json:"reason"`
	Risk       string   `json:"risk"`
}

// RequestCommandOutput reports review status and, when approved, execution
// output.
type RequestCommandOutput struct {
	Status   string           `json:"status"`
	Proposal Proposal         `json:"proposal"`
	Result   *execspec.Output `json:"result,omitempty"`
	Message  string           `json:"message,omitempty"`
}

// Proposal is the normalized, signed command request shown to the user.
type Proposal struct {
	Executable  string   `json:"executable"`
	Args        []string `json:"args"`
	CommandLine string   `json:"command_line"`
	CWD         string   `json:"cwd"`
	Stdin       string   `json:"stdin,omitempty"`
	Reason      string   `json:"reason"`
	Risk        string   `json:"risk"`
	Signature   string   `json:"signature"`
}

// ReviewRequestPayload is the structured payload passed to confirmation UIs.
type ReviewRequestPayload struct {
	Proposal            Proposal                `json:"proposal"`
	Options             []ApprovalOption        `json:"options"`
	PersistentApprovals PersistentApprovalState `json:"persistent_approvals"`
}

// PersistentApprovalState reports whether review decisions may be saved beyond
// the current harness process.
type PersistentApprovalState struct {
	Enabled             bool   `json:"enabled"`
	Message             string `json:"message"`
	WorkspacePolicyPath string `json:"workspace_policy_path,omitempty"`
	GlobalPolicyPath    string `json:"global_policy_path,omitempty"`
}
