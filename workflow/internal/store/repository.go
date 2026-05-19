// This file implements workflow repository operations.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

const timeFormat = time.RFC3339Nano

// UpsertDefinition stores or replaces one loaded workflow definition.
func (s *Store) UpsertDefinition(ctx context.Context, record DefinitionRecord) error {
	now := nowString()
	body, err := json.Marshal(record.Body)
	if err != nil {
		return fmt.Errorf("encode definition body: %w", err)
	}
	name := record.Name
	if name == "" {
		name = record.ID
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_definitions (id, kind, name, hash, body_json, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, name=excluded.name, hash=excluded.hash, body_json=excluded.body_json, updated_at=excluded.updated_at`,
		record.ID, record.Kind, name, record.Hash, string(body), now)
	if err != nil {
		return fmt.Errorf("upsert workflow definition %q: %w", record.ID, err)
	}
	return nil
}

// ListDefinitions returns installed definition snapshots.
func (s *Store) ListDefinitions(ctx context.Context) ([]DefinitionRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, kind, name, hash, body_json, updated_at FROM workflow_definitions ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("list workflow definitions: %w", err)
	}
	defer rows.Close()
	var records []DefinitionRecord
	for rows.Next() {
		record, err := scanDefinition(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// DeleteDefinitionsExcept removes definition snapshots no longer present on disk.
func (s *Store) DeleteDefinitionsExcept(ctx context.Context, ids []string) error {
	if len(ids) == 0 {
		if _, err := s.db.ExecContext(ctx, `DELETE FROM workflow_definitions`); err != nil {
			return fmt.Errorf("delete workflow definitions: %w", err)
		}
		return nil
	}
	placeholders := make([]string, len(ids))
	args := make([]any, len(ids))
	for index, id := range ids {
		placeholders[index] = "?"
		args[index] = id
	}
	query := `DELETE FROM workflow_definitions WHERE id NOT IN (` + strings.Join(placeholders, ",") + `)`
	if _, err := s.db.ExecContext(ctx, query, args...); err != nil {
		return fmt.Errorf("delete stale workflow definitions: %w", err)
	}
	return nil
}

// CreateRun inserts one new workflow run.
func (s *Store) CreateRun(ctx context.Context, record RunRecord) error {
	now := nowString()
	input, err := json.Marshal(nilMap(record.Input))
	if err != nil {
		return fmt.Errorf("encode run input: %w", err)
	}
	output, err := json.Marshal(nilMap(record.Output))
	if err != nil {
		return fmt.Errorf("encode run output: %w", err)
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_runs (id, definition_id, kind, status, state, input_json, output_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		record.ID, record.DefinitionID, record.Kind, record.Status, record.State, string(input), string(output), now, now)
	if err != nil {
		return fmt.Errorf("create workflow run %q: %w", record.ID, err)
	}
	return nil
}

// GetRun loads one workflow run by id.
func (s *Store) GetRun(ctx context.Context, id string) (RunRecord, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, definition_id, kind, status, state, input_json, output_json, created_at, updated_at FROM workflow_runs WHERE id = ?`, id)
	return scanRun(row)
}

// ListRunsByStatus loads durable runs matching one runtime status.
func (s *Store) ListRunsByStatus(ctx context.Context, status string) ([]RunRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, definition_id, kind, status, state, input_json, output_json, created_at, updated_at FROM workflow_runs WHERE status = ? ORDER BY created_at`, status)
	if err != nil {
		return nil, fmt.Errorf("list workflow runs by status %q: %w", status, err)
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

// UpdateRunState updates run status, state, and output.
func (s *Store) UpdateRunState(ctx context.Context, id string, status string, state string, output map[string]any) error {
	encoded, err := json.Marshal(nilMap(output))
	if err != nil {
		return fmt.Errorf("encode run output: %w", err)
	}
	_, err = s.db.ExecContext(ctx, `UPDATE workflow_runs SET status = ?, state = ?, output_json = ?, updated_at = ? WHERE id = ?`, status, state, string(encoded), nowString(), id)
	if err != nil {
		return fmt.Errorf("update workflow run %q: %w", id, err)
	}
	return nil
}

// AppendEvent adds one durable run event.
func (s *Store) AppendEvent(ctx context.Context, runID string, eventType string, message string, data map[string]any) error {
	encoded, err := json.Marshal(nilMap(data))
	if err != nil {
		return fmt.Errorf("encode workflow event: %w", err)
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_events (run_id, type, message, data_json, created_at) VALUES (?, ?, ?, ?, ?)`, runID, eventType, message, string(encoded), nowString())
	if err != nil {
		return fmt.Errorf("append workflow event for run %q: %w", runID, err)
	}
	return nil
}

// ListEvents returns durable events for one run.
func (s *Store) ListEvents(ctx context.Context, runID string) ([]EventRecord, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, run_id, type, message, data_json, created_at FROM workflow_events WHERE run_id = ? ORDER BY id`, runID)
	if err != nil {
		return nil, fmt.Errorf("list workflow events for run %q: %w", runID, err)
	}
	defer rows.Close()
	var records []EventRecord
	for rows.Next() {
		record, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// SaveStepOutput stores one step output.
func (s *Store) SaveStepOutput(ctx context.Context, runID string, stepID string, output map[string]any) error {
	encoded, err := json.Marshal(nilMap(output))
	if err != nil {
		return fmt.Errorf("encode step output: %w", err)
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_step_outputs (run_id, step_id, output_json, created_at)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(run_id, step_id) DO UPDATE SET output_json=excluded.output_json, created_at=excluded.created_at`,
		runID, stepID, string(encoded), nowString())
	if err != nil {
		return fmt.Errorf("save workflow step output %s/%s: %w", runID, stepID, err)
	}
	return nil
}

