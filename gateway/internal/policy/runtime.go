// This file implements runtime policy injection for ADK run requests.
package policy

import (
	"bytes"
	"encoding/json"
	"strings"
)

// RuntimePolicyPrefix marks server-owned operating rules in agent input text.
const RuntimePolicyPrefix = "[[AGENT_AWESOME_RUNTIME_POLICY:"

// DefaultRuntimePolicyText is the gateway's default task-management guidance.
const DefaultRuntimePolicyText = "Graph-backed task management is auto-approved. When Doug asks to create, update, complete, cancel, delete, or link a task, call the task tool immediately. Do not ask for approval. Treat \"remember that I need to...\" as a task when it describes an action, purchase, errand, reminder, deadline, or commitment. Ask only for missing task details that block execution."

const runtimeSessionContextPrefix = "[[AGENT_AWESOME_SESSION_CONTEXT:"

// Config stores runtime policy injection settings.
type Config struct {
	Text string
}

// Injector adds configured runtime policy text to eligible ADK request bodies.
type Injector struct {
	text string
}

// NewInjector creates a runtime policy injector from configuration.
func NewInjector(config Config) *Injector {
	return &Injector{text: strings.TrimSpace(config.Text)}
}

// Enabled reports whether this injector has policy text to add.
func (i *Injector) Enabled() bool {
	return i != nil && strings.TrimSpace(i.text) != ""
}

// Inject adds configured policy text to user text run parts.
func (i *Injector) Inject(body []byte) ([]byte, bool, error) {
	if !i.Enabled() {
		return body, false, nil
	}
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
		part["text"] = i.runtimePolicy(sessionID) + text
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
func (i *Injector) runtimePolicy(sessionID string) string {
	policy := RuntimePolicyPrefix + " " + strings.TrimSpace(i.text) + "]]\n\n"
	if strings.TrimSpace(sessionID) == "" {
		return policy
	}
	return policy + runtimeSessionContextPrefix + " Current chat session id is \"" + sessionID + "\". For create_task calls made from this chat, include an idempotency_key beginning with \"agent_gateway:" + sessionID + ":\".]]\n\n"
}
