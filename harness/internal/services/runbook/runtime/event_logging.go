// This file records runbook events with redacted event data.
package runtime

import (
	"context"

	"agentawesome/internal/services/runbook/policy"
)

// appendEvent stores one runbook event after redacting credential-like values.
func (s *Service) appendEvent(ctx context.Context, runID string, eventType string, message string, data map[string]any) error {
	redacted, _ := policy.RedactSensitive(data).(map[string]any)
	if redacted == nil && data != nil {
		redacted = map[string]any{}
	}
	return s.store.AppendEvent(ctx, runID, eventType, policy.RedactString(message), redacted)
}
