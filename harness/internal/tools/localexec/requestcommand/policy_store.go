// This file adapts policy persistence to the review workflow.
package requestcommand

// reviewPolicyStore abstracts persisted approval policy checks and writes.
type reviewPolicyStore interface {
	allowsExact(base string, proposal Proposal) (bool, error)
	allowsWorkspaceTool(base string) (bool, error)
	allowsWorkspacePrefix(base, commandLine string) (bool, error)
	allowsGlobalTool() (bool, error)

	approveWorkspaceExact(base string, proposal Proposal) error
	approveWorkspacePrefix(base, prefix string) error
	approveWorkspaceTool(base string) error
	approveGlobalTool() error
}

type fileReviewPolicyStore struct{}

// newFileReviewPolicyStore creates the filesystem-backed policy store.
func newFileReviewPolicyStore() reviewPolicyStore {
	return fileReviewPolicyStore{}
}

// allowsExact reports whether a workspace has approved the exact proposal.
func (fileReviewPolicyStore) allowsExact(base string, proposal Proposal) (bool, error) {
	policies, err := loadWorkspacePolicies(base)
	if err != nil {
		return false, err
	}
	return exactAllows(policies.Exact, proposal), nil
}

// allowsWorkspaceTool reports whether all request_command proposals are
// approved in the workspace.
func (fileReviewPolicyStore) allowsWorkspaceTool(base string) (bool, error) {
	policies, err := loadWorkspacePolicies(base)
	if err != nil {
		return false, err
	}
	return policies.AlwaysTool, nil
}

// allowsWorkspacePrefix reports whether a command line matches a stored
// workspace prefix.
func (fileReviewPolicyStore) allowsWorkspacePrefix(base, commandLine string) (bool, error) {
	policies, err := loadWorkspacePolicies(base)
	if err != nil {
		return false, err
	}
	return prefixAllows(sliceSet(policies.Prefixes), commandLine), nil
}

// allowsGlobalTool reports whether all request_command proposals are globally
// approved.
func (fileReviewPolicyStore) allowsGlobalTool() (bool, error) {
	policies, err := loadGlobalPolicies()
	if err != nil {
		return false, err
	}
	return policies.AlwaysTool, nil
}

// approveWorkspaceExact persists exact approval for one workspace proposal.
func (fileReviewPolicyStore) approveWorkspaceExact(base string, proposal Proposal) error {
	return updateWorkspacePolicies(base, func(policies *workspacePolicies) {
		policies.Exact = appendUniqueExact(policies.Exact, proposal)
	})
}

// approveWorkspacePrefix persists a command-line prefix approval for a
// workspace.
func (fileReviewPolicyStore) approveWorkspacePrefix(base, prefix string) error {
	return updateWorkspacePolicies(base, func(policies *workspacePolicies) {
		policies.Prefixes = appendUnique(policies.Prefixes, prefix)
	})
}

// approveWorkspaceTool persists workspace-wide request_command approval.
func (fileReviewPolicyStore) approveWorkspaceTool(base string) error {
	return updateWorkspacePolicies(base, func(policies *workspacePolicies) {
		policies.AlwaysTool = true
	})
}

// approveGlobalTool persists global request_command approval for the user.
func (fileReviewPolicyStore) approveGlobalTool() error {
	return updateGlobalPolicies(func(policies *globalPolicies) {
		policies.AlwaysTool = true
	})
}
