// This file defines the confirmation boundary for local command review.
package review

import (
	"context"

	"google.golang.org/adk/tool/toolconfirmation"
)

// ConfirmationRequester is the runtime context behavior needed by local
// command review workflows.
type ConfirmationRequester interface {
	context.Context
	ToolConfirmation() *toolconfirmation.ToolConfirmation
	RequestConfirmation(hint string, payload any) error
}
