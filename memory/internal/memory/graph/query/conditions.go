// This file evaluates graph query conditions and stored value conversions.
package query

import (
	"sort"
	"strconv"
	"strings"
	"time"

	graph "memory/internal/memory/graph/domain"
	"memory/internal/memory/normalize"
)

// conditionMatches applies one parsed WHERE condition to a resolved field value.
func conditionMatches(condition Condition, actual any) bool {
	if orderedOperator(condition.Operator) && strings.TrimSpace(comparableString(actual)) == "" {
		return false
	}
	comparison := compareConditionValues(actual, condition.Value)
	switch condition.Operator {
	case OperatorEqual:
		return comparison == 0
	case OperatorNotEqual:
		return comparison != 0
	case OperatorLessThan:
		return comparison < 0
	case OperatorLessOrEqual:
		return comparison <= 0
	case OperatorGreaterThan:
		return comparison > 0
	case OperatorGreaterOrEqual:
		return comparison >= 0
	default:
		return false
	}
}

// orderedOperator reports whether an operator requires an existing sortable field.
func orderedOperator(operator ConditionOperator) bool {
	switch operator {
	case OperatorLessThan, OperatorLessOrEqual, OperatorGreaterThan, OperatorGreaterOrEqual:
		return true
	default:
		return false
	}
}

// compareConditionValues compares time, numeric, then case-folded string values.
func compareConditionValues(actual any, expected string) int {
	if left, ok := timeConditionValue(actual); ok {
		if right, ok := parseConditionTime(expected); ok {
			return compareTimes(left, right)
		}
	}
	if left, ok := numericValue(actual, true); ok {
		if right, ok := numericValue(expected, true); ok {
			return compareNumbers(left, right)
		}
	}
	return strings.Compare(strings.ToLower(comparableString(actual)), strings.ToLower(expected))
}

// timeConditionValue extracts a comparable time from a field value.
func timeConditionValue(value any) (time.Time, bool) {
	switch typed := value.(type) {
	case time.Time:
		return typed, true
	case *time.Time:
		if typed == nil {
			return time.Time{}, false
		}
		return *typed, true
	case string:
		return parseConditionTime(typed)
	default:
		return time.Time{}, false
	}
}

// parseConditionTime parses graph query time literals.
func parseConditionTime(value string) (time.Time, bool) {
	return normalize.ParseFlexibleTime(value)
}

// compareTimes compares two timestamp values.
func compareTimes(left time.Time, right time.Time) int {
	switch {
	case left.Before(right):
		return -1
	case left.After(right):
		return 1
	default:
		return 0
	}
}

// numericValue extracts numeric values, optionally parsing strings.
func numericValue(value any, parseStrings bool) (float64, bool) {
	switch typed := value.(type) {
	case int:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case float64:
		return typed, true
	case string:
		if !parseStrings {
			return 0, false
		}
		parsed, err := strconv.ParseFloat(strings.TrimSpace(typed), 64)
		return parsed, err == nil
	default:
		return 0, false
	}
}

// compareNumbers compares two numeric values.
func compareNumbers(left float64, right float64) int {
	switch {
	case left < right:
		return -1
	case left > right:
		return 1
	default:
		return 0
	}
}

// sortCandidates sorts query candidates by a metadata or property field.
func sortCandidates(candidates []queryCandidate, field string, order SortOrder) {
	if field == "" {
		sort.Slice(candidates, func(i, j int) bool {
			return candidates[i].node.UpdatedAt.After(candidates[j].node.UpdatedAt)
		})
		return
	}
	sort.Slice(candidates, func(i, j int) bool {
		comparison := compareRowValues(candidates[i].typedField(field), candidates[j].typedField(field))
		if order == SortDescending {
			return comparison > 0
		}
		return comparison < 0
	})
}

// sortMatchCandidates sorts match rows by a requested field.
func sortMatchCandidates(candidates []matchCandidate, field string, order SortOrder) {
	if field == "" {
		sort.Slice(candidates, func(i, j int) bool {
			if candidates[i].from.node.Title != candidates[j].from.node.Title {
				return candidates[i].from.node.Title < candidates[j].from.node.Title
			}
			return candidates[i].to.node.Title < candidates[j].to.node.Title
		})
		return
	}
	sort.Slice(candidates, func(i, j int) bool {
		comparison := compareRowValues(candidates[i].typedField(field), candidates[j].typedField(field))
		if order == SortDescending {
			return comparison > 0
		}
		return comparison < 0
	})
}

// queryValue returns the typed row value for a stored graph property.
func queryValue(value graph.Value) any {
	switch value.Type {
	case graph.ValueText:
		return value.Text
	case graph.ValueBool:
		parsed, err := strconv.ParseBool(value.Text)
		if err != nil {
			return value.Text
		}
		return parsed
	case graph.ValueNumber:
		return value.Number
	case graph.ValueTime:
		if value.Time == nil {
			return ""
		}
		return value.Time.UTC()
	case graph.ValueJSON:
		return value.JSON
	default:
		return ""
	}
}
