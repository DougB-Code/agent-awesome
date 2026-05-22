// This file manages reusable workflow templates and package metadata.
package runtime

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/store"
)

// ListTemplates returns available workflow templates.
func (s *Service) ListTemplates(ctx context.Context) ([]store.TemplateRecord, error) {
	return s.store.ListTemplates(ctx)
}

// GetTemplate returns one workflow template.
func (s *Service) GetTemplate(ctx context.Context, id string) (store.TemplateRecord, error) {
	return s.store.GetTemplate(ctx, strings.TrimSpace(id))
}

// InstantiateTemplate creates an editable draft from a template.
func (s *Service) InstantiateTemplate(ctx context.Context, id string, req TemplateInstantiateRequest) (store.DraftRecord, error) {
	template, err := s.store.GetTemplate(ctx, strings.TrimSpace(id))
	if err != nil {
		return store.DraftRecord{}, err
	}
	body := cloneMap(template.Body)
	applyTemplateParameters(body, req.Parameters)
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = template.Name
	}
	return s.CreateDraft(ctx, DraftRequest{
		Kind:        stringFromMap(body, "kind", draftKindWorkflow),
		Name:        name,
		Description: template.Description,
		Body:        body,
	})
}

// ListPackages returns installed workflow packages.
func (s *Service) ListPackages(ctx context.Context) ([]store.PackageRecord, error) {
	return s.store.ListPackages(ctx)
}

// ImportPackage installs one workflow package record.
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

// ExportPackage returns one installed workflow package.
func (s *Service) ExportPackage(ctx context.Context, id string) (store.PackageRecord, error) {
	return s.store.GetPackage(ctx, strings.TrimSpace(id))
}

// SeedAuthoringCatalog installs built-in templates and package metadata.
func (s *Service) SeedAuthoringCatalog(ctx context.Context) error {
	templates, err := builtInTemplates()
	if err != nil {
		return err
	}
	for _, template := range templates {
		if err := s.store.UpsertTemplate(ctx, template); err != nil {
			return err
		}
	}
	return nil
}

// applyTemplateParameters replaces simple string placeholders in template bodies.
func applyTemplateParameters(body map[string]any, params map[string]any) {
	for key, value := range body {
		switch typed := value.(type) {
		case string:
			next := typed
			for param, replacement := range params {
				next = strings.ReplaceAll(next, "{{"+param+"}}", fmt.Sprint(replacement))
			}
			body[key] = next
		case map[string]any:
			applyTemplateParameters(typed, params)
		case []any:
			for _, item := range typed {
				if nested, ok := item.(map[string]any); ok {
					applyTemplateParameters(nested, params)
				}
			}
		}
	}
}
