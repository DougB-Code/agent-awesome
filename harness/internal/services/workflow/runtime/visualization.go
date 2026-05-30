// This file builds workflow state-machine visualization artifacts.
package runtime

import (
	"fmt"
	"strings"

	"agentawesome/internal/services/workflow/definition"
)

// DefinitionDOT returns a Graphviz DOT view of one installed state-machine definition.
func (s *Service) DefinitionDOT(definitionID string) (string, bool) {
	def, ok := s.DescribeDefinition(definitionID)
	if !ok {
		return "", false
	}
	var builder strings.Builder
	builder.WriteString("digraph workflow {\n")
	builder.WriteString("  rankdir=LR;\n")
	writeStateDOT(&builder, def.States)
	builder.WriteString("}\n")
	return builder.String(), true
}

// writeStateDOT writes state nodes, child-entry links, and transitions.
func writeStateDOT(builder *strings.Builder, states []definition.StateDefinition) {
	for _, state := range states {
		label := strings.TrimSpace(state.ID)
		if len(state.OnEntry) > 0 {
			label = fmt.Sprintf("%s\\n%d entry action(s)", label, len(state.OnEntry))
		}
		builder.WriteString(fmt.Sprintf("  %q [label=%q];\n", state.ID, label))
		childInitial := strings.TrimSpace(state.Initial)
		if childInitial == "" && len(state.States) > 0 {
			childInitial = strings.TrimSpace(state.States[0].ID)
		}
		if childInitial != "" {
			builder.WriteString(fmt.Sprintf("  %q -> %q [label=%q];\n", state.ID, childInitial, "initial"))
		}
		for _, transition := range state.Transitions {
			target := strings.TrimSpace(transition.To)
			if target == "" {
				continue
			}
			label := strings.TrimSpace(transition.Trigger)
			builder.WriteString(fmt.Sprintf("  %q -> %q [label=%q];\n", state.ID, target, label))
		}
		writeStateDOT(builder, state.States)
	}
}
