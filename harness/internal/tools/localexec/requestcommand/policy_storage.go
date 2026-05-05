// This file persists request_command approval policies.
package requestcommand

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"agent-awesome.com/harnessinternal/config/schema"
)

// workspacePolicies is the JSON shape stored under .agentawesome for one
// workspace.
type workspacePolicies struct {
	Version    int                     `json:"version"`
	Exact      workspaceExactApprovals `json:"exact"`
	Prefixes   []string                `json:"prefixes"`
	AlwaysTool bool                    `json:"always_tool,omitempty"`
}

// globalPolicies is the user-level JSON shape for cross-workspace approvals.
type globalPolicies struct {
	Version    int  `json:"version"`
	AlwaysTool bool `json:"always_tool,omitempty"`
}

// workspaceExactApproval is an editable exact command approval record.
type workspaceExactApproval struct {
	Signature   string    `json:"signature,omitempty"`
	Executable  string    `json:"executable,omitempty"`
	Args        []string  `json:"args,omitempty"`
	CWD         string    `json:"cwd,omitempty"`
	Stdin       string    `json:"stdin,omitempty"`
	CommandLine string    `json:"command_line,omitempty"`
	Reason      string    `json:"reason,omitempty"`
	Risk        string    `json:"risk,omitempty"`
	CreatedAt   time.Time `json:"created_at,omitempty"`
}

type workspaceExactApprovals []workspaceExactApproval

// UnmarshalJSON accepts both the current object form and the older signature
// string form for exact workspace approvals.
func (approvals *workspaceExactApprovals) UnmarshalJSON(data []byte) error {
	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	out := make([]workspaceExactApproval, 0, len(raw))
	for _, item := range raw {
		var signature string
		if err := json.Unmarshal(item, &signature); err == nil {
			out = append(out, workspaceExactApproval{Signature: signature})
			continue
		}
		var approval workspaceExactApproval
		if err := json.Unmarshal(item, &approval); err != nil {
			return err
		}
		out = append(out, approval)
	}
	*approvals = out
	return nil
}

// loadWorkspacePolicies reads workspace approvals, returning an empty policy set
// when the file does not exist yet.
func loadWorkspacePolicies(base string) (workspacePolicies, error) {
	path := workspacePolicyPath(base)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return workspacePolicies{Version: 1}, nil
		}
		return workspacePolicies{}, fmt.Errorf("read workspace reviewed-command policies: %w", err)
	}
	var policies workspacePolicies
	if err := json.Unmarshal(data, &policies); err != nil {
		return workspacePolicies{}, fmt.Errorf("decode workspace reviewed-command policies: %w", err)
	}
	if policies.Version == 0 {
		policies.Version = 1
	}
	policies.normalize()
	return policies, nil
}

// updateWorkspacePolicies loads, mutates, normalizes, and persists workspace
// approvals atomically from the caller's perspective.
func updateWorkspacePolicies(base string, update func(*workspacePolicies)) error {
	policies, err := loadWorkspacePolicies(base)
	if err != nil {
		return err
	}
	update(&policies)
	policies.normalize()
	data, err := json.MarshalIndent(policies, "", "  ")
	if err != nil {
		return fmt.Errorf("encode workspace reviewed-command policies: %w", err)
	}
	path := workspacePolicyPath(base)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create workspace approval directory: %w", err)
	}
	if err := os.WriteFile(path, append(data, '\n'), 0o600); err != nil {
		return fmt.Errorf("write workspace reviewed-command policies: %w", err)
	}
	return nil
}

// normalize fills default fields so persisted JSON stays predictable.
func (p *workspacePolicies) normalize() {
	if p.Version == 0 {
		p.Version = 1
	}
	if p.Exact == nil {
		p.Exact = workspaceExactApprovals{}
	}
	if p.Prefixes == nil {
		p.Prefixes = []string{}
	}
}

