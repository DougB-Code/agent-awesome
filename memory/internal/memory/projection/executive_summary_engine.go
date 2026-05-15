package projection

import (
	"errors"
	"fmt"
	"sort"

	"memory/internal/memory/domain"
)

// Engine composes focused projection policies into the Today read model.
type Engine struct{}

// NewEngine creates an executive summary projection engine.
func NewEngine() Engine {
	return Engine{}
}

// Project builds the canonical Today projection from a task graph snapshot.
func (e Engine) Project(q domain.ExecutiveSummaryQuery, graph domain.TaskGraphProjection) domain.ExecutiveSummaryProjection {
	index := newTaskIndex(graph)
	attention := buildAttentionProjection(q, index)
	openLoops := buildOpenLoopProjection(q, index)
	delegation := buildDelegationProjection(q, index)
	riskUnblocks := buildRiskUnblockProjection(q, index)
	timeHorizon := buildTimeHorizonProjection(q, index)
	coverage := buildCoverageProjection(index)
	quality := buildProjectionQuality(index, coverage)
	metrics := buildSummaryMetrics(attention, delegation, coverage, quality)
	return domain.ExecutiveSummaryProjection{
		SchemaVersion:    domain.ExecutiveSummarySchemaVersion,
		GeneratedAt:      *q.Now,
		Firewall:         domain.ProjectionFirewall{Kind: string(q.Firewall), ID: "doug", Label: "Doug"},
		Horizon:          q.Horizon,
		Title:            "Today",
		Subtitle:         "Here is what matters now.",
		NarrativeSummary: narrativeSummary(metrics),
		Metrics:          metrics,
		Attention:        attention,
		OpenLoops:        openLoops,
		TimeHorizon:      timeHorizon,
		Delegation:       delegation,
		RiskUnblocks:     riskUnblocks,
		Coverage:         coverage,
		Quality:          quality,
		Links:            projectionLinks(),
	}
}

// ExplainExecutiveSummaryItem finds and explains one item in a projection.
func ExplainExecutiveSummaryItem(projection domain.ExecutiveSummaryProjection, q domain.ExplainExecutiveSummaryItemQuery) (domain.ExecutiveSummaryItemExplanation, error) {
	for _, item := range executiveSummaryItems(projection) {
		if item.ID != q.ItemID {
			continue
		}
		sources := item.Evidence
		limits := []string{}
		if !q.IncludeSourcesEnabled() {
			sources = nil
		}
		if len(sources) == 0 {
			limits = append(limits, "No source handles were requested or available beyond graph task fields.")
		}
		confidence := item.Confidence
		if confidence == 0 {
			confidence = 0.72
		}
		return domain.ExecutiveSummaryItemExplanation{
			ItemID:     item.ID,
			Title:      item.Title,
			Reason:     item.Reason,
			Evidence:   sources,
			Confidence: confidence,
			Limits:     limits,
		}, nil
	}
	return domain.ExecutiveSummaryItemExplanation{}, errors.New("executive summary item was not found")
}

// projectionLinks returns reserved routes for dedicated projection pages.
func projectionLinks() []domain.ProjectionLink {
	return []domain.ProjectionLink{
		{Label: "Open Loop Radar", Route: "/open-loops"},
		{Label: "Today's Attention", Route: "/attention"},
		{Label: "Delegation & Agent", Route: "/delegation"},
		{Label: "Horizon", Route: "/timeline"},
		{Label: "Risk & Unblocks", Route: "/risks"},
		{Label: "Confidence & Coverage", Route: "/memory/coverage"},
	}
}

// buildSummaryMetrics creates the top-level Today counters.
func buildSummaryMetrics(attention domain.AttentionProjection, delegation domain.DelegationProjection, coverage domain.CoverageProjection, quality domain.ProjectionQualitySummary) []domain.SummaryMetric {
	decisions := countAttentionLane(attention, "decide")
	followUps := countAttentionLane(attention, "follow_up")
	agentCanHandle := delegationBucketCount(delegation, "can_do_now")
	return []domain.SummaryMetric{
		{ID: "decisions", Label: "Decide", Value: fmt.Sprint(decisions), Subtitle: "Need your judgment", Severity: severityForCount(decisions, "attention"), Link: domain.ProjectionLink{Route: "/attention?metric=decisions"}},
		{ID: "relationships", Label: "Follow-ups", Value: fmt.Sprint(followUps), Subtitle: "People or promises", Severity: severityForCount(followUps, "warning"), Link: domain.ProjectionLink{Route: "/attention?metric=relationships"}},
		{ID: "agent_can_handle", Label: "Agent can handle", Value: fmt.Sprint(agentCanHandle), Subtitle: "Ready to act", Severity: severityForCount(agentCanHandle, "good"), Link: domain.ProjectionLink{Route: "/delegation"}},
		{ID: "picture_quality", Label: "Picture quality", Value: quality.Label, Subtitle: pictureQualitySubtitle(quality, coverage), Severity: pictureQualitySeverity(quality), Link: domain.ProjectionLink{Route: "/memory/coverage"}},
	}
}

