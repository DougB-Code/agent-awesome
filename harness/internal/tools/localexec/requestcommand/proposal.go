// This file normalizes request_command proposals.
package requestcommand

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"

	"agentawesome/internal/tools/localexec/commandline"
)

type proposalBuilder struct{}

// newProposal normalizes user/model input and computes a stable signature used
// by exact-approval policies.
func newProposal(input RequestCommandInput) Proposal {
	return proposalBuilder{}.Build(input)
}

// Build normalizes request input into a proposal with display and signature
// fields populated.
func (proposalBuilder) Build(input RequestCommandInput) Proposal {
	cwd := strings.TrimSpace(input.CWD)
	if cwd == "" {
		cwd = "."
	}
	proposal := Proposal{
		Executable: strings.TrimSpace(input.Executable),
		Args:       append([]string(nil), input.Args...),
		CWD:        cwd,
		Stdin:      input.Stdin,
		Reason:     strings.TrimSpace(input.Reason),
		Risk:       strings.TrimSpace(input.Risk),
	}
	proposal.CommandLine = commandline.ReviewedCommandLine(proposal.Executable, proposal.Args)
	proposal.Signature = proposalSignature(proposal)
	return proposal
}

// proposalSignature hashes the executable, arguments, cwd, and stdin so exact
// approvals are tied to the behaviorally relevant command shape.
func proposalSignature(proposal Proposal) string {
	data, _ := json.Marshal(struct {
		Executable string   `json:"executable"`
		Args       []string `json:"args"`
		CWD        string   `json:"cwd"`
		Stdin      string   `json:"stdin"`
	}{
		Executable: proposal.Executable,
		Args:       proposal.Args,
		CWD:        proposal.CWD,
		Stdin:      proposal.Stdin,
	})
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