// workspacePolicyPath returns the per-workspace approvals file path.
func workspacePolicyPath(base string) string {
	return filepath.Join(base, ".agentawesome", "reviewed-command-approvals.json")
}

// loadGlobalPolicies reads user-wide command approval policy.
func loadGlobalPolicies() (globalPolicies, error) {
	path, err := globalPolicyPath()
	if err != nil {
		return globalPolicies{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return globalPolicies{Version: 1}, nil
		}
		return globalPolicies{}, fmt.Errorf("read global reviewed-command policies: %w", err)
	}
	var policies globalPolicies
	if err := json.Unmarshal(data, &policies); err != nil {
		return globalPolicies{}, fmt.Errorf("decode global reviewed-command policies: %w", err)
	}
	if policies.Version == 0 {
		policies.Version = 1
	}
	return policies, nil
}

// updateGlobalPolicies loads, mutates, and persists user-wide command approval
// policy.
func updateGlobalPolicies(update func(*globalPolicies)) error {
	policies, err := loadGlobalPolicies()
	if err != nil {
		return err
	}
	update(&policies)
	if policies.Version == 0 {
		policies.Version = 1
	}
	data, err := json.MarshalIndent(policies, "", "  ")
	if err != nil {
		return fmt.Errorf("encode global reviewed-command policies: %w", err)
	}
	path, err := globalPolicyPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create global approval directory: %w", err)
	}
	if err := os.WriteFile(path, append(data, '\n'), 0o600); err != nil {
		return fmt.Errorf("write global reviewed-command policies: %w", err)
	}
	return nil
}

// globalPolicyPath returns the user config path for global approvals.
func globalPolicyPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("resolve user config dir: %w", err)
	}
	return filepath.Join(dir, schema.AppConfigDirName, "reviewed-command-approvals.json"), nil
}

// exactAllows reports whether a stored exact approval matches the proposal
// signature.
func exactAllows(approvals workspaceExactApprovals, proposal Proposal) bool {
	for _, approval := range approvals {
		if approval.signature() == proposal.Signature {
			return true
		}
	}
	return false
}

// signature returns the stored signature or reconstructs one from editable
// command fields.
func (a workspaceExactApproval) signature() string {
	if a.hasCommandFields() {
		cwd := strings.TrimSpace(a.CWD)
		if cwd == "" {
			cwd = "."
		}
		return proposalSignature(Proposal{
			Executable: strings.TrimSpace(a.Executable),
			Args:       append([]string(nil), a.Args...),
			CWD:        cwd,
			Stdin:      a.Stdin,
		})
	}
	return strings.TrimSpace(a.Signature)
}

// hasCommandFields reports whether an exact approval stores editable command
// fields instead of only a signature.
func (a workspaceExactApproval) hasCommandFields() bool {
	return strings.TrimSpace(a.Executable) != "" || len(a.Args) > 0 || strings.TrimSpace(a.CWD) != "" || a.Stdin != ""
}

// sliceSet converts a string slice into a membership map.
func sliceSet(values []string) map[string]struct{} {
	out := make(map[string]struct{}, len(values))
	for _, value := range values {
		out[value] = struct{}{}
	}
	return out
}

// appendUnique appends value only when it is not already present.
func appendUnique(values []string, value string) []string {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

// appendUniqueExact appends a proposal as an editable exact approval unless an
// equivalent approval already exists.
func appendUniqueExact(values workspaceExactApprovals, proposal Proposal) workspaceExactApprovals {
	if exactAllows(values, proposal) {
		return values
	}
	return append(values, workspaceExactApproval{
		Executable:  proposal.Executable,
		Args:        append([]string(nil), proposal.Args...),
		CWD:         proposal.CWD,
		Stdin:       proposal.Stdin,
		CommandLine: proposal.CommandLine,
		Reason:      proposal.Reason,
		Risk:        proposal.Risk,
		CreatedAt:   time.Now().UTC(),
	})
}
