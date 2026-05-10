package projection

import (
	"math"
	"sort"
	"strings"
	"time"

	"memory/internal/memory/domain"
)

var attentionLaneOrder = map[string]int{
	"protect":   0,
	"decide":    1,
	"do":        2,
	"delegate":  3,
	"follow_up": 4,
	"monitor":   5,
}

// buildAttentionProjection ranks active tasks into user-facing attention lanes.
func buildAttentionProjection(q domain.ExecutiveSummaryQuery, index taskIndex) domain.AttentionProjection {
	items := []domain.ExecutiveSummaryItem{}
	for _, task := range index.activeTasks() {
		item := attentionItemForTask(q, index, task)
		items = append(items, item)
	}
	sort.SliceStable(items, func(i, j int) bool {
		leftLane := attentionLaneOrder[items[i].Lane]
		rightLane := attentionLaneOrder[items[j].Lane]
		if leftLane != rightLane {
			return leftLane < rightLane
		}
		if items[i].Score != items[j].Score {
			return items[i].Score > items[j].Score
		}
		return items[i].Title < items[j].Title
	})
	if len(items) > q.MaxItems {
		items = items[:q.MaxItems]
	}
	return domain.AttentionProjection{
		Items: items,
		Link:  domain.ProjectionLink{Label: "View all", Route: "/attention"},
	}
}

// attentionItemForTask converts one active task into an explainable lane item.
func attentionItemForTask(q domain.ExecutiveSummaryQuery, index taskIndex, task domain.Task) domain.ExecutiveSummaryItem {
	lane := attentionLaneForTask(q, index, task)
	reason := attentionReasonForTask(q, index, task, lane)
	item := domain.ExecutiveSummaryItem{
		ID:              "attention:" + lane + ":" + string(task.ID),
		Kind:            "task",
		Lane:            lane,
		Title:           task.Title,
		Subtitle:        attentionSubtitle(task),
		Reason:          reason,
		Score:           attentionScore(q, index, task),
		Confidence:      taskConfidence(task),
		Status:          string(task.Status),
		Priority:        string(task.Priority),
		TaskID:          task.ID,
		Person:          task.Person,
		Project:         task.Project,
		DueAt:           task.DueAt,
		ScheduledAt:     task.ScheduledAt,
		FollowUpAt:      task.FollowUpAt,
		EstimateMinutes: task.EstimateMinutes,
		Links:           []domain.ProjectionLink{{Route: "/attention?item=" + string(task.ID)}},
	}
	if q.IncludeEvidenceEnabled() {
		item.Evidence = sourceHandlesForTask(task)
	}
	if q.IncludeActionsEnabled() {
		item.PrimaryAction = primaryActionForLane(lane, task)
	}
	return item
}

// attentionLaneForTask classifies one task into a stable Today lane.
func attentionLaneForTask(q domain.ExecutiveSummaryQuery, index taskIndex, task domain.Task) string {
	if relationshipLoopDue(q, task) {
		return "follow_up"
	}
	if task.Status == domain.TaskStatusBlocked || task.Status == domain.TaskStatusWaiting {
		return "monitor"
	}
	if requiresHumanDecision(task) {
		return "decide"
	}
	if safelyDelegable(task) {
		return "delegate"
	}
	if shouldProtect(q, task) {
		return "protect"
	}
	return "do"
}

// attentionReasonForTask explains the lane without relying on hidden model judgment.
func attentionReasonForTask(q domain.ExecutiveSummaryQuery, index taskIndex, task domain.Task, lane string) string {
	switch lane {
	case "protect":
		return "High-value or scheduled work should not be casually displaced."
	case "decide":
		if unsafeTask(task) {
			return "Sensitive or financial action needs your approval."
		}
		return "Risk, urgency, or priority requires human judgment."
	case "delegate":
		return "Low-risk drafting, research, organizing, or planning work can be prepared safely."
	case "follow_up":
		return "Visible person or promise context needs follow-up."
	case "monitor":
		if task.Status == domain.TaskStatusBlocked {
			return "Blocked work should stay visible until the blocker moves."
		}
		return "Waiting work needs monitoring but no immediate action."
	default:
		if forgettingRisk(q, index, task) > 0.55 {
			return "Small or under-specified task is easy to forget."
		}
		return "Concrete open task is ready for your attention."
	}
}

