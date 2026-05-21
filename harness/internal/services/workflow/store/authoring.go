// This file persists workflow authoring records used by the Automations UI.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
)

// UpsertDraft stores or replaces one editable workflow draft.
func (s *Store) UpsertDraft(ctx context.Context, record DraftRecord) error {
	now := nowString()
	body, err := marshalMap(record.Body)
	if err != nil {
		return fmt.Errorf("encode workflow draft body: %w", err)
	}
	validation, err := marshalMap(record.Validation)
	if err != nil {
		return fmt.Errorf("encode workflow draft validation: %w", err)
	}
	createdAt := record.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	name := record.Name
	if name == "" {
		name = record.ID
	}
	status := record.Status
	if status == "" {
		status = "draft"
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_drafts
		(id, kind, name, description, status, body_json, validation_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, name=excluded.name,
			description=excluded.description, status=excluded.status, body_json=excluded.body_json,
			validation_json=excluded.validation_json, updated_at=excluded.updated_at`,
		record.ID, record.Kind, name, record.Description, status, string(body), string(validation), createdAt, now)
	if err != nil {
		return fmt.Errorf("upsert workflow draft %q: %w", record.ID, err)
	}
	return nil
}

// ListDrafts returns editable workflow drafts in most-recent order.
func (s *Store) ListDrafts(ctx context.Context) ([]DraftRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, kind, name, description, status, body_json, validation_json, created_at, updated_at FROM workflow_drafts ORDER BY updated_at DESC`)
	if err != nil {
		return nil, fmt.Errorf("list workflow drafts: %w", err)
	}
	defer rows.Close()
	var records []DraftRecord
	for rows.Next() {
		record, err := scanDraft(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// GetDraft returns one editable workflow draft.
func (s *Store) GetDraft(ctx context.Context, id string) (DraftRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, kind, name, description, status, body_json, validation_json, created_at, updated_at FROM workflow_drafts WHERE id = ?`, id)
	return scanDraft(row)
}

// DeleteDraft removes one editable workflow draft.
func (s *Store) DeleteDraft(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM workflow_drafts WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete workflow draft %q: %w", id, err)
	}
	return nil
}

// UpsertTemplate stores or replaces one workflow template record.
func (s *Store) UpsertTemplate(ctx context.Context, record TemplateRecord) error {
	now := nowString()
	tags, err := json.Marshal(record.Tags)
	if err != nil {
		return fmt.Errorf("encode workflow template tags: %w", err)
	}
	parameters, err := json.Marshal(record.Parameters)
	if err != nil {
		return fmt.Errorf("encode workflow template parameters: %w", err)
	}
	requirements, err := marshalMap(record.Requirements)
	if err != nil {
		return fmt.Errorf("encode workflow template requirements: %w", err)
	}
	body, err := marshalMap(record.Body)
	if err != nil {
		return fmt.Errorf("encode workflow template body: %w", err)
	}
	createdAt := record.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_templates
		(id, name, description, category, tags_json, parameters_json, requirements_json, body_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET name=excluded.name, description=excluded.description,
			category=excluded.category, tags_json=excluded.tags_json,
			parameters_json=excluded.parameters_json, requirements_json=excluded.requirements_json,
			body_json=excluded.body_json, updated_at=excluded.updated_at`,
		record.ID, record.Name, record.Description, record.Category, string(tags), string(parameters), string(requirements), string(body), createdAt, now)
	if err != nil {
		return fmt.Errorf("upsert workflow template %q: %w", record.ID, err)
	}
	return nil
}

// ListTemplates returns available workflow templates.
func (s *Store) ListTemplates(ctx context.Context) ([]TemplateRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, description, category, tags_json, parameters_json, requirements_json, body_json, created_at, updated_at FROM workflow_templates ORDER BY category, name`)
	if err != nil {
		return nil, fmt.Errorf("list workflow templates: %w", err)
	}
	defer rows.Close()
	var records []TemplateRecord
	for rows.Next() {
		record, err := scanTemplate(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// GetTemplate returns one workflow template.
func (s *Store) GetTemplate(ctx context.Context, id string) (TemplateRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, description, category, tags_json, parameters_json, requirements_json, body_json, created_at, updated_at FROM workflow_templates WHERE id = ?`, id)
	return scanTemplate(row)
}

// UpsertPackage stores or replaces one automation package.
func (s *Store) UpsertPackage(ctx context.Context, record PackageRecord) error {
	now := nowString()
	body, err := marshalMap(record.Body)
	if err != nil {
		return fmt.Errorf("encode workflow package body: %w", err)
	}
	createdAt := record.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_packages
		(id, name, version, description, body_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET name=excluded.name, version=excluded.version,
			description=excluded.description, body_json=excluded.body_json, updated_at=excluded.updated_at`,
		record.ID, record.Name, record.Version, record.Description, string(body), createdAt, now)
	if err != nil {
		return fmt.Errorf("upsert workflow package %q: %w", record.ID, err)
	}
	return nil
}

// ListPackages returns installed automation packages.
func (s *Store) ListPackages(ctx context.Context) ([]PackageRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, version, description, body_json, created_at, updated_at FROM workflow_packages ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("list workflow packages: %w", err)
	}
	defer rows.Close()
	var records []PackageRecord
	for rows.Next() {
		record, err := scanPackage(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// GetPackage returns one automation package.
func (s *Store) GetPackage(ctx context.Context, id string) (PackageRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, version, description, body_json, created_at, updated_at FROM workflow_packages WHERE id = ?`, id)
	return scanPackage(row)
}

// UpsertPublishedDefinition stores publication metadata for one definition.
func (s *Store) UpsertPublishedDefinition(ctx context.Context, record PublishedDefinitionRecord) error {
	publishedAt := record.PublishedAt
	if publishedAt == "" {
		publishedAt = nowString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO workflow_published_definitions
		(definition_id, draft_id, path, hash, published_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(definition_id) DO UPDATE SET draft_id=excluded.draft_id,
			path=excluded.path, hash=excluded.hash, published_at=excluded.published_at`,
		record.DefinitionID, record.DraftID, record.Path, record.Hash, publishedAt)
	if err != nil {
		return fmt.Errorf("upsert published definition %q: %w", record.DefinitionID, err)
	}
	return nil
}

// ListRuns returns workflow runs matching operator filters.
func (s *Store) ListRuns(ctx context.Context, filter RunFilter) ([]RunRecord, error) {
	clauses := []string{}
	args := []any{}
	if strings.TrimSpace(filter.Status) != "" {
		clauses = append(clauses, "status = ?")
		args = append(args, strings.TrimSpace(filter.Status))
	}
	if strings.TrimSpace(filter.DefinitionID) != "" {
		clauses = append(clauses, "definition_id = ?")
		args = append(args, strings.TrimSpace(filter.DefinitionID))
	}
	query := `SELECT id, definition_id, kind, status, state, input_json, output_json, created_at, updated_at FROM workflow_runs`
	if len(clauses) > 0 {
		query += ` WHERE ` + strings.Join(clauses, ` AND `)
	}
	query += ` ORDER BY created_at DESC`
	limit := filter.Limit
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	query += ` LIMIT ?`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list workflow runs: %w", err)
	}
	defer rows.Close()
	var records []RunRecord
	for rows.Next() {
		record, err := scanRun(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// scanDraft decodes one workflow draft row.
func scanDraft(row interface{ Scan(...any) error }) (DraftRecord, error) {
	var record DraftRecord
	var body, validation string
	if err := row.Scan(&record.ID, &record.Kind, &record.Name, &record.Description, &record.Status, &body, &validation, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return DraftRecord{}, fmt.Errorf("workflow draft not found")
		}
		return DraftRecord{}, err
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return DraftRecord{}, fmt.Errorf("decode workflow draft body: %w", err)
	}
	if err := json.Unmarshal([]byte(validation), &record.Validation); err != nil {
		return DraftRecord{}, fmt.Errorf("decode workflow draft validation: %w", err)
	}
	return record, nil
}

// scanTemplate decodes one workflow template row.
func scanTemplate(row interface{ Scan(...any) error }) (TemplateRecord, error) {
	var record TemplateRecord
	var tags, parameters, requirements, body string
	if err := row.Scan(&record.ID, &record.Name, &record.Description, &record.Category, &tags, &parameters, &requirements, &body, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return TemplateRecord{}, fmt.Errorf("workflow template not found")
		}
		return TemplateRecord{}, err
	}
	if err := json.Unmarshal([]byte(tags), &record.Tags); err != nil {
		return TemplateRecord{}, fmt.Errorf("decode workflow template tags: %w", err)
	}
	if err := json.Unmarshal([]byte(parameters), &record.Parameters); err != nil {
		return TemplateRecord{}, fmt.Errorf("decode workflow template parameters: %w", err)
	}
	if err := json.Unmarshal([]byte(requirements), &record.Requirements); err != nil {
		return TemplateRecord{}, fmt.Errorf("decode workflow template requirements: %w", err)
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return TemplateRecord{}, fmt.Errorf("decode workflow template body: %w", err)
	}
	return record, nil
}

// scanPackage decodes one workflow package row.
func scanPackage(row interface{ Scan(...any) error }) (PackageRecord, error) {
	var record PackageRecord
	var body string
	if err := row.Scan(&record.ID, &record.Name, &record.Version, &record.Description, &body, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return PackageRecord{}, fmt.Errorf("workflow package not found")
		}
		return PackageRecord{}, err
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return PackageRecord{}, fmt.Errorf("decode workflow package body: %w", err)
	}
	return record, nil
}

// marshalMap encodes nil maps as empty JSON objects.
func marshalMap(value map[string]any) ([]byte, error) {
	return json.Marshal(nilMap(value))
}
