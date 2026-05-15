package projection

import (
	"sort"

	"memory/internal/memory/domain"
)

// buildOpenLoopProjection summarizes task graph gaps and blocked work.
func buildOpenLoopProjection(q domain.ExecutiveSummaryQuery, index taskIndex) domain.OpenLoopProjection {
	categories := []domain.OpenLoopCategory{
		openLoopCategory(q, index, "orphan_tasks", "Orphan tasks", "warning", isOrphanTask),
		openLoopCategory(q, index, "stale_promises", "Stale promises", "warning", func(task domain.Task) bool { return relationshipLoopDue(q, task) }),
		openLoopCategory(q, index, "waiting_on", "Waiting on", "normal", func(task domain.Task) bool { return task.Status == domain.TaskStatusWaiting }),
		openLoopCategory(q, index, "blocked", "Blocked", "attention", func(task domain.Task) bool { return task.Status == domain.TaskStatusBlocked }),
		openLoopCategory(q, index, "unscheduled_due_items", "Unscheduled due items", "normal", func(task domain.Task) bool { return task.DueAt != nil && task.ScheduledAt == nil }),
	}
	return domain.OpenLoopProjection{
		Categories: categories,
		Link:       domain.ProjectionLink{Label: "View open loops", Route: "/open-loops"},
	}
}

// openLoopCategory builds one category counter with a few explainable examples.
func openLoopCategory(q domain.ExecutiveSummaryQuery, index taskIndex, id string, label string, severity string, match func(domain.Task) bool) domain.OpenLoopCategory {
	items := []domain.ExecutiveSummaryItem{}
	for _, task := range index.activeTasks() {
		if !match(task) {
			continue
		}
		items = append(items, openLoopItem(q, task, id))
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].Score != items[j].Score {
			return items[i].Score > items[j].Score
		}
		return items[i].Title < items[j].Title
	})
	topItems := items
	if len(topItems) > 3 {
		topItems = topItems[:3]
	}
	return domain.OpenLoopCategory{
		ID:       id,
		Label:    label,
		Count:    len(items),
		Severity: severity,
		TopItems: topItems,
		Link:     domain.ProjectionLink{Route: "/open-loops?category=" + id},
	}
}

// openLoopItem converts one matching task into an explainable category example.
func openLoopItem(q domain.ExecutiveSummaryQuery, task domain.Task, category string) domain.ExecutiveSummaryItem {
	item := domain.ExecutiveSummaryItem{
		ID:     "open_loop:" + category + ":" + string(task.ID),
		Kind:   "task",
		Title:  task.Title,
		Reason: "Task is included in the " + category + " open-loop category.",
		Score:  pressureScore(task) + timePressureScore(q, task),
		Status: string(task.Status),
		TaskID: task.ID,
	}
	if q.IncludeEvidenceEnabled() {
		item.Evidence = sourceHandlesForTask(task)
	}
	return item
}

// isOrphanTask reports whether a task has no visible organizing facet.
func isOrphanTask(task domain.Task) bool {
	return task.Project == "" && task.Person == "" && len(task.Topics) == 0
}
