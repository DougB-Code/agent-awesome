package projection

import (
	"fmt"
	"time"

	"memory/internal/memory/domain"
)

// buildTimeHorizonProjection counts active tasks across fixed near-term buckets.
func buildTimeHorizonProjection(q domain.ExecutiveSummaryQuery, index taskIndex) domain.TimeHorizonProjection {
	buckets := []domain.TimeHorizonBucket{
		horizonBucket(q, index, "now", "Now", isNowTask),
		horizonBucket(q, index, "next", "Next", isNextTask),
		horizonBucket(q, index, "today", "Today", isTodayTask),
		horizonBucket(q, index, "tomorrow", "Tomorrow", isTomorrowTask),
		horizonBucket(q, index, "this_week", "This Week", isThisWeekTask),
	}
	return domain.TimeHorizonProjection{
		Buckets: buckets,
		Link:    domain.ProjectionLink{Label: "View timeline", Route: "/timeline"},
	}
}

// horizonBucket builds one fixed time bucket.
func horizonBucket(q domain.ExecutiveSummaryQuery, index taskIndex, id string, label string, match func(domain.ExecutiveSummaryQuery, domain.Task) bool) domain.TimeHorizonBucket {
	count := 0
	topItem := ""
	for _, task := range index.activeTasks() {
		if !match(q, task) {
			continue
		}
		count++
		if topItem == "" {
			topItem = task.Title
		}
	}
	return domain.TimeHorizonBucket{
		ID:      id,
		Label:   label,
		Count:   count,
		Summary: horizonSummary(id, count, topItem),
		TopItem: topItem,
		Link:    domain.ProjectionLink{Route: "/timeline?horizon=" + id},
	}
}

// horizonSummary returns a compact stable summary for one time bucket.
func horizonSummary(id string, count int, topItem string) string {
	if count == 0 {
		switch id {
		case "now":
			return "Clear"
		case "next":
			return "No priority queued"
		default:
			return "No items"
		}
	}
	if topItem != "" {
		return topItem
	}
	return fmt.Sprintf("%d items", count)
}

// isNowTask reports whether a task belongs in the immediate bucket.
func isNowTask(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	if task.Status == domain.TaskStatusBlocked {
		return true
	}
	if task.ScheduledAt != nil && !task.ScheduledAt.After(q.Now.Add(2*time.Hour)) {
		return true
	}
	return task.DueAt != nil && !task.DueAt.After(q.Now.Add(2*time.Hour))
}

// isNextTask reports whether a task is the next near-term work.
func isNextTask(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	return !isNowTask(q, task) && (task.Priority == domain.TaskPriorityUrgent || task.Priority == domain.TaskPriorityHigh || task.Risk >= 0.5)
}

// isTodayTask reports whether a task is due or scheduled today.
func isTodayTask(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	return sameOptionalLocalDay(task.DueAt, *q.Now) || sameOptionalLocalDay(task.ScheduledAt, *q.Now)
}

// isTomorrowTask reports whether a task is due or scheduled tomorrow.
func isTomorrowTask(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	tomorrow := q.Now.Add(24 * time.Hour)
	return sameOptionalLocalDay(task.DueAt, tomorrow) || sameOptionalLocalDay(task.ScheduledAt, tomorrow)
}

// isThisWeekTask reports whether a task is due or scheduled in the next week.
func isThisWeekTask(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	for _, candidate := range []*time.Time{task.DueAt, task.ScheduledAt, task.FollowUpAt} {
		if candidate == nil {
			continue
		}
		if candidate.After(*q.Now) && candidate.Before(q.Now.Add(7*24*time.Hour)) {
			return true
		}
	}
	return false
}
