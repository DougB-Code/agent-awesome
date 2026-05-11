// This file normalizes create_task tool arguments into service requests.
package toolargs

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"memory/internal/memory/domain"
	"memory/internal/memory/normalize"
)

var taskStatusTokens = map[string]domain.TaskStatus{
	"blocked":     domain.TaskStatusBlocked,
	"canceled":    domain.TaskStatusCanceled,
	"cancelled":   domain.TaskStatusCanceled,
	"complete":    domain.TaskStatusDone,
	"completed":   domain.TaskStatusDone,
	"done":        domain.TaskStatusDone,
	"open":        domain.TaskStatusOpen,
	"pending":     domain.TaskStatusOpen,
	"todo":        domain.TaskStatusOpen,
	"to_do":       domain.TaskStatusOpen,
	"new":         domain.TaskStatusOpen,
	"backlog":     domain.TaskStatusOpen,
	"in_progress": domain.TaskStatusOpen,
	"doing":       domain.TaskStatusOpen,
	"waiting":     domain.TaskStatusWaiting,
	"waiting_on":  domain.TaskStatusWaiting,
}

var taskPriorityTokens = map[string]domain.TaskPriority{
	"high":     domain.TaskPriorityHigh,
	"low":      domain.TaskPriorityLow,
	"normal":   domain.TaskPriorityNormal,
	"medium":   domain.TaskPriorityNormal,
	"default":  domain.TaskPriorityNormal,
	"urgent":   domain.TaskPriorityUrgent,
	"critical": domain.TaskPriorityUrgent,
}

var qualitativeScoreTokens = map[string]float64{
	"low":      0.25,
	"medium":   0.5,
	"normal":   0.5,
	"high":     0.75,
	"urgent":   1,
	"critical": 1,
}

// DecodeCreateTaskRequest accepts a tiny create_task payload plus legacy extras.
func DecodeCreateTaskRequest(args json.RawMessage) (domain.CreateTaskRequest, error) {
	if len(args) == 0 || string(args) == "null" {
		args = []byte("{}")
	}
	var raw map[string]any
	if err := json.Unmarshal(args, &raw); err != nil {
		return domain.CreateTaskRequest{}, fmt.Errorf("invalid arguments: %w", err)
	}
	raw = normalizeCreateTaskArgs(raw)
	req := domain.CreateTaskRequest{
		Actor:           stringArg(raw["actor"]),
		Title:           firstStringArg(raw, "title", "text", "task"),
		Description:     firstStringArg(raw, "description", "note"),
		Status:          taskStatusArg(raw["status"]),
		Priority:        taskPriorityArg(raw["priority"]),
		DueAt:           timeArg(raw["due_at"]),
		ScheduledAt:     timeArg(raw["scheduled_at"]),
		FollowUpAt:      timeArg(raw["follow_up_at"]),
		Topics:          stringListArg(raw["topics"]),
		EstimateMinutes: intArg(raw["estimate_minutes"]),
		EnergyRequired:  stringArg(raw["energy_required"]),
		Effort:          scoreArg(raw["effort"]),
		Value:           scoreArg(raw["value"]),
		Urgency:         scoreArg(raw["urgency"]),
		Risk:            scoreArg(raw["risk"]),
		Context:         stringArg(raw["context"]),
		View:            stringArg(raw["view"]),
		Project:         stringArg(raw["project"]),
		Location:        stringArg(raw["location"]),
		Person:          firstStringArg(raw, "person", "owner", "assignee"),
		Source:          stringArg(raw["source"]),
		Confidence:      scoreArg(raw["confidence"]),
		IdempotencyKey:  stringArg(raw["idempotency_key"]),
	}
	if links, ok := memoryLinksArg(raw["memory_links"]); ok {
		req.MemoryLinks = links
	}
	if workBreakdown, ok := taskWorkBreakdownArg(raw["work_breakdown"]); ok {
		req.WorkBreakdown = workBreakdown
	}
	return req, nil
}

// normalizeCreateTaskArgs recovers model-emitted field:value keys.
func normalizeCreateTaskArgs(raw map[string]any) map[string]any {
	for key, value := range raw {
		if value != nil {
			continue
		}
		field, fieldValue, ok := splitMalformedCreateTaskKey(key)
		if !ok {
			continue
		}
		if _, exists := raw[field]; !exists {
			raw[field] = fieldValue
		}
	}
	return raw
}

// splitMalformedCreateTaskKey parses keys like title:<|"|>Buy milk<|"|>.
func splitMalformedCreateTaskKey(key string) (string, string, bool) {
	left, right, ok := strings.Cut(strings.TrimSpace(key), ":")
	if !ok {
		return "", "", false
	}
	field := strings.TrimSpace(left)
	if !knownCreateTaskField(field) {
		return "", "", false
	}
	value := strings.TrimSpace(right)
	value = strings.NewReplacer(`<|"|>`, `"`, `<|'|>`, `'`).Replace(value)
	value = strings.Trim(value, `"'`)
	value = strings.TrimSpace(value)
	if value == "" || strings.EqualFold(value, "null") {
		return "", "", false
	}
	return field, value, true
}

// knownCreateTaskField reports whether a field belongs to create_task input.
func knownCreateTaskField(field string) bool {
	switch field {
	case "actor", "title", "description", "status", "priority", "due_at", "scheduled_at", "follow_up_at", "topics", "estimate_minutes", "energy_required", "effort", "value", "urgency", "risk", "context", "view", "project", "location", "person", "owner", "assignee", "source", "confidence", "idempotency_key":
		return true
	default:
		return false
	}
}

