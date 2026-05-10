package service

import (
	"context"

	"memory/internal/memory/domain"
	"memory/internal/memory/projection"
)

// ProjectExecutiveSummary returns the canonical Today projection from graph-backed tasks.
func (s *Service) ProjectExecutiveSummary(ctx context.Context, q domain.ExecutiveSummaryQuery) (domain.ExecutiveSummaryProjection, error) {
	q, err := domain.NormalizeExecutiveSummaryQuery(q)
	if err != nil {
		return domain.ExecutiveSummaryProjection{}, err
	}
	repo, err := s.taskRepository()
	if err != nil {
		return domain.ExecutiveSummaryProjection{}, err
	}
	graph, err := repo.TaskGraphProjection(ctx, domain.TaskGraphProjectionQuery{
		Tasks: domain.TaskQuery{
			IncludeDone:  true,
			IncludeLinks: q.IncludeEvidenceEnabled(),
			Limit:        100,
		},
		IncludeFacets: true,
	})
	if err != nil {
		return domain.ExecutiveSummaryProjection{}, err
	}
	return projection.NewEngine().Project(q, graph), nil
}

// ExplainExecutiveSummaryItem explains why a Today projection item was surfaced.
func (s *Service) ExplainExecutiveSummaryItem(ctx context.Context, q domain.ExplainExecutiveSummaryItemQuery) (domain.ExecutiveSummaryItemExplanation, error) {
	q, err := domain.NormalizeExplainExecutiveSummaryItemQuery(q)
	if err != nil {
		return domain.ExecutiveSummaryItemExplanation{}, err
	}
	includeSources := q.IncludeSourcesEnabled()
	summary, err := s.ProjectExecutiveSummary(ctx, domain.ExecutiveSummaryQuery{
		Scope:           domain.ScopeUser,
		Horizon:         "today",
		MaxItems:        50,
		IncludeEvidence: &includeSources,
		IncludeActions:  &includeSources,
		Channel:         "api",
	})
	if err != nil {
		return domain.ExecutiveSummaryItemExplanation{}, err
	}
	return projection.ExplainExecutiveSummaryItem(summary, q)
}
