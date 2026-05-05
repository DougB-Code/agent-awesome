// This file defines validated agent metadata.
package agent

import (
	"fmt"
	"strings"
)

// Definition is a validated agent configuration ready for runtime construction.
type Definition struct {
	Name        string
	Description string
	Instruction string
}

// NewDefinition trims and validates the minimum fields required to run an
// agent.
func NewDefinition(name, description, instruction string) (Definition, error) {
	def := Definition{
		Name:        strings.TrimSpace(name),
		Description: strings.TrimSpace(description),
		Instruction: strings.TrimSpace(instruction),
	}
	if def.Name == "" {
		return Definition{}, fmt.Errorf("agent name must not be empty")
	}
	if def.Instruction == "" {
		return Definition{}, fmt.Errorf("agent %q instruction must not be empty", def.Name)
	}
	return def, nil
}
