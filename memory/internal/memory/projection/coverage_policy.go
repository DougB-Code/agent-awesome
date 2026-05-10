package projection

import (
	"fmt"

	"memory/internal/memory/domain"
)

// buildCoverageProjection reports known coverage and explicit unknown domains.
func buildCoverageProjection(index taskIndex) domain.CoverageProjection {
	good := []string{}
	partial := []string{}
	if len(index.tasks) > 0 {
		good = append(good, "Tasks & projects")
	}
	if len(index.graph.Relations) > 0 {
		good = append(good, "Task relations")
	} else if len(index.tasks) > 0 {
		partial = append(partial, "No task relations recorded")
	}
	if hasCommitmentSignal(index) {
		good = append(good, "Commitments")
	} else if len(index.tasks) > 0 {
		partial = append(partial, "Some missing commitment context")
	}
	if hasPeopleSignal(index) {
		good = append(good, "People & contacts")
	} else if len(index.tasks) > 0 {
		partial = append(partial, "Some missing people context")
	}
	if missingDueDates(index) > 0 {
		partial = append(partial, fmt.Sprintf("%d tasks missing due dates", missingDueDates(index)))
	}
	if missingProjects(index) > 0 {
		partial = append(partial, fmt.Sprintf("%d tasks missing projects", missingProjects(index)))
	}
	return domain.CoverageProjection{
		Good:         good,
		Partial:      partial,
		NotConnected: []string{"Calendar", "Email", "Health / Sleep", "Banking / Bills"},
		Promise:      "I only use information that is source-backed in memory.",
	}
}

// buildProjectionQuality creates a concise trust and coverage summary.
func buildProjectionQuality(index taskIndex, coverage domain.CoverageProjection) domain.ProjectionQualitySummary {
	label := "Sparse"
	if len(index.tasks) > 0 {
		label = "Partial"
	}
	if len(index.tasks) > 0 && len(coverage.Partial) <= 2 && index.graph.Quality.RelationCoverage >= 0.25 {
		label = "Good"
	}
	limits := []string{}
	if len(index.tasks) == 0 {
		limits = append(limits, "No graph-backed tasks are available yet.")
	}
	if len(coverage.NotConnected) > 0 {
		limits = append(limits, "Calendar, email, health, and banking are unknown unless source-backed signals are added.")
	}
	return domain.ProjectionQualitySummary{
		Label:            label,
		RelationCoverage: index.graph.Quality.RelationCoverage,
		TaskCount:        len(index.tasks),
		UnknownDomains:   coverage.NotConnected,
		Limits:           limits,
	}
}

// hasCommitmentSignal reports whether tasks contain visible promise metadata.
func hasCommitmentSignal(index taskIndex) bool {
	for _, task := range index.tasks {
		if task.Person != "" || task.FollowUpAt != nil || containsAny(task.Source+" "+task.Context, []string{"promise", "commitment"}) {
			return true
		}
	}
	return false
}

// hasPeopleSignal reports whether the graph has person metadata.
func hasPeopleSignal(index taskIndex) bool {
	for _, task := range index.tasks {
		if task.Person != "" {
			return true
		}
	}
	return false
}

// missingDueDates counts active tasks without due dates.
func missingDueDates(index taskIndex) int {
	count := 0
	for _, task := range index.activeTasks() {
		if task.DueAt == nil {
			count++
		}
	}
	return count
}

// missingProjects counts active tasks without a project.
func missingProjects(index taskIndex) int {
	count := 0
	for _, task := range index.activeTasks() {
		if task.Project == "" {
			count++
		}
	}
	return count
}
