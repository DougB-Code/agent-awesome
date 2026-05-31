// This file manages reusable runbook package metadata.
package runtime

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/services/runbook/store"
)

// ListPackages returns installed runbook packages.
func (s *Service) ListPackages(ctx context.Context) ([]store.PackageRecord, error) {
	return s.store.ListPackages(ctx)
}

// ImportPackage installs one runbook package record.
func (s *Service) ImportPackage(ctx context.Context, req PackageImportRequest) (store.PackageRecord, error) {
	record := req.Package
	if err := validateAuthoringID(record.ID, "package id"); err != nil {
		return store.PackageRecord{}, err
	}
	if record.Name == "" {
		record.Name = record.ID
	}
	if record.Version == "" {
		return store.PackageRecord{}, fmt.Errorf("package version is required")
	}
	if err := s.store.UpsertPackage(ctx, record); err != nil {
		return store.PackageRecord{}, err
	}
	return s.store.GetPackage(ctx, record.ID)
}

// ExportPackage returns one installed runbook package.
func (s *Service) ExportPackage(ctx context.Context, id string) (store.PackageRecord, error) {
	return s.store.GetPackage(ctx, strings.TrimSpace(id))
}
