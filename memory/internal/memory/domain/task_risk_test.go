package domain

import (
	"testing"
	"time"
)

// TestDueDateTaskRiskStrategyCalculatesDeadlineRisk verifies due-date risk bands.
func TestDueDateTaskRiskStrategyCalculatesDeadlineRisk(t *testing.T) {
	now := time.Date(2026, 5, 15, 12, 0, 0, 0, time.UTC)
	overdue := now.Add(-time.Hour)
	soon := now.Add(12 * time.Hour)
	later := now.Add(30 * 24 * time.Hour)
	doneStatus := TaskStatusDone

	tests := []struct {
		name string
		task Task
		want float64
	}{
		{name: "missing due date uses low baseline", task: Task{Status: TaskStatusOpen}, want: 0.10},
		{name: "overdue is maximum risk", task: Task{Status: TaskStatusOpen, DueAt: &overdue}, want: 1},
		{name: "due within day is high risk", task: Task{Status: TaskStatusOpen, DueAt: &soon}, want: 0.85},
		{name: "far future is low risk", task: Task{Status: TaskStatusOpen, DueAt: &later}, want: 0.10},
		{name: "terminal task has no active risk", task: Task{Status: doneStatus, DueAt: &overdue}, want: 0},
	}

	strategy := DueDateTaskRiskStrategy{}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := strategy.Calculate(test.task, now); got != test.want {
				t.Fatalf("risk = %v, want %v", got, test.want)
			}
		})
	}
}
