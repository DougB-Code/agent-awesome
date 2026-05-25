// This file validates agent configuration schema values.
package schema

import (
	"fmt"
	"strings"
)

// ValidateAgent checks the required fields for an agent config.
func ValidateAgent(agent Agent) error {
	if strings.TrimSpace(agent.Name) == "" {
		return fmt.Errorf("agent name must not be empty")
	}
	if strings.TrimSpace(agent.Instruction) == "" {
		return fmt.Errorf("agent %q instruction must not be empty", strings.TrimSpace(agent.Name))
	}
	if err := validateAgentValidations(agent.Validations); err != nil {
		return err
	}
	return nil
}

// validateAgentValidations checks portable agent behavior test metadata.
func validateAgentValidations(validations []AgentValidation) error {
	seen := make(map[string]struct{}, len(validations))
	for _, validation := range validations {
		id, err := validateAgentValidationID(validation.ID)
		if err != nil {
			return err
		}
		if _, ok := seen[id]; ok {
			return fmt.Errorf("agent validation duplicate %q", id)
		}
		seen[id] = struct{}{}
		switch strings.TrimSpace(validation.Mode) {
		case "", "mocked", "live":
		default:
			return fmt.Errorf("agent validation %q mode must be mocked or live", id)
		}
		if strings.TrimSpace(validation.Prompt) == "" {
			return fmt.Errorf("agent validation %q prompt must not be empty", id)
		}
		if err := validateAgentValidationExpected(id, validation.Expected); err != nil {
			return err
		}
		if err := validateAgentValidationAssertions(id, validation.Assertions); err != nil {
			return err
		}
	}
	return nil
}

// validateAgentValidationID trims and validates one agent validation id.
func validateAgentValidationID(value string) (string, error) {
	id := strings.TrimSpace(value)
	if id == "" {
		return "", fmt.Errorf("agent validation id must not be empty")
	}
	if !localExecCommandNamePattern.MatchString(id) {
		return "", fmt.Errorf("agent validation %q uses an invalid id", id)
	}
	return id, nil
}

// validateAgentValidationExpected checks legacy expected shortcuts.
func validateAgentValidationExpected(id string, expected map[string]any) error {
	for key, value := range expected {
		expectedKey := strings.TrimSpace(key)
		switch expectedKey {
		case "response_contains", "tool_call":
			if value == nil || strings.TrimSpace(fmt.Sprint(value)) == "" {
				return fmt.Errorf("agent validation %q expected %s must not be empty", id, expectedKey)
			}
		default:
			if expectedKey == "" {
				return fmt.Errorf("agent validation %q expected key must not be empty", id)
			}
			return fmt.Errorf("agent validation %q expected %q is unsupported", id, expectedKey)
		}
	}
	return nil
}

// validateAgentValidationAssertions checks agent assertion metadata.
func validateAgentValidationAssertions(id string, assertions []ValidationAssertion) error {
	for index, assertion := range assertions {
		assertionType := strings.TrimSpace(assertion.Type)
		switch assertionType {
		case "response-contains", "tool-call", "json-path", "schema":
		default:
			return fmt.Errorf("agent validation %q assertion %d uses an unsupported type", id, index+1)
		}
		if err := validateValidationAssertionExpectation("agent validation", id, index, assertion, assertionType); err != nil {
			return err
		}
	}
	return nil
}
