// This file renders and reads console tool confirmation prompts.
package console

import (
	"fmt"
	"strconv"
	"strings"

	"google.golang.org/adk/tool/toolconfirmation"
	"google.golang.org/genai"
)

// PromptForConfirmation renders the runtime confirmation request, reads the
// user's choice, and returns the function response expected by the runtime.
func (c *Console) PromptForConfirmation(call *genai.FunctionCall) (*genai.Content, error) {
	confirmation, err := decodeToolConfirmation(call)
	if err != nil {
		return nil, err
	}
	fmt.Fprint(c.out, "\n\n")
	if strings.TrimSpace(confirmation.Hint) != "" {
		fmt.Fprintln(c.out, confirmation.Hint)
	} else {
		fmt.Fprintln(c.out, "The agent wants to use a local tool.")
	}
	options := confirmationOptions(confirmation.Payload)
	for i, option := range options {
		fmt.Fprintf(c.out, "  %d. %s\n", i+1, option.Label)
	}
	fmt.Fprintf(c.out, "Choose [1-%d]: ", len(options))

	choice, err := c.readOption(options)
	if err != nil {
		return nil, err
	}
	selected := options[choice-1]
	confirmed := selected.Action != "deny"
	response := map[string]any{"confirmed": confirmed}
	if confirmed && selected.Action != "" {
		response["payload"] = map[string]any{"action": selected.Action}
	}
	part := genai.NewPartFromFunctionResponse(toolconfirmation.FunctionCallName, response)
	part.FunctionResponse.ID = call.ID
	return genai.NewContentFromParts([]*genai.Part{part}, genai.RoleUser), nil
}

// readOption accepts numeric choices and y/n shortcuts until the user selects a
// valid confirmation option.
func (c *Console) readOption(options []confirmationOption) (int, error) {
	max := len(options)
	for {
		line, err := c.reader.ReadString('\n')
		if err != nil {
			return 0, err
		}
		line = strings.TrimSpace(line)
		if strings.EqualFold(line, "y") || strings.EqualFold(line, "yes") {
			return firstNonDenyOption(options), nil
		}
		if strings.EqualFold(line, "n") || strings.EqualFold(line, "no") {
			return denyOption(options), nil
		}
		value, err := strconv.Atoi(line)
		if err == nil && value >= 1 && value <= max {
			return value, nil
		}
		fmt.Fprintf(c.out, "Choose [1-%d]: ", max)
	}
}

// firstNonDenyOption returns the first approving option for the "yes" shortcut.
func firstNonDenyOption(options []confirmationOption) int {
	for i, option := range options {
		if option.Action != "deny" {
			return i + 1
		}
	}
	return 1
}

// denyOption returns the explicit deny option for the "no" shortcut.
func denyOption(options []confirmationOption) int {
	for i, option := range options {
		if option.Action == "deny" {
			return i + 1
		}
	}
	return len(options)
}
