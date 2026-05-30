// This file defines workflow policy decision helpers.
package policy

import (
	"fmt"
	"regexp"
	"strings"

	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/envelope"
)

var sensitiveTextPattern = regexp.MustCompile(`(?i)(password|secret|token|credential|api[_-]?key|access[_-]?key)\s*[:=]\s*[^,\s;]+`)

const (
	// DecisionAllowed permits execution.
	DecisionAllowed = "allowed"
	// DecisionNeedsApproval pauses execution for user confirmation.
	DecisionNeedsApproval = "needs_approval"
	// DecisionBlocked rejects execution.
	DecisionBlocked = "blocked"
)

// Decision records the deterministic policy outcome for an action invocation.
type Decision struct {
	Status  string   `json:"status"`
	Reasons []string `json:"reasons,omitempty"`
}

// EvaluateInvocation checks an envelope against target node effects and runtime.
func EvaluateInvocation(input envelope.Envelope, effects contracts.Effects, runtime contracts.Runtime) Decision {
	var reasons []string
	if reason := runtimeSandboxReason(effects, runtime); reason != "" {
		reasons = append(reasons, reason)
	}
	if hasWildcardNetwork(effects) {
		reasons = append(reasons, "network effects must declare bounded hosts")
	}
	if containsUntrustedText(input) && hasFilesystemWrite(effects) {
		reasons = append(reasons, "untrusted text cannot flow directly into filesystem write effects")
	}
	if containsUntrustedText(input) && hasNetworkEffects(effects) {
		reasons = append(reasons, "untrusted text cannot flow directly into network effects")
	}
	if containsUntrustedText(input) && len(effects.Secrets.Required) > 0 {
		reasons = append(reasons, "untrusted text cannot flow directly into secret-using effects")
	}
	if ContainsSensitiveKey(input.ToMap()) && (hasNetworkEffects(effects) || hasFilesystemWrite(effects)) {
		reasons = append(reasons, "credential-like data cannot flow into network or filesystem write effects")
	}
	if len(reasons) > 0 {
		return Decision{Status: DecisionBlocked, Reasons: reasons}
	}
	if len(effects.UserConfirmation.RequiredFor) > 0 || len(effects.Secrets.Required) > 0 {
		return Decision{Status: DecisionNeedsApproval, Reasons: []string{"node declares user-confirmed or secret-using effects"}}
	}
	return Decision{Status: DecisionAllowed}
}

// Allowed reports whether a decision permits immediate execution.
func (d Decision) Allowed() bool {
	return strings.TrimSpace(d.Status) == "" || d.Status == DecisionAllowed
}

// containsUntrustedText reports whether the envelope carries text marked untrusted.
func containsUntrustedText(input envelope.Envelope) bool {
	if level, _ := input.Facets["trust.level"].(string); strings.EqualFold(strings.TrimSpace(level), "untrusted") {
		return true
	}
	if source, _ := input.Facets["source.trust"].(string); strings.EqualFold(strings.TrimSpace(source), "untrusted") {
		return true
	}
	return false
}

// hasFilesystemWrite reports whether effects include filesystem writes.
func hasFilesystemWrite(effects contracts.Effects) bool {
	return len(effects.Filesystem.Write) > 0
}

// hasNetworkEffects reports whether effects include network host access.
func hasNetworkEffects(effects contracts.Effects) bool {
	return len(effects.Network.AllowedHosts) > 0
}

// runtimeSandboxReason returns a blocking reason for missing or invalid sandboxes.
func runtimeSandboxReason(effects contracts.Effects, runtime contracts.Runtime) string {
	sandbox := strings.TrimSpace(runtime.Sandbox)
	if sandbox != "" && !contracts.SandboxSupported(sandbox) {
		return "runtime sandbox " + sandbox + " is not supported"
	}
	if sandbox == "" && nonAAEffects(effects) {
		return "effectful nodes must declare a runtime sandbox"
	}
	if sandbox == contracts.RuntimeSandboxAA && nonAAEffects(effects) {
		return "aa-runtime sandbox cannot execute network, filesystem, or secret effects"
	}
	return ""
}

