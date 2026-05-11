// This file adapts graph values to SQL storage and query helpers.
package store

import (
	"fmt"
	"strings"
	"time"

	graph "memory/internal/memory/graph/domain"
	"memory/internal/memory/id"
)

// nullableNodeID converts blank node ids to nil for SQL nullable columns.
func nullableNodeID(value graph.NodeID) any {
	if value == "" {
		return nil
	}
	return value
}

// nullableEdgeID converts blank edge ids to nil for SQL nullable columns.
func nullableEdgeID(value graph.EdgeID) any {
	if value == "" {
		return nil
	}
	return value
}

// nullableString converts blank strings to nil for SQL nullable columns.
func nullableString(value string) any {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return value
}

// nullableTime converts nil times to nil SQL values.
func nullableTime(value *time.Time) any {
	if value == nil || value.IsZero() {
		return nil
	}
	return timeString(*value)
}

// nullableNumber converts non-number values to nil for SQL nullable columns.
func nullableNumber(value graph.Value) any {
	if value.Type != graph.ValueNumber {
		return nil
	}
	return value.Number
}

// nullableValueTime converts non-time values to nil for SQL nullable columns.
func nullableValueTime(value graph.Value) any {
	if value.Type != graph.ValueTime || value.Time == nil {
		return nil
	}
	return timeString(*value.Time)
}

// valueText returns a searchable string for any typed value.
func valueText(value graph.Value) string {
	switch value.Type {
	case graph.ValueBool, graph.ValueText:
		return value.Text
	case graph.ValueJSON:
		return value.JSON
	case graph.ValueNumber:
		return fmt.Sprintf("%g", value.Number)
	case graph.ValueTime:
		if value.Time == nil {
			return ""
		}
		return timeString(*value.Time)
	default:
		return ""
	}
}

// inClause returns a SQL IN clause placeholder list.
func inClause(column string, count int) string {
	placeholders := make([]string, count)
	for i := range placeholders {
		placeholders[i] = "?"
	}
	return fmt.Sprintf("%s IN (%s)", column, strings.Join(placeholders, ","))
}

// ftsQuery converts user text into a conservative FTS expression.
func ftsQuery(text string) string {
	parts := strings.Fields(strings.ToLower(text))
	terms := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.Trim(part, `"'()[]{}:;,.!?`)
		if part != "" {
			terms = append(terms, fmt.Sprintf("%q", part))
		}
	}
	if len(terms) == 0 {
		return `""`
	}
	return strings.Join(terms, " OR ")
}

// timeString formats times consistently for SQLite text ordering.
func timeString(value time.Time) string {
	return value.UTC().Format(time.RFC3339Nano)
}

// parseTime parses SQLite time strings.
func parseTime(value string) (time.Time, error) {
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return time.Time{}, fmt.Errorf("parse graph time %q: %w", value, err)
	}
	return parsed, nil
}

// newNodeID creates a graph node identifier.
func newNodeID() (graph.NodeID, error) {
	value, err := id.New("node")
	return graph.NodeID(value), err
}

// newEdgeID creates a graph edge identifier.
func newEdgeID() (graph.EdgeID, error) {
	value, err := id.New("edge")
	return graph.EdgeID(value), err
}

// newPropertyID creates a graph property identifier.
func newPropertyID() (graph.PropertyID, error) {
	value, err := id.New("prop")
	return graph.PropertyID(value), err
}

// newAuditID creates a graph audit identifier.
func newAuditID() (graph.AuditID, error) {
	value, err := id.New("audit")
	return graph.AuditID(value), err
}
