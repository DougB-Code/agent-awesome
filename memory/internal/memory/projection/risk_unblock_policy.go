package projection

import (
	"sort"

	"memory/internal/memory/domain"
)

// buildRiskUnblockProjection builds dependency chains that could unblock work.
func buildRiskUnblockProjection(q domain.ExecutiveSummaryQuery, index taskIndex) domain.RiskUnblockProjection {
	chains := []domain.RiskUnblockChain{}
	for _, relation := range index.graph.Relations {
		chain, ok := riskChainForRelation(index, relation)
		if !ok {
			continue
		}
		chains = append(chains, chain)
	}
	sort.SliceStable(chains, func(i, j int) bool {
		return chainScore(index, chains[i]) > chainScore(index, chains[j])
	})
	if len(chains) > 3 {
		chains = chains[:3]
	}
	return domain.RiskUnblockProjection{
		Chains: chains,
		Link:   domain.ProjectionLink{Label: "View risks", Route: "/risks"},
	}
}

// riskChainForRelation converts a blocking dependency into a display chain.
func riskChainForRelation(index taskIndex, relation domain.TaskRelation) (domain.RiskUnblockChain, bool) {
	from, okFrom := index.tasksByID[relation.FromTaskID]
	to, okTo := index.tasksByID[relation.ToTaskID]
	if !okFrom || !okTo {
		return domain.RiskUnblockChain{}, false
	}
	var blocker domain.Task
	var blocked domain.Task
	switch relation.Type {
	case domain.TaskRelationDependsOn:
		blocker = to
		blocked = from
	case domain.TaskRelationBlocks:
		blocker = from
		blocked = to
	default:
		return domain.RiskUnblockChain{}, false
	}
	if blocked.Status != domain.TaskStatusBlocked && blocked.Status != domain.TaskStatusWaiting && blocked.Risk < 0.4 && blocked.Value < 0.4 {
		return domain.RiskUnblockChain{}, false
	}
	action := &domain.ExecutiveSummaryAction{
		Label:  "Take action on " + blocker.Title,
		Safety: "safe",
	}
	if unsafeTask(blocker) {
		action.Safety = "approval_required"
	}
	return domain.RiskUnblockChain{
		ID: "risk:" + string(relation.ID),
		Nodes: []domain.RiskUnblockChainNode{
			{TaskID: blocker.ID, Title: blocker.Title, Subtitle: statusSubtitle(blocker)},
			{TaskID: blocked.ID, Title: blocked.Title, Subtitle: statusSubtitle(blocked)},
		},
		SuggestedAction: action,
	}, true
}

// chainScore scores chains by blocked task risk and value.
func chainScore(index taskIndex, chain domain.RiskUnblockChain) float64 {
	if len(chain.Nodes) == 0 {
		return 0
	}
	last := chain.Nodes[len(chain.Nodes)-1]
	task, ok := index.tasksByID[last.TaskID]
	if !ok {
		return 0
	}
	return task.Risk + task.Value + pressureScore(task)
}

// statusSubtitle returns a compact state line for risk chain nodes.
func statusSubtitle(task domain.Task) string {
	if task.Person != "" && task.Status == domain.TaskStatusWaiting {
		return "Waiting on " + task.Person
	}
	if task.Project != "" {
		return task.Project
	}
	return string(task.Status)
}