// attentionSubtitle returns a compact row detail from task metadata.
func attentionSubtitle(task domain.Task) string {
	if task.Project != "" {
		return task.Project
	}
	if task.Person != "" {
		return task.Person
	}
	if task.Context != "" {
		return task.Context
	}
	if len(task.Topics) > 0 {
		return strings.Join(task.Topics, ", ")
	}
	return string(task.Status)
}

// attentionScore computes a deterministic explainable priority score.
func attentionScore(q domain.ExecutiveSummaryQuery, index taskIndex, task domain.Task) float64 {
	pressure := pressureScore(task)
	timePressure := timePressureScore(q, task)
	risk := clamp01(task.Risk)
	value := clamp01(task.Value)
	urgency := urgencyScore(task)
	relationshipCost := relationshipCostScore(q, task)
	forgetting := forgettingRisk(q, index, task)
	delegable := 0.0
	if safelyDelegable(task) {
		delegable = 1
	}
	return roundScore(pressure*0.22 + timePressure*0.18 + risk*0.16 + value*0.14 + urgency*0.12 + relationshipCost*0.08 + forgetting*0.08 - delegable*0.06)
}

// pressureScore derives pressure from priority and blocked state.
func pressureScore(task domain.Task) float64 {
	switch task.Priority {
	case domain.TaskPriorityUrgent:
		return 1
	case domain.TaskPriorityHigh:
		return 0.75
	case domain.TaskPriorityLow:
		return 0.2
	default:
		if task.Status == domain.TaskStatusBlocked {
			return 0.65
		}
		return 0.4
	}
}

// timePressureScore derives time pressure from scheduled, due, and follow-up dates.
func timePressureScore(q domain.ExecutiveSummaryQuery, task domain.Task) float64 {
	now := *q.Now
	best := 0.0
	for _, candidate := range []*time.Time{task.DueAt, task.ScheduledAt, task.FollowUpAt} {
		if candidate == nil {
			continue
		}
		hours := candidate.Sub(now).Hours()
		switch {
		case hours < 0:
			best = math.Max(best, 1)
		case hours <= 2:
			best = math.Max(best, 0.9)
		case sameLocalDay(*candidate, now):
			best = math.Max(best, 0.75)
		case hours <= 48:
			best = math.Max(best, 0.45)
		case hours <= 168:
			best = math.Max(best, 0.25)
		}
	}
	return best
}

// urgencyScore combines explicit urgency with priority fallback.
func urgencyScore(task domain.Task) float64 {
	if task.Urgency > 0 {
		return clamp01(task.Urgency)
	}
	if task.Priority == domain.TaskPriorityUrgent {
		return 0.9
	}
	if task.Priority == domain.TaskPriorityHigh {
		return 0.65
	}
	return 0
}

// relationshipCostScore scores visible obligations without inventing relationship health.
func relationshipCostScore(q domain.ExecutiveSummaryQuery, task domain.Task) float64 {
	score := 0.0
	if task.Person != "" {
		score += 0.35
	}
	if task.FollowUpAt != nil && !task.FollowUpAt.After(*q.Now) {
		score += 0.35
	}
	if containsAny(task.Source+" "+task.Context, []string{"promise", "commitment", "follow up", "reply"}) {
		score += 0.2
	}
	for _, link := range task.MemoryLinks {
		if link.Relationship == domain.TaskMemoryOriginatedFrom || link.Relationship == domain.TaskMemorySupporting {
			score += 0.1
			break
		}
	}
	return clamp01(score)
}

// forgettingRisk scores open loops that have weak metadata or no graph edges.
func forgettingRisk(q domain.ExecutiveSummaryQuery, index taskIndex, task domain.Task) float64 {
	if task.Status != domain.TaskStatusOpen && task.Status != domain.TaskStatusWaiting {
		return 0
	}
	score := 0.0
	if task.DueAt == nil {
		score += 0.22
	}
	if task.Project == "" && task.Person == "" && len(task.Topics) == 0 {
		score += 0.25
	}
	if len(index.relationsFor(task.ID)) == 0 {
		score += 0.2
	}
	if task.EstimateMinutes > 0 && task.EstimateMinutes <= 20 {
		score += 0.15
	}
	if containsAny(task.Source+" "+task.Context, []string{"remember", "capture", "quick note"}) {
		score += 0.1
	}
	if task.UpdatedAt.Before(q.Now.Add(-14 * 24 * time.Hour)) {
		score += 0.08
	}
	return clamp01(score)
}

