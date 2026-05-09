// This file implements optional operator policy injection for ADK run requests.
package policy

import (
	"bytes"
	"encoding/json"
	"strings"
)

// RuntimePolicyPrefix marks server-owned operating rules in agent input text.
const RuntimePolicyPrefix = "[[AGENT_AWESOME_RUNTIME_POLICY:"

// DefaultRuntimePolicyText is empty because runtime invariants live in ADK.
const DefaultRuntimePolicyText = ""

// Config stores optional operator policy injection settings.
type Config struct {
	Text string
}

// Injector adds operator-configured policy text to eligible ADK request bodies.
type Injector struct {
	text string
}

// NewInjector creates an operator policy injector from configuration.
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
		part["text"] = i.runtimePolicy() + text
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

// runtimePolicy builds the complete operator policy prefix.
func (i *Injector) runtimePolicy() string {
	return RuntimePolicyPrefix + " " + strings.TrimSpace(i.text) + "]]\n\n"
}