// firstStringArg returns the first non-empty scalar string from named fields.
func firstStringArg(raw map[string]any, keys ...string) string {
	for _, key := range keys {
		value := stringArg(raw[key])
		if value != "" {
			return value
		}
	}
	return ""
}

// stringArg returns a trimmed scalar value suitable for string task fields.
func stringArg(value any) string {
	switch typed := value.(type) {
	case nil:
		return ""
	case string:
		return strings.TrimSpace(typed)
	case bool:
		return strconv.FormatBool(typed)
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	case float32:
		return strconv.FormatFloat(float64(typed), 'f', -1, 32)
	case int:
		return strconv.Itoa(typed)
	case int8:
		return strconv.Itoa(int(typed))
	case int16:
		return strconv.Itoa(int(typed))
	case int32:
		return strconv.Itoa(int(typed))
	case int64:
		return strconv.FormatInt(typed, 10)
	case uint:
		return strconv.FormatUint(uint64(typed), 10)
	case uint8:
		return strconv.FormatUint(uint64(typed), 10)
	case uint16:
		return strconv.FormatUint(uint64(typed), 10)
	case uint32:
		return strconv.FormatUint(uint64(typed), 10)
	case uint64:
		return strconv.FormatUint(typed, 10)
	case json.Number:
		return strings.TrimSpace(typed.String())
	default:
		return ""
	}
}

// taskStatusArg maps loose model vocabulary onto supported task statuses.
func taskStatusArg(value any) domain.TaskStatus {
	return taskStatusTokens[tokenArg(value)]
}

// taskPriorityArg maps loose model vocabulary onto supported priorities.
func taskPriorityArg(value any) domain.TaskPriority {
	return taskPriorityTokens[tokenArg(value)]
}

// tokenArg normalizes a scalar value for controlled-vocabulary matching.
func tokenArg(value any) string {
	token := strings.ToLower(stringArg(value))
	token = strings.ReplaceAll(token, "-", "_")
	token = strings.ReplaceAll(token, " ", "_")
	return token
}

// timeArg parses RFC3339 timestamps or YYYY-MM-DD dates from model fields.
func timeArg(value any) *time.Time {
	text := strings.TrimSpace(stringArg(value))
	if text == "" || strings.EqualFold(text, "null") {
		return nil
	}
	if parsed, ok := normalize.ParseFlexibleTime(text); ok {
		return &parsed
	}
	return nil
}

// stringListArg accepts arrays or comma-separated strings as task topics.
func stringListArg(value any) []string {
	values := []string{}
	switch typed := value.(type) {
	case []string:
		values = append(values, typed...)
	case []any:
		for _, item := range typed {
			if text := stringArg(item); text != "" {
				values = append(values, text)
			}
		}
	case string:
		for _, item := range strings.Split(typed, ",") {
			if text := strings.TrimSpace(item); text != "" {
				values = append(values, text)
			}
		}
	}
	return domain.NormalizeStrings(values)
}

// intArg reads a non-negative integer-like model field.
func intArg(value any) int {
	number, ok := numberArg(value)
	if !ok || number <= 0 {
		return 0
	}
	return int(number)
}

// scoreArg reads numeric or qualitative 0..1 scores from legacy task fields.
func scoreArg(value any) float64 {
	if number, ok := numberArg(value); ok {
		if number < 0 {
			return 0
		}
		if number > 1 {
			return 1
		}
		return number
	}
	if score, ok := qualitativeScoreTokens[tokenArg(value)]; ok {
		return score
	}
	return 0
}

// numberArg reads scalar numeric values from JSON-decoded arguments.
func numberArg(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		return typed, true
	case float32:
		return float64(typed), true
	case int:
		return float64(typed), true
	case int8:
		return float64(typed), true
	case int16:
		return float64(typed), true
	case int32:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case uint:
		return float64(typed), true
	case uint8:
		return float64(typed), true
	case uint16:
		return float64(typed), true
	case uint32:
		return float64(typed), true
	case uint64:
		return float64(typed), true
	case json.Number:
		number, err := typed.Float64()
		return number, err == nil
	case string:
		number, err := strconv.ParseFloat(strings.TrimSpace(typed), 64)
		return number, err == nil
	default:
		return 0, false
	}
}

// memoryLinksArg decodes valid memory links and ignores unrelated shapes.
func memoryLinksArg(value any) ([]domain.MemoryLinkRequest, bool) {
	if value == nil {
		return nil, false
	}
	if _, ok := value.([]any); !ok {
		return nil, false
	}
	bytes, err := json.Marshal(value)
	if err != nil {
		return nil, false
	}
	var links []domain.MemoryLinkRequest
	if err := json.Unmarshal(bytes, &links); err != nil {
		return nil, false
	}
	return links, true
}

// taskWorkBreakdownArg decodes object-shaped WBS metadata from advanced callers.
func taskWorkBreakdownArg(value any) (domain.TaskWorkBreakdown, bool) {
	if value == nil {
		return domain.TaskWorkBreakdown{}, false
	}
	if _, ok := value.(map[string]any); !ok {
		return domain.TaskWorkBreakdown{}, false
	}
	bytes, err := json.Marshal(value)
	if err != nil {
		return domain.TaskWorkBreakdown{}, false
	}
	var workBreakdown domain.TaskWorkBreakdown
	if err := json.Unmarshal(bytes, &workBreakdown); err != nil {
		return domain.TaskWorkBreakdown{}, false
	}
	return workBreakdown, true
}
