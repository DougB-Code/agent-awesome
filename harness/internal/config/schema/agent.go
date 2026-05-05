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
	return nil
}
