// This file persists runbook authoring records used by the Automations UI.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
)

// UpsertDraft stores or replaces one editable runbook draft.
func (s *Store) UpsertDraft(ctx context.Context, record DraftRecord) error {
	now := nowString()
	body, err := marshalMap(record.Body)
	if err != nil {
		return fmt.Errorf("encode runbook draft body: %w", err)
	}
	validation, err := marshalMap(record.Validation)
	if err != nil {
		return fmt.Errorf("encode runbook draft validation: %w", err)
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
	_, err = s.db.ExecContext(ctx, `INSERT INTO runbook_drafts
		(id, kind, name, description, status, body_json, validation_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, name=excluded.name,
			description=excluded.description, status=excluded.status, body_json=excluded.body_json,
			validation_json=excluded.validation_json, updated_at=excluded.updated_at`,
		record.ID, record.Kind, name, record.Description, status, string(body), string(validation), createdAt, now)
	if err != nil {
		return fmt.Errorf("upsert runbook draft %q: %w", record.ID, err)
	}
	return nil
}

// ListDrafts returns editable runbook drafts in most-recent order.
func (s *Store) ListDrafts(ctx context.Context) ([]DraftRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, kind, name, description, status, body_json, validation_json, created_at, updated_at FROM runbook_drafts ORDER BY updated_at DESC`)
	if err != nil {
		return nil, fmt.Errorf("list runbook drafts: %w", err)
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

// GetDraft returns one editable runbook draft.
func (s *Store) GetDraft(ctx context.Context, id string) (DraftRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, kind, name, description, status, body_json, validation_json, created_at, updated_at FROM runbook_drafts WHERE id = ?`, id)
	return scanDraft(row)
}

// DeleteDraft removes one editable runbook draft.
func (s *Store) DeleteDraft(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM runbook_drafts WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete runbook draft %q: %w", id, err)
	}
	return nil
}

// UpsertPackage stores or replaces one automation package.
func (s *Store) UpsertPackage(ctx context.Context, record PackageRecord) error {
	now := nowString()
	body, err := marshalMap(record.Body)
	if err != nil {
		return fmt.Errorf("encode runbook package body: %w", err)
	}
	createdAt := record.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO runbook_packages
		(id, name, version, description, body_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET name=excluded.name, version=excluded.version,
			description=excluded.description, body_json=excluded.body_json, updated_at=excluded.updated_at`,
		record.ID, record.Name, record.Version, record.Description, string(body), createdAt, now)
	if err != nil {
		return fmt.Errorf("upsert runbook package %q: %w", record.ID, err)
	}
	return nil
}

// ListPackages returns installed automation packages.
func (s *Store) ListPackages(ctx context.Context) ([]PackageRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, version, description, body_json, created_at, updated_at FROM runbook_packages ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("list runbook packages: %w", err)
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
	row := s.db.QueryRowContext(ctx, `SELECT id, name, version, description, body_json, created_at, updated_at FROM runbook_packages WHERE id = ?`, id)
	return scanPackage(row)
}

// UpsertDesignArtifact stores or replaces one deterministic design artifact.
func (s *Store) UpsertDesignArtifact(ctx context.Context, record DesignArtifactRecord) error {
	body, err := marshalMap(record.Body)
	if err != nil {
		return fmt.Errorf("encode runbook design artifact body: %w", err)
	}
	createdAt := record.CreatedAt
	if createdAt == "" {
		createdAt = nowString()
	}
	name := record.Name
	if name == "" {
		name = record.ID
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO runbook_design_artifacts
		(id, kind, name, body_json, created_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, name=excluded.name,
			body_json=excluded.body_json, created_at=excluded.created_at`,
		record.ID, record.Kind, name, string(body), createdAt)
	if err != nil {
		return fmt.Errorf("upsert runbook design artifact %q: %w", record.ID, err)
	}
	return nil
}

