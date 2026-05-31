// This file exposes live memory domain pool management through service policy.
package service

import (
	"context"
	"fmt"

	"memory/internal/memory/domain"
	"memory/internal/memory/ports"
)

// ListMemoryDomains lists databases currently known to the memory pool.
func (s *Service) ListMemoryDomains(ctx context.Context, req domain.MemoryDomainListRequest) ([]domain.MemoryDomainInfo, error) {
	repo, err := s.domainPoolRepository()
	if err != nil {
		return nil, err
	}
	infos, err := repo.ListMemoryDomains(ctx)
	if err != nil {
		return nil, err
	}
	policy, err := s.firewallPolicyForAuthorization()
	if err != nil {
		return nil, err
	}
	requested := domain.DomainID("")
	if req.DomainID != "" {
		requested, err = domain.NormalizeDomainID(req.DomainID, "")
		if err != nil {
			return nil, err
		}
		if policy != nil && !policy.AllowsRead(req.Actor, domain.Firewall(requested)) {
			return nil, fmt.Errorf("actor %q cannot read memory domain %q", req.Actor, requested)
		}
	}
	filtered := make([]domain.MemoryDomainInfo, 0, len(infos))
	for _, info := range infos {
		if requested != "" && info.DomainID != requested {
			continue
		}
		if requested == "" && policy != nil && !policy.AllowsRead(req.Actor, domain.Firewall(info.DomainID)) {
			continue
		}
		filtered = append(filtered, info)
	}
	return filtered, nil
}

// CreateMemoryDomain opens or creates a pooled database for one domain id.
func (s *Service) CreateMemoryDomain(ctx context.Context, req domain.MemoryDomainRequest) (domain.MemoryDomainInfo, error) {
	domainID, err := domain.NormalizeDomainID(req.DomainID, "")
	if err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	if err := s.authorizeWrite(req.Actor, domainID); err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	repo, err := s.domainPoolRepository()
	if err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	return repo.CreateMemoryDomain(ctx, domainID)
}

// RemoveMemoryDomain closes a pooled database and optionally deletes its files.
func (s *Service) RemoveMemoryDomain(ctx context.Context, req domain.MemoryDomainRequest) (domain.MemoryDomainInfo, error) {
	domainID, err := domain.NormalizeDomainID(req.DomainID, "")
	if err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	if err := s.authorizeWrite(req.Actor, domainID); err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	repo, err := s.domainPoolRepository()
	if err != nil {
		return domain.MemoryDomainInfo{}, err
	}
	return repo.RemoveMemoryDomain(ctx, domainID, req.DeleteFiles)
}

// domainPoolRepository returns the live domain-pool repository.
func (s *Service) domainPoolRepository() (ports.DomainPoolRepository, error) {
	if s.domainPoolRepo == nil {
		return nil, fmt.Errorf("memory domain pool repository is not configured")
	}
	return s.domainPoolRepo, nil
}
