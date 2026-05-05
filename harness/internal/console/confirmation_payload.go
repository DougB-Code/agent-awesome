// This file decodes runtime tool confirmation payloads.
package console

import (
	"encoding/json"
	"fmt"

	"google.golang.org/adk/tool/toolconfirmation"
	"google.golang.org/genai"
)

// decodeToolConfirmation converts the generic function-call payload into the
// runtime's typed confirmation request.
func decodeToolConfirmation(call *genai.FunctionCall) (toolconfirmation.ToolConfirmation, error) {
	raw, ok := call.Args["toolConfirmation"]
	if !ok {
		return toolconfirmation.ToolConfirmation{}, fmt.Errorf("confirmation request missing toolConfirmation payload")
	}
	data, err := json.Marshal(raw)
	if err != nil {
		return toolconfirmation.ToolConfirmation{}, fmt.Errorf("marshal confirmation payload: %w", err)
	}
	var confirmation toolconfirmation.ToolConfirmation
	if err := json.Unmarshal(data, &confirmation); err != nil {
		return toolconfirmation.ToolConfirmation{}, fmt.Errorf("decode confirmation payload: %w", err)
	}
	return confirmation, nil
}

type confirmationOption struct {
	Action string `json:"action"`
	Label  string `json:"label"`
}

// confirmationOptions extracts the options supplied by the tool. Older or
// malformed payloads fall back to a small deny/approve-once menu.
func confirmationOptions(payload any) []confirmationOption {
	var body struct {
		Options []confirmationOption `json:"options"`
	}
	data, err := json.Marshal(payload)
	if err == nil {
		_ = json.Unmarshal(data, &body)
	}
	if len(body.Options) > 0 {
		return body.Options
	}
	return []confirmationOption{
		{Action: "deny", Label: "Deny"},
		{Action: "approve_once", Label: "Approve once"},
	}
}