// relationshipLoopDue reports whether a task carries a due relationship obligation.
func relationshipLoopDue(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	if task.Person == "" && task.FollowUpAt == nil && !containsAny(task.Source+" "+task.Context, []string{"promise", "commitment", "reply", "follow up"}) {
		return false
	}
	if task.FollowUpAt == nil {
		return task.Person != "" && containsAny(task.Title+" "+task.Context, []string{"reply", "follow up", "check in"})
	}
	return !task.FollowUpAt.After(q.Now.Add(24 * time.Hour))
}

// requiresHumanDecision reports whether a task should be approval-gated.
func requiresHumanDecision(task domain.Task) bool {
	return task.Status == domain.TaskStatusBlocked ||
		task.Priority == domain.TaskPriorityUrgent ||
		task.Risk >= 0.65 ||
		unsafeTask(task) ||
		containsAny(task.Title+" "+task.Context, []string{"approve", "decide", "decision", "defer", "confirm"})
}

// safelyDelegable reports whether the task can be represented as safe prep work.
func safelyDelegable(task domain.Task) bool {
	if unsafeTask(task) || task.Risk >= 0.65 {
		return false
	}
	if task.Status != domain.TaskStatusOpen && task.Status != domain.TaskStatusWaiting {
		return false
	}
	text := task.Title + " " + task.Description + " " + task.Context + " " + task.Source
	return containsAny(text, []string{"draft", "summarize", "research", "organize", "plan", "outline", "prepare", "collect"})
}

// unsafeTask reports whether a task needs approval before external or sensitive action.
func unsafeTask(task domain.Task) bool {
	text := strings.ToLower(task.Title + " " + task.Description + " " + task.Context + " " + task.Source)
	return containsAny(text, []string{"payment", "bank", "bill", "wire", "transfer", "delete", "remove", "send email", "send message", "external"})
}

// shouldProtect reports whether a task deserves protected attention.
func shouldProtect(q domain.ExecutiveSummaryQuery, task domain.Task) bool {
	if task.ScheduledAt != nil && sameLocalDay(*task.ScheduledAt, *q.Now) {
		return true
	}
	if task.Value >= 0.75 && (task.Risk >= 0.35 || task.EstimateMinutes >= 60) {
		return true
	}
	return task.Priority == domain.TaskPriorityHigh && task.EstimateMinutes >= 45
}

// primaryActionForLane returns one action hint for supported lanes.
func primaryActionForLane(lane string, task domain.Task) *domain.ExecutiveSummaryAction {
	switch lane {
	case "do":
		return &domain.ExecutiveSummaryAction{Label: "Mark done", Tool: "complete_task", Safety: "safe", Payload: map[string]string{"task_id": string(task.ID)}}
	case "delegate":
		return &domain.ExecutiveSummaryAction{Label: "Prepare draft", Safety: "safe"}
	case "decide":
		return &domain.ExecutiveSummaryAction{Label: "Review decision", Safety: "approval_required"}
	default:
		return nil
	}
}

// sourceHandlesForTask returns concise source handles for one graph task.
func sourceHandlesForTask(task domain.Task) []domain.ExecutiveSummaryEvidence {
	sources := []domain.ExecutiveSummaryEvidence{{Kind: "task", ID: string(task.ID), Label: task.Title, Relationship: "source"}}
	for _, link := range task.MemoryLinks {
		id := string(link.MemoryID)
		kind := "memory"
		if id == "" {
			id = string(link.MemoryEvidenceID)
			kind = "source"
		}
		if id == "" {
			continue
		}
		sources = append(sources, domain.ExecutiveSummaryEvidence{Kind: kind, ID: id, Label: link.Note, Relationship: string(link.Relationship)})
	}
	return sources
}

// taskConfidence returns explicit confidence or a conservative graph default.
func taskConfidence(task domain.Task) float64 {
	if task.Confidence > 0 {
		return clamp01(task.Confidence)
	}
	return 0.72
}