// ListDesignArtifacts returns persisted deterministic design artifacts.
func (s *Store) ListDesignArtifacts(ctx context.Context) ([]DesignArtifactRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, kind, name, body_json, created_at FROM runbook_design_artifacts ORDER BY created_at DESC`)
	if err != nil {
		return nil, fmt.Errorf("list runbook design artifacts: %w", err)
	}
	defer rows.Close()
	var records []DesignArtifactRecord
	for rows.Next() {
		record, err := scanDesignArtifact(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// UpsertPublishedDefinition stores publication metadata for one definition.
func (s *Store) UpsertPublishedDefinition(ctx context.Context, record PublishedDefinitionRecord) error {
	publishedAt := record.PublishedAt
	if publishedAt == "" {
		publishedAt = nowString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO runbook_published_definitions
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

// UpsertDefinitionSource records the current disk path for a loaded definition.
func (s *Store) UpsertDefinitionSource(ctx context.Context, record PublishedDefinitionRecord) error {
	publishedAt := record.PublishedAt
	if publishedAt == "" {
		publishedAt = nowString()
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO runbook_published_definitions
		(definition_id, draft_id, path, hash, published_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(definition_id) DO UPDATE SET path=excluded.path,
			hash=excluded.hash, published_at=excluded.published_at`,
		record.DefinitionID, record.DraftID, record.Path, record.Hash, publishedAt)
	if err != nil {
		return fmt.Errorf("upsert definition source %q: %w", record.DefinitionID, err)
	}
	return nil
}

// GetPublishedDefinitionByDraftID returns source metadata for one draft.
func (s *Store) GetPublishedDefinitionByDraftID(ctx context.Context, draftID string) (PublishedDefinitionRecord, bool, error) {
	row := s.db.QueryRowContext(ctx, `SELECT definition_id, draft_id, path, hash, published_at FROM runbook_published_definitions WHERE draft_id = ?`, draftID)
	record, err := scanPublishedDefinition(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return PublishedDefinitionRecord{}, false, nil
		}
		return PublishedDefinitionRecord{}, false, err
	}
	return record, true, nil
}

// DeletePublishedDefinition removes source metadata for one definition.
func (s *Store) DeletePublishedDefinition(ctx context.Context, definitionID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM runbook_published_definitions WHERE definition_id = ?`, definitionID)
	if err != nil {
		return fmt.Errorf("delete published definition %q: %w", definitionID, err)
	}
	return nil
}

// DeletePublishedDefinitionsExcept removes source metadata for missing definitions.
func (s *Store) DeletePublishedDefinitionsExcept(ctx context.Context, ids []string) error {
	if len(ids) == 0 {
		if _, err := s.db.ExecContext(ctx, `DELETE FROM runbook_published_definitions`); err != nil {
			return fmt.Errorf("delete published definitions: %w", err)
		}
		return nil
	}
	placeholders := make([]string, len(ids))
	args := make([]any, len(ids))
	for index, id := range ids {
		placeholders[index] = "?"
		args[index] = id
	}
	query := `DELETE FROM runbook_published_definitions WHERE definition_id NOT IN (` + strings.Join(placeholders, ",") + `)`
	if _, err := s.db.ExecContext(ctx, query, args...); err != nil {
		return fmt.Errorf("delete stale published definitions: %w", err)
	}
	return nil
}

// ListRuns returns runbook runs matching operator filters.
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
	query := `SELECT id, definition_id, kind, status, state, input_json, output_json, created_at, updated_at FROM runbook_runs`
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
		return nil, fmt.Errorf("list runbook runs: %w", err)
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

// UpsertRunSetup stores or replaces one reusable runbook run setup.
func (s *Store) UpsertRunSetup(ctx context.Context, record RunSetupRecord) error {
	now := nowString()
	input, err := marshalMap(record.Input)
	if err != nil {
		return fmt.Errorf("encode runbook run setup input: %w", err)
	}
	createdAt := record.CreatedAt
	if createdAt == "" {
		createdAt = now
	}
	name := record.Name
	if name == "" {
		name = record.ID
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO runbook_run_setups
		(id, definition_id, name, description, input_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET definition_id=excluded.definition_id,
			name=excluded.name, description=excluded.description, input_json=excluded.input_json,
			updated_at=excluded.updated_at`,
		record.ID, record.DefinitionID, name, record.Description, string(input), createdAt, now)
	if err != nil {
		return fmt.Errorf("upsert runbook run setup %q: %w", record.ID, err)
	}
	return nil
}