// StepOutput loads one persisted step output for DAG fan-in input.
func (s *Store) StepOutput(ctx context.Context, runID string, stepID string) (map[string]any, bool, error) {
	var encoded string
	err := s.db.QueryRowContext(ctx, `SELECT output_json FROM workflow_step_outputs WHERE run_id = ? AND step_id = ?`, runID, stepID).Scan(&encoded)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, false, nil
		}
		return nil, false, fmt.Errorf("load workflow step output %s/%s: %w", runID, stepID, err)
	}
	var output map[string]any
	if err := json.Unmarshal([]byte(encoded), &output); err != nil {
		return nil, false, fmt.Errorf("decode workflow step output %s/%s: %w", runID, stepID, err)
	}
	return output, true, nil
}

// CreatePendingItem stores one user-visible pending item.
func (s *Store) CreatePendingItem(ctx context.Context, item PendingItem) error {
	payload, err := json.Marshal(nilMap(item.Payload))
	if err != nil {
		return fmt.Errorf("encode pending payload: %w", err)
	}
	response, err := json.Marshal(nilMap(item.Response))
	if err != nil {
		return fmt.Errorf("encode pending response: %w", err)
	}
	now := nowString()
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_pending_items (id, run_id, step_id, status, prompt, payload_json, response_json, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		item.ID, item.RunID, item.StepID, item.Status, item.Prompt, string(payload), string(response), now, now)
	if err != nil {
		return fmt.Errorf("create pending workflow item %q: %w", item.ID, err)
	}
	return nil
}

// CompletePendingItems records a response for open pending items on a run.
func (s *Store) CompletePendingItems(ctx context.Context, runID string, response map[string]any) error {
	encoded, err := json.Marshal(nilMap(response))
	if err != nil {
		return fmt.Errorf("encode pending response: %w", err)
	}
	_, err = s.db.ExecContext(ctx, `UPDATE workflow_pending_items SET status = 'completed', response_json = ?, updated_at = ? WHERE run_id = ? AND status = 'open'`, string(encoded), nowString(), runID)
	if err != nil {
		return fmt.Errorf("complete pending workflow items for run %q: %w", runID, err)
	}
	return nil
}

// ListOpenPendingItems returns open user-visible workflow items.
func (s *Store) ListOpenPendingItems(ctx context.Context) ([]PendingItem, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, run_id, step_id, status, prompt, payload_json, response_json, created_at, updated_at FROM workflow_pending_items WHERE status = 'open' ORDER BY created_at`)
	if err != nil {
		return nil, fmt.Errorf("list workflow inbox: %w", err)
	}
	defer rows.Close()
	var records []PendingItem
	for rows.Next() {
		record, err := scanPending(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// scanDefinition decodes one definition row.
func scanDefinition(row interface{ Scan(...any) error }) (DefinitionRecord, error) {
	var record DefinitionRecord
	var body string
	if err := row.Scan(&record.ID, &record.Kind, &record.Name, &record.Hash, &body, &record.UpdatedAt); err != nil {
		return DefinitionRecord{}, err
	}
	if err := json.Unmarshal([]byte(body), &record.Body); err != nil {
		return DefinitionRecord{}, fmt.Errorf("decode workflow definition body: %w", err)
	}
	return record, nil
}

// scanRun decodes one run row.
func scanRun(row interface{ Scan(...any) error }) (RunRecord, error) {
	var record RunRecord
	var input, output string
	if err := row.Scan(&record.ID, &record.DefinitionID, &record.Kind, &record.Status, &record.State, &input, &output, &record.CreatedAt, &record.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			return RunRecord{}, fmt.Errorf("workflow run not found")
		}
		return RunRecord{}, err
	}
	if err := json.Unmarshal([]byte(input), &record.Input); err != nil {
		return RunRecord{}, fmt.Errorf("decode workflow run input: %w", err)
	}
	if err := json.Unmarshal([]byte(output), &record.Output); err != nil {
		return RunRecord{}, fmt.Errorf("decode workflow run output: %w", err)
	}
	return record, nil
}

// scanEvent decodes one event row.
func scanEvent(row interface{ Scan(...any) error }) (EventRecord, error) {
	var record EventRecord
	var data string
	if err := row.Scan(&record.ID, &record.RunID, &record.Type, &record.Message, &data, &record.CreatedAt); err != nil {
		return EventRecord{}, err
	}
	if err := json.Unmarshal([]byte(data), &record.Data); err != nil {
		return EventRecord{}, fmt.Errorf("decode workflow event data: %w", err)
	}
	return record, nil
}

// scanPending decodes one pending item row.
func scanPending(row interface{ Scan(...any) error }) (PendingItem, error) {
	var item PendingItem
	var payload, response string
	if err := row.Scan(&item.ID, &item.RunID, &item.StepID, &item.Status, &item.Prompt, &payload, &response, &item.CreatedAt, &item.UpdatedAt); err != nil {
		return PendingItem{}, err
	}
	if err := json.Unmarshal([]byte(payload), &item.Payload); err != nil {
		return PendingItem{}, fmt.Errorf("decode pending payload: %w", err)
	}
	if err := json.Unmarshal([]byte(response), &item.Response); err != nil {
		return PendingItem{}, fmt.Errorf("decode pending response: %w", err)
	}
	return item, nil
}

// nilMap returns an empty JSON object for nil maps.
func nilMap(value map[string]any) map[string]any {
	if value == nil {
		return map[string]any{}
	}
	return value
}

// nowString returns the store timestamp format.
func nowString() string {
	return time.Now().UTC().Format(timeFormat)
}
