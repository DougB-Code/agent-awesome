// This file defines ADK before-tool callbacks for graph task invariants.
package callbacks

import (
	"fmt"
	"strings"
	"unicode"

	"google.golang.org/adk/agent/llmagent"
	"google.golang.org/adk/tool"
)

const taskIdempotencyPrefix = "agent_awesome"

// TaskInvariantCallbacks returns callbacks that normalize task tool calls.
func TaskInvariantCallbacks() []llmagent.BeforeToolCallback {
	return []llmagent.BeforeToolCallback{NormalizeCreateTask}
}

// NormalizeCreateTask fills deterministic create_task fields before execution.
func NormalizeCreateTask(ctx tool.Context, calledTool tool.Tool, args map[string]any) (map[string]any, error) {
	if calledTool == nil || calledTool.Name() != "create_task" {
		return nil, nil
	}
	sessionID := ""
	if ctx != nil {
		sessionID = ctx.SessionID()
	}
	normalizeCreateTaskArgs(args, sessionID)
	return nil, nil
}

// normalizeCreateTaskArgs mutates create_task arguments with local invariants.
func normalizeCreateTaskArgs(args map[string]any, sessionID string) {
	if args == nil {
		return
	}
	title := firstTaskText(args["title"], args["description"])
	if title != "" && taskText(args["title"]) == "" {
		args["title"] = title
	}
	if taskText(args["description"]) == "" {
		args["description"] = ""
	}
	if taskText(args["idempotency_key"]) != "" {
		return
	}
	sessionID = strings.TrimSpace(sessionID)
	if sessionID == "" || title == "" {
		return
	}
	args["idempotency_key"] = taskIdempotencyPrefix + ":" + sessionID + ":" + taskKeySlug(title)
}

// firstTaskText returns the first non-empty text value from a list of fields.
func firstTaskText(values ...any) string {
	for _, value := range values {
		if text := taskText(value); text != "" {
			return text
		}
	}
	return ""
}

// taskText converts a model-provided task field into normalized text.
func taskText(value any) string {
	text := strings.TrimSpace(fmt.Sprint(value))
	if text == "" || text == "<nil>" || strings.EqualFold(text, "null") {
		return ""
	}
	return text
}

// taskKeySlug returns a deterministic suffix for a session-scoped task key.
func taskKeySlug(value string) string {
	parts := []string{}
	var current strings.Builder
	for _, r := range strings.ToLower(value) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			current.WriteRune(r)
			continue
		}
		if current.Len() > 0 {
			parts = append(parts, current.String())
			current.Reset()
		}
	}
	if current.Len() > 0 {
		parts = append(parts, current.String())
	}
	if len(parts) == 0 {
		return "task"
	}
	return strings.Join(parts, "_")
}
