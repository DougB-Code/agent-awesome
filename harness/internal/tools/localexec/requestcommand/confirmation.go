// This file defines the confirmation interface used by request_command.
package requestcommand

import (
	"context"

	"google.golang.org/adk/tool/toolconfirmation"
)

// confirmationRequester is the small part of the ADK tool context needed by
// reviewed command flows.
type confirmationRequester interface {
	context.Context
	ToolConfirmation() *toolconfirmation.ToolConfirmation
	RequestConfirmation(hint string, payload any) error
}
