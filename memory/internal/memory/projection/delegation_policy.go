package projection

import (
	"sort"
	"time"

	"memory/internal/memory/domain"
)

// buildDelegationProjection groups tasks by agent readiness and approval needs.
func buildDelegationProjection(q domain.ExecutiveSummaryQuery, index taskIndex) domain.DelegationProjection {
	buckets := []domain.DelegationBucket{
		delegationBucket(q, index, "can_do_now", "Agent can do now", "good", func(task domain.Task) bool { return safelyDelegable(task) }),
		delegationBucket(q, index, "needs_approval", "Needs your approval", "attention", func(task domain.Task) bool { return unsafeTask(task) || task.Risk >= 0.65 }),
		delegationBucket(q, index, "needs_context", "Needs context", "warning", func(task domain.Task) bool { return maybeDelegableButMissingContext(task) }),
		delegationBucket(q, index, "running", "Running", "normal", func(task domain.Task) bool { return task.Status == domain.TaskStatusWaiting }),
		delegationBucket(q, index, "done", "Done", "good", func(task domain.Task) bool { return completedRecently(q, task) }),
		delegationBucket(q, index, "failed", "Needs attention", "warning", func(task domain.Task) bool { return task.Status == domain.TaskStatusCanceled }),
	}
	return domain.DelegationProjection{
		Buckets: buckets,
		Link:    domain.ProjectionLink{Label: "View all", Route: "/delegation"},
	}
}

// delegationBucket builds one agent delegation status bucket.
func delegationBucket(q domain.ExecutiveSummaryQuery, index taskIndex, id string, label string, severity string, match func(domain.Task) bool) domain.DelegationBucket {
	items := []domain.ExecutiveSummaryItem{}
	for _, task := range index.tasks {
		if !match(task) {
			continue
		}
		items = append(items, delegationItem(q, index, task, id))
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].Score != items[j].Score {
			return items[i].Score > items[j].Score
		}
		return items[i].Title < items[j].Title
	})
	visible := items
	if len(visible) > 3 {
		visible = visible[:3]
	}
	return domain.DelegationBucket{
		ID:       id,
		Label:    label,
		Count:    len(items),
		Items:    visible,
		Severity: severity,
		Link:     domain.ProjectionLink{Route: "/delegation?bucket=" + id},
	}
}

// delegationItem converts one task into a delegation row.
func delegationItem(q domain.ExecutiveSummaryQuery, index taskIndex, task domain.Task, bucket string) domain.ExecutiveSummaryItem {
	item := domain.ExecutiveSummaryItem{
		ID:       "delegation:" + bucket + ":" + string(task.ID),
		Kind:     "task",
		Title:    task.Title,
		Subtitle: delegationSubtitle(bucket, task),
		Reason:   delegationReason(bucket),
		Score:    attentionScore(q, index, task),
		Status:   string(task.Status),
		TaskID:   task.ID,
	}
	if q.IncludeEvidenceEnabled() {
		item.Evidence = sourceHandlesForTask(task)
	}
	if q.IncludeActionsEnabled() && bucket == "can_do_now" {
		item.PrimaryAction = &domain.ExecutiveSummaryAction{Label: "Prepare draft", Safety: "safe"}
	}
	return item
}

// completedRecently reports whether a task finished inside the Today window.
func completedRecently(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	if task.Status != domain.TaskStatusDone {
		return false
	}
	threshold := q.Now.Add(-24 * time.Hour)
	if task.CompletedAt != nil {
		return task.CompletedAt.After(threshold)
	}
	return task.UpdatedAt.After(threshold)
}

// maybeDelegableButMissingContext reports bounded low-risk work that lacks task context.
func maybeDelegableButMissingContext(task domain.Task) bool {
	if task.Status != domain.TaskStatusOpen || unsafeTask(task) || task.Risk >= 0.65 {
		return false
	}
	if task.Description != "" || len(task.MemoryLinks) > 0 {
		return false
	}
	return task.EstimateMinutes > 0 && task.EstimateMinutes <= 60
}

// delegationSubtitle returns concise status text for an agent bucket item.
func delegationSubtitle(bucket string, task domain.Task) string {
	if task.Project != "" {
		return task.Project
	}
	return string(task.Status)
}

// delegationReason explains one delegation bucket classification.
func delegationReason(bucket string) string {
	switch bucket {
	case "can_do_now":
		return "Low-risk bounded work has enough context to proceed."
	case "needs_approval":
		return "High-risk work needs approval."
	case "needs_context":
		return "The task is bounded and low risk, but lacks supporting context."
	case "running":
		return "Task is already waiting on another actor or process."
	case "done":
		return "Task has been completed."
	default:
		return "Task needs attention before it can be delegated."
	}
}
