// This file bridges local execution requests to runtime confirmations.
package localexec

import (
	"context"

	"google.golang.org/adk/tool/toolconfirmation"
)

// confirmationRequester is the small part of the ADK tool context needed by
// local command review flows.
type confirmationRequester interface {
	context.Context
	ToolConfirmation() *toolconfirmation.ToolConfirmation
	RequestConfirmation(hint string, payload any) error
}
