// This file tests agent definition validation.
package agent

import (
	"testing"
)

func TestNewDefinitionTrimsAgentDefinition(t *testing.T) {
	def, err := NewDefinition(" test_agent ", " Test agent. ", " Be helpful. ")
	if err != nil {
		t.Fatalf("NewDefinition() error = %v", err)
	}
	if got, want := def.Name, "test_agent"; got != want {
		t.Fatalf("Name = %q, want %q", got, want)
	}
	if got, want := def.Description, "Test agent."; got != want {
		t.Fatalf("Description = %q, want %q", got, want)
	}
	if got, want := def.Instruction, "Be helpful."; got != want {
		t.Fatalf("Instruction = %q, want %q", got, want)
	}
}

func TestNewDefinitionRejectsMissingInstruction(t *testing.T) {
	_, err := NewDefinition("test_agent", "", "")
	if err == nil {
		t.Fatalf("NewDefinition() error = nil, want validation error")
	}
}
