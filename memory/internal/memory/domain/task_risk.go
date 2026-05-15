package domain

import "time"

// TaskRiskStrategy calculates a read-only risk score from explicit task facts.
type TaskRiskStrategy interface {
	Calculate(task Task, now time.Time) float64
}

// DueDateTaskRiskStrategy derives risk from deadline proximity.
type DueDateTaskRiskStrategy struct{}

// Calculate returns a normalized due-date risk score for an active task.
func (DueDateTaskRiskStrategy) Calculate(task Task, now time.Time) float64 {
	if TerminalTaskStatus(task.Status) {
		return 0
	}
	if task.DueAt == nil {
		return 0.10
	}
	hours := task.DueAt.Sub(now).Hours()
	switch {
	case hours < 0:
		return 1
	case hours <= 24:
		return 0.85
	case hours <= 48:
		return 0.70
	case hours <= 7*24:
		return 0.45
	case hours <= 14*24:
		return 0.25
	default:
		return 0.10
	}
}

// DefaultTaskRiskStrategy is the production task risk calculation policy.
var DefaultTaskRiskStrategy TaskRiskStrategy = DueDateTaskRiskStrategy{}

// CalculateTaskRisk applies the configured task risk strategy.
func CalculateTaskRisk(task Task, now time.Time) float64 {
	return DefaultTaskRiskStrategy.Calculate(task, now)
}
