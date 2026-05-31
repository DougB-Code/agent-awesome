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

var taskPriorityTokens = map[string]domain.TaskPriority{
	"high":     domain.TaskPriorityHigh,
	"low":      domain.TaskPriorityLow,
	"normal":   domain.TaskPriorityNormal,
	"medium":   domain.TaskPriorityNormal,
	"default":  domain.TaskPriorityNormal,
	"urgent":   domain.TaskPriorityUrgent,
	"critical": domain.TaskPriorityUrgent,
}

// DecodeCreateTaskRequest accepts the model-facing create_task payload.
func DecodeCreateTaskRequest(args json.RawMessage) (domain.CreateTaskRequest, error) {
	if len(args) == 0 || string(args) == "null" {
		args = []byte("{}")
	}
	var raw map[string]any
	if err := json.Unmarshal(args, &raw); err != nil {
		return domain.CreateTaskRequest{}, fmt.Errorf("invalid arguments: %w", err)
	}
	req := domain.CreateTaskRequest{
		Actor:          stringArg(raw["actor"]),
		DomainID:       domain.DomainID(stringArg(raw["domain_id"])),
		Firewall:       domain.Firewall(stringArg(raw["firewall"])),
		Title:          stringArg(raw["title"]),
		Description:    stringArg(raw["description"]),
		Priority:       taskPriorityArg(raw["priority"]),
		DueAt:          timeArg(raw["due_at"]),
		ScheduledAt:    timeArg(raw["scheduled_at"]),
		Topics:         stringListArg(raw["topics"]),
		IdempotencyKey: stringArg(raw["idempotency_key"]),
	}
	return req, nil
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
