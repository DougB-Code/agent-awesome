// This file describes persistent request_command approval state for review UIs.
package requestcommand

import "strings"

// persistentApprovalState builds the state displayed with each command review.
func persistentApprovalState(base string, enabled bool) PersistentApprovalState {
	if !enabled {
		return PersistentApprovalState{
			Enabled: false,
			Message: "disabled; saved workspace/global approvals require local-exec allow-persistent-approvals: true",
		}
	}
	state := PersistentApprovalState{
		Enabled:             true,
		Message:             "enabled; workspace/global approvals can be saved and reused without another review",
		WorkspacePolicyPath: workspacePolicyPath(base),
	}
	if path, err := globalPolicyPath(); err == nil {
		state.GlobalPolicyPath = path
	}
	return state
}

// persistentApprovalPromptText renders persistent approval state for prompts.
func persistentApprovalPromptText(state PersistentApprovalState) string {
	var b strings.Builder
	b.WriteString(state.Message)
	if state.WorkspacePolicyPath != "" {
		b.WriteString("\n  Workspace policy file: ")
		b.WriteString(state.WorkspacePolicyPath)
	}
	if state.GlobalPolicyPath != "" {
		b.WriteString("\n  Global policy file: ")
		b.WriteString(state.GlobalPolicyPath)
	}
	return b.String()
}