// ListRunSetups returns reusable runbook run setups.
func (s *Store) ListRunSetups(ctx context.Context, filter RunSetupFilter) ([]RunSetupRecord, error) {
	query := `SELECT id, definition_id, name, description, input_json, created_at, updated_at FROM runbook_run_setups`
	args := []any{}
	if strings.TrimSpace(filter.DefinitionID) != "" {
		query += ` WHERE definition_id = ?`
		args = append(args, strings.TrimSpace(filter.DefinitionID))
	}
	query += ` ORDER BY updated_at DESC`
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list runbook run setups: %w", err)
	}
	defer rows.Close()
	var records []RunSetupRecord
	for rows.Next() {
		record, err := scanRunSetup(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// GetRunSetup returns one reusable runbook run setup.
func (s *Store) GetRunSetup(ctx context.Context, id string) (RunSetupRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, definition_id, name, description, input_json, created_at, updated_at FROM runbook_run_setups WHERE id = ?`, id)
	return scanRunSetup(row)
}

// DeleteRunSetup removes one reusable runbook run setup.
func (s *Store) DeleteRunSetup(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM runbook_run_setups WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete runbook run setup %q: %w", id, err)
	}
	return nil
}

// scanRunSetup decodes one reusable runbook run setup row.
func scanRunSetup(row interface{ Scan(...any) error }) (RunSetupRecord, error) {
	var record RunSetupRecord
	var input string
	if err := row.Scan(&record.ID, &record.DefinitionID, &record.Name, &record.Description, &input, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return RunSetupRecord{}, fmt.Errorf("runbook run setup not found")
		}
		return RunSetupRecord{}, err
	}
	if err := json.Unmarshal([]byte(input), &record.Input); err != nil {
		return RunSetupRecord{}, fmt.Errorf("decode runbook run setup input: %w", err)
	}
	return record, nil
}

// scanDraft decodes one runbook draft row.
func scanDraft(row interface{ Scan(...any) error }) (DraftRecord, error) {
	var record DraftRecord
	var body, validation string
	if err := row.Scan(&record.ID, &record.Kind, &record.Name, &record.Description, &record.Status, &body, &validation, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return DraftRecord{}, fmt.Errorf("runbook draft not found")
		}
		return DraftRecord{}, err
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return DraftRecord{}, fmt.Errorf("decode runbook draft body: %w", err)
	}
	if err := json.Unmarshal([]byte(validation), &record.Validation); err != nil {
		return DraftRecord{}, fmt.Errorf("decode runbook draft validation: %w", err)
	}
	return record, nil
}

// scanPublishedDefinition decodes one published definition metadata row.
func scanPublishedDefinition(row interface{ Scan(...any) error }) (PublishedDefinitionRecord, error) {
	var record PublishedDefinitionRecord
	if err := row.Scan(&record.DefinitionID, &record.DraftID, &record.Path, &record.Hash, &record.PublishedAt); err != nil {
		return PublishedDefinitionRecord{}, err
	}
	return record, nil
}

// scanPackage decodes one runbook package row.
func scanPackage(row interface{ Scan(...any) error }) (PackageRecord, error) {
	var record PackageRecord
	var body string
	if err := row.Scan(&record.ID, &record.Name, &record.Version, &record.Description, &body, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return PackageRecord{}, fmt.Errorf("runbook package not found")
		}
		return PackageRecord{}, err
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return PackageRecord{}, fmt.Errorf("decode runbook package body: %w", err)
	}
	return record, nil
}

// scanDesignArtifact decodes one design artifact row.
func scanDesignArtifact(row interface{ Scan(...any) error }) (DesignArtifactRecord, error) {
	var record DesignArtifactRecord
	var body string
	if err := row.Scan(&record.ID, &record.Kind, &record.Name, &body, &record.CreatedAt); err != nil {
		return DesignArtifactRecord{}, err
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return DesignArtifactRecord{}, fmt.Errorf("decode runbook design artifact body: %w", err)
	}
	return record, nil
}

// marshalMap encodes nil maps as empty JSON objects.
func marshalMap(value map[string]any) ([]byte, error) {
	return json.Marshal(nilMap(value))
}
