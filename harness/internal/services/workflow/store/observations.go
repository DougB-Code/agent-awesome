// This file persists runtime-observed workflow contract shapes.
package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// UpsertObservedContract increments or creates one observed output contract shape.
func (s *Store) UpsertObservedContract(ctx context.Context, record ObservedContractRecord) error {
	now := nowString()
	contract, err := marshalMap(record.Contract)
	if err != nil {
		return fmt.Errorf("encode observed contract: %w", err)
	}
	fields, err := json.Marshal(record.ObservedFields)
	if err != nil {
		return fmt.Errorf("encode observed contract fields: %w", err)
	}
	firstSeenAt := record.FirstSeenAt
	if firstSeenAt == "" {
		firstSeenAt = now
	}
	lastSeenAt := record.LastSeenAt
	if lastSeenAt == "" {
		lastSeenAt = now
	}
	occurrences := record.Occurrences
	if occurrences <= 0 {
		occurrences = 1
	}
	_, err = s.db.ExecContext(ctx, `INSERT INTO workflow_observed_contracts
		(definition_id, node_id, tool_id, shape_hash, occurrences, contract_json, observed_fields_json, first_seen_at, last_seen_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(definition_id, node_id, tool_id, shape_hash)
		DO UPDATE SET occurrences = workflow_observed_contracts.occurrences + excluded.occurrences,
			contract_json = excluded.contract_json,
			observed_fields_json = excluded.observed_fields_json,
			last_seen_at = excluded.last_seen_at`,
		record.DefinitionID, record.NodeID, record.ToolID, record.ShapeHash, occurrences, string(contract), string(fields), firstSeenAt, lastSeenAt)
	if err != nil {
		return fmt.Errorf("upsert observed contract %s/%s/%s: %w", record.DefinitionID, record.NodeID, record.ShapeHash, err)
	}
	return nil
}

// ListObservedContracts returns runtime-observed contract shapes.
func (s *Store) ListObservedContracts(ctx context.Context, filter ObservedContractFilter) ([]ObservedContractRecord, error) {
	clauses := []string{}
	args := []any{}
	if strings.TrimSpace(filter.DefinitionID) != "" {
		clauses = append(clauses, "definition_id = ?")
		args = append(args, strings.TrimSpace(filter.DefinitionID))
	}
	if strings.TrimSpace(filter.NodeID) != "" {
		clauses = append(clauses, "node_id = ?")
		args = append(args, strings.TrimSpace(filter.NodeID))
	}
	if strings.TrimSpace(filter.ToolID) != "" {
		clauses = append(clauses, "tool_id = ?")
		args = append(args, strings.TrimSpace(filter.ToolID))
	}
	query := `SELECT definition_id, node_id, tool_id, shape_hash, occurrences, contract_json, observed_fields_json, first_seen_at, last_seen_at FROM workflow_observed_contracts`
	if len(clauses) > 0 {
		query += ` WHERE ` + strings.Join(clauses, ` AND `)
	}
	query += ` ORDER BY occurrences DESC, last_seen_at DESC`
	limit := filter.Limit
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	query += ` LIMIT ?`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list observed contracts: %w", err)
	}
	defer rows.Close()
	var records []ObservedContractRecord
	for rows.Next() {
		record, err := scanObservedContract(rows)
		if err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

// scanObservedContract decodes one observed contract row.
func scanObservedContract(row interface{ Scan(...any) error }) (ObservedContractRecord, error) {
	var record ObservedContractRecord
	var contract string
	var fields string
	if err := row.Scan(&record.DefinitionID, &record.NodeID, &record.ToolID, &record.ShapeHash, &record.Occurrences, &contract, &fields, &record.FirstSeenAt, &record.LastSeenAt); err != nil {
		return ObservedContractRecord{}, err
	}
	if err := json.Unmarshal([]byte(contract), &record.Contract); err != nil {
		return ObservedContractRecord{}, fmt.Errorf("decode observed contract: %w", err)
	}
	if err := json.Unmarshal([]byte(fields), &record.ObservedFields); err != nil {
		return ObservedContractRecord{}, fmt.Errorf("decode observed contract fields: %w", err)
	}
	return record, nil
}
