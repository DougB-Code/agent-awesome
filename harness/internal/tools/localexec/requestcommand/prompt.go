// This file builds request_command review prompt text.
package requestcommand

import "strings"

// proposalHint builds the human-readable review text shown to the user.
func proposalHint(proposal Proposal, state PersistentApprovalState) string {
	var b strings.Builder
	b.WriteString("The agent wants to run:\n\n  ")
	b.WriteString(proposal.CommandLine)
	b.WriteString("\n\nReason:\n  ")
	b.WriteString(proposal.Reason)
	b.WriteString("\n\nWorking directory:\n  ")
	b.WriteString(proposal.CWD)
	b.WriteString("\n\nRisk:\n  ")
	b.WriteString(proposal.Risk)
	appendStdinReview(&b, proposal.Stdin)
	b.WriteString("\n\nPersistent approvals:\n  ")
	b.WriteString(persistentApprovalPromptText(state))
	if state.Enabled {
		b.WriteString("\n\nChoose one: deny / approve once / always exact for session / always exact for workspace / always starts with for session / always starts with for workspace / always approve tool for session / always approve tool for workspace / dangerous always approve tool.")
	} else {
		b.WriteString("\n\nChoose one: deny / approve once / always exact for session / always starts with for session / always approve tool for session.")
	}
	return b.String()
}