// countAttentionLane returns the number of visible items in one lane.
func countAttentionLane(attention domain.AttentionProjection, lane string) int {
	count := 0
	for _, item := range attention.Items {
		if item.Lane == lane {
			count++
		}
	}
	return count
}

// delegationBucketCount returns the visible count for one delegation bucket.
func delegationBucketCount(delegation domain.DelegationProjection, id string) int {
	for _, bucket := range delegation.Buckets {
		if bucket.ID == id {
			return bucket.Count
		}
	}
	return 0
}

// severityForCount picks a metric severity while keeping zero states calm.
func severityForCount(count int, nonZero string) string {
	if count == 0 {
		return "normal"
	}
	return nonZero
}

// pictureQualitySubtitle describes the projection quality without blaming the user.
func pictureQualitySubtitle(quality domain.ProjectionQualitySummary, coverage domain.CoverageProjection) string {
	if quality.TaskCount == 0 {
		return "No task graph yet"
	}
	if len(coverage.Partial) > 0 || len(coverage.NotConnected) > 0 {
		return "Some gaps known"
	}
	return "Strong overall"
}

// pictureQualitySeverity maps quality labels to semantic metric severity.
func pictureQualitySeverity(quality domain.ProjectionQualitySummary) string {
	switch quality.Label {
	case "Good":
		return "good"
	case "Sparse":
		return "warning"
	default:
		return "normal"
	}
}

// narrativeSummary writes a compact text summary for chat and non-visual channels.
func narrativeSummary(metrics []domain.SummaryMetric) string {
	values := map[string]string{}
	for _, metric := range metrics {
		values[metric.ID] = metric.Value
	}
	return fmt.Sprintf("You have %s decisions, %s follow-ups, and %s items Agent Awesome can handle.",
		values["decisions"], values["relationships"], values["agent_can_handle"])
}

// executiveSummaryItems flattens explainable items from all primary sections.
func executiveSummaryItems(projection domain.ExecutiveSummaryProjection) []domain.ExecutiveSummaryItem {
	items := append([]domain.ExecutiveSummaryItem{}, projection.Attention.Items...)
	for _, category := range projection.OpenLoops.Categories {
		items = append(items, category.TopItems...)
	}
	for _, bucket := range projection.Delegation.Buckets {
		items = append(items, bucket.Items...)
	}
	return items
}

// newTaskIndex prepares task and relation lookup maps for policy objects.
func newTaskIndex(graph domain.TaskGraphProjection) taskIndex {
	tasksByID := map[domain.TaskID]domain.Task{}
	relationsByTask := map[domain.TaskID][]domain.TaskRelation{}
	for _, task := range graph.Tasks {
		tasksByID[task.ID] = task
	}
	for _, relation := range graph.Relations {
		relationsByTask[relation.FromTaskID] = append(relationsByTask[relation.FromTaskID], relation)
		relationsByTask[relation.ToTaskID] = append(relationsByTask[relation.ToTaskID], relation)
	}
	tasks := append([]domain.Task{}, graph.Tasks...)
	sort.SliceStable(tasks, func(i, j int) bool {
		return compareTasks(tasks[i], tasks[j])
	})
	return taskIndex{graph: graph, tasks: tasks, tasksByID: tasksByID, relationsByTask: relationsByTask}
}

// taskIndex stores normalized task graph lookups for Today policies.
type taskIndex struct {
	graph           domain.TaskGraphProjection
	tasks           []domain.Task
	tasksByID       map[domain.TaskID]domain.Task
	relationsByTask map[domain.TaskID][]domain.TaskRelation
}

// activeTasks returns tasks that still need attention or awareness.
func (i taskIndex) activeTasks() []domain.Task {
	tasks := []domain.Task{}
	for _, task := range i.tasks {
		if task.Status != domain.TaskStatusDone && task.Status != domain.TaskStatusCanceled {
			tasks = append(tasks, task)
		}
	}
	return tasks
}

// relationsFor returns all visible relations touching a task.
func (i taskIndex) relationsFor(taskID domain.TaskID) []domain.TaskRelation {
	return i.relationsByTask[taskID]
}
