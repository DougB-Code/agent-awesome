package projection

import (
	"math"
	"strings"
	"time"

	"memory/internal/memory/domain"
)

// buildCommitmentProjection collects relationship follow-up items for compatibility.
func buildCommitmentProjection(attention domain.AttentionProjection) domain.CommitmentProjection {
	items := []domain.ExecutiveSummaryItem{}
	for _, item := range attention.Items {
		if item.Lane == "follow_up" {
			items = append(items, item)
		}
	}
	return domain.CommitmentProjection{
		Items: items,
		Link:  domain.ProjectionLink{Label: "View commitments", Route: "/attention?lane=follow_up"},
	}
}

// compareTasks provides a stable order for projection inputs.
func compareTasks(left domain.Task, right domain.Task) bool {
	leftTime := taskSortTime(left)
	rightTime := taskSortTime(right)
	if !leftTime.Equal(rightTime) {
		return leftTime.Before(rightTime)
	}
	return left.Title < right.Title
}

// taskSortTime returns the best available ordering time for one task.
func taskSortTime(task domain.Task) time.Time {
	for _, candidate := range []*time.Time{task.DueAt, task.ScheduledAt, task.FollowUpAt} {
		if candidate != nil {
			return *candidate
		}
	}
	if !task.UpdatedAt.IsZero() {
		return task.UpdatedAt
	}
	return task.CreatedAt
}

// containsAny reports whether text contains any case-insensitive needle.
func containsAny(text string, needles []string) bool {
	text = strings.ToLower(text)
	for _, needle := range needles {
		if strings.Contains(text, strings.ToLower(needle)) {
			return true
		}
	}
	return false
}

// clamp01 constrains a score to the inclusive 0..1 range.
func clamp01(value float64) float64 {
	if value < 0 {
		return 0
	}
	if value > 1 {
		return 1
	}
	return value
}

// roundScore keeps scores deterministic and compact in JSON responses.
func roundScore(value float64) float64 {
	return math.Round(clamp01(value)*1000) / 1000
}

// sameOptionalLocalDay reports whether an optional time lands on a given day.
func sameOptionalLocalDay(candidate *time.Time, target time.Time) bool {
	if candidate == nil {
		return false
	}
	return sameLocalDay(*candidate, target)
}

// sameLocalDay compares two timestamps by local calendar day.
func sameLocalDay(left time.Time, right time.Time) bool {
	left = left.Local()
	right = right.Local()
	return left.Year() == right.Year() && left.YearDay() == right.YearDay()
}
