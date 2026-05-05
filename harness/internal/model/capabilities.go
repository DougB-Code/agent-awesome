// This file validates requested model capabilities.
package model

import (
	"fmt"

	"agent-awesome.com/harnessinternal/config/schema"
)

// ValidateRequestedCapabilities checks that the selected configured model
// declares every capability requested by the current invocation.
func ValidateRequestedCapabilities(requested schema.ModelCapabilities, selection schema.ProviderSelection) error {
	if requested.Streaming && !selection.Model.Capabilities.Streaming {
		return fmt.Errorf("provider %q model %q does not declare streaming support; set capabilities.streaming after verifying the configured model supports SSE", selection.Name, selection.Model.ID)
	}
	return nil
}
