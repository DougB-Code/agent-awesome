// This file exposes typed codebase catalog operations through the memory service.
package service

import (
	"context"
	"errors"

	"memory/internal/memory/domain"
	"memory/internal/memory/ports"
)

// UpsertCodebase stores or updates one durable codebase record.
func (s *Service) UpsertCodebase(ctx context.Context, req domain.UpsertCodebaseRequest) (domain.Codebase, error) {
	repo, err := s.codebaseRepository()
	if err != nil {
		return domain.Codebase{}, err
	}
	return repo.UpsertCodebase(ctx, req)
}

// GetCodebase loads one durable codebase record by id.
func (s *Service) GetCodebase(ctx context.Context, req domain.CodebaseIDRequest) (domain.Codebase, error) {
	repo, err := s.codebaseRepository()
	if err != nil {
		return domain.Codebase{}, err
	}
	return repo.GetCodebase(ctx, req)
}

// ListCodebases returns durable codebase records matching a query.
func (s *Service) ListCodebases(ctx context.Context, req domain.CodebaseQuery) ([]domain.Codebase, error) {
	repo, err := s.codebaseRepository()
	if err != nil {
		return nil, err
	}
	return repo.ListCodebases(ctx, req)
}

// ResolveCodebase resolves one human codebase phrase to a strong match or ambiguity.
func (s *Service) ResolveCodebase(ctx context.Context, req domain.ResolveCodebaseRequest) (domain.CodebaseResolution, error) {
	repo, err := s.codebaseRepository()
	if err != nil {
		return domain.CodebaseResolution{}, err
	}
	return repo.ResolveCodebase(ctx, req)
}

// DeleteCodebase lifecycle-deletes one durable codebase record.
func (s *Service) DeleteCodebase(ctx context.Context, req domain.CodebaseIDRequest) error {
	repo, err := s.codebaseRepository()
	if err != nil {
		return err
	}
	return repo.DeleteCodebase(ctx, req)
}

// codebaseRepository returns the typed codebase catalog storage port.
func (s *Service) codebaseRepository() (ports.CodebaseRepository, error) {
	if s.codebaseRepo == nil {
		return nil, errors.New("codebase repository is not configured")
	}
	return s.codebaseRepo, nil
}
