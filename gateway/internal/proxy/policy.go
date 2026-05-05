package proxy

import (
	"bytes"
	"encoding/json"
	"strings"
)

// RuntimePolicyPrefix carries server-owned operating rules to the agent.
const RuntimePolicyPrefix = "[[AURORA_RUNTIME_POLICY:"

const runtimePolicyBody = " Graph-backed task management is auto-approved. When Doug asks to create, update, complete, cancel, delete, or link a task, call the task tool immediately. Do not ask for approval. Treat \"remember that I need to...\" as a task when it describes an action, purchase, errand, reminder, deadline, or commitment. Ask only for missing task details that block execution.]]\n\n"

const runtimeSessionContextPrefix = "[[AURORA_SESSION_CONTEXT:"

// InjectRuntimePolicy adds gateway-owned policy text to user text run parts.
func InjectRuntimePolicy(body []byte) ([]byte, bool, error) {
	var payload map[string]any
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.UseNumber()
	if err := decoder.Decode(&payload); err != nil {
		return body, false, nil
	}
	sessionID, _ := payload["sessionId"].(string)
	message, ok := payload["newMessage"].(map[string]any)
	if !ok {
		return body, false, nil
	}
	parts, ok := message["parts"].([]any)
	if !ok {
		return body, false, nil
	}

	changed := false
	for _, rawPart := range parts {
		part, ok := rawPart.(map[string]any)
		if !ok {
			continue
		}
		text, ok := part["text"].(string)
		if !ok || text == "" || strings.HasPrefix(text, RuntimePolicyPrefix) {
			continue
		}
		part["text"] = runtimePolicy(sessionID) + text
		changed = true
	}
	if !changed {
		return body, false, nil
	}
	next, err := json.Marshal(payload)
	if err != nil {
		return nil, false, err
	}
	return next, true, nil
}

// runtimePolicy builds the complete policy prefix for one session.
func runtimePolicy(sessionID string) string {
	policy := RuntimePolicyPrefix + runtimePolicyBody
	if strings.TrimSpace(sessionID) == "" {
		return policy
	}
	return policy + runtimeSessionContextPrefix + " Current chat session id is \"" + sessionID + "\". For create_task calls made from this chat, include an idempotency_key beginning with \"agent_gateway:" + sessionID + ":\".]]\n\n"
}