// nonAAEffects reports whether effects leave the pure AA runtime boundary.
func nonAAEffects(effects contracts.Effects) bool {
	return len(effects.Filesystem.Read) > 0 ||
		len(effects.Filesystem.Write) > 0 ||
		len(effects.Network.AllowedHosts) > 0 ||
		len(effects.Secrets.Required) > 0
}

// hasWildcardNetwork reports unbounded network host declarations.
func hasWildcardNetwork(effects contracts.Effects) bool {
	for _, host := range effects.Network.AllowedHosts {
		normalized := strings.ToLower(strings.TrimSpace(host))
		if normalized == "*" || normalized == "0.0.0.0/0" || normalized == "::/0" {
			return true
		}
	}
	return false
}

// ContainsSensitiveKey reports whether JSON-like data appears to contain secrets.
func ContainsSensitiveKey(value any) bool {
	switch typed := value.(type) {
	case map[string]any:
		for key, item := range typed {
			if sensitiveKey(key) {
				return true
			}
			if ContainsSensitiveKey(item) {
				return true
			}
		}
	case []any:
		for _, item := range typed {
			if ContainsSensitiveKey(item) {
				return true
			}
		}
	}
	return false
}

// RedactSensitive returns a JSON-like copy with credential-like values removed.
func RedactSensitive(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			if sensitiveKey(key) {
				out[key] = "[REDACTED]"
				continue
			}
			out[key] = RedactSensitive(item)
		}
		return out
	case []any:
		out := make([]any, len(typed))
		for index, item := range typed {
			out[index] = RedactSensitive(item)
		}
		return out
	case string:
		return RedactString(typed)
	default:
		return typed
	}
}

// SanitizeLLMInput redacts credential-like data before model-boundary invocation.
func SanitizeLLMInput(input envelope.Envelope) envelope.Envelope {
	redacted, _ := OmitSensitive(RedactSensitive(input.ToMap())).(map[string]any)
	sanitized := envelope.FromMap(redacted)
	sanitized.SetFacet("llm.input_sanitized", true)
	if containsUntrustedText(input) {
		sanitized.SetFacet("llm.untrusted_input", true)
	}
	return sanitized
}

// OmitSensitive returns a JSON-like copy without credential-like keys.
func OmitSensitive(value any) any {
	switch typed := value.(type) {
	case map[string]any:
		out := make(map[string]any, len(typed))
		for key, item := range typed {
			if sensitiveKey(key) {
				continue
			}
			out[key] = OmitSensitive(item)
		}
		return out
	case []any:
		out := make([]any, len(typed))
		for index, item := range typed {
			out[index] = OmitSensitive(item)
		}
		return out
	default:
		return value
	}
}

// sensitiveKey reports whether a key name commonly carries credential material.
func sensitiveKey(key string) bool {
	normalized := strings.ToLower(strings.TrimSpace(key))
	return normalized == "password" ||
		strings.HasSuffix(normalized, "_password") ||
		normalized == "secret" ||
		strings.HasSuffix(normalized, "_secret") ||
		normalized == "token" ||
		strings.HasSuffix(normalized, "_token") ||
		normalized == "credential" ||
		strings.HasSuffix(normalized, "_credential") ||
		strings.Contains(normalized, "api_key") ||
		strings.Contains(normalized, "access_key")
}

// RedactString obscures inline credential-looking key-value fragments.
func RedactString(value string) string {
	return sensitiveTextPattern.ReplaceAllString(value, "$1=[REDACTED]")
}

// RedactError returns an error string with credential-looking fragments obscured.
func RedactError(err error) string {
	if err == nil {
		return ""
	}
	return RedactString(fmt.Sprint(err))
}
