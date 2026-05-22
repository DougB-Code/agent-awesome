// This file builds workflow graph visualization artifacts.
package runtime

import (
	"fmt"
	"sort"
	"strings"

	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/definition"
)

// DefinitionDOT returns a Graphviz DOT view of one installed workflow definition.
func (s *Service) DefinitionDOT(definitionID string) (string, bool) {
	def, ok := s.DescribeDefinition(definitionID)
	if !ok {
		return "", false
	}
	var builder strings.Builder
	builder.WriteString("digraph workflow {\n")
	builder.WriteString("  rankdir=LR;\n")
	nodes := append([]definition.NodeDefinition(nil), def.Nodes...)
	sort.Slice(nodes, func(i int, j int) bool { return nodes[i].ID < nodes[j].ID })
	for _, node := range nodes {
		label := strings.TrimSpace(node.ID)
		if action := definition.NodeAction(node); action != "" {
			label += "\\n" + action
		}
		builder.WriteString(fmt.Sprintf("  %q [label=%q];\n", node.ID, label))
	}
	edges := append([]definition.EdgeDefinition(nil), def.Edges...)
	sort.Slice(edges, func(i int, j int) bool {
		left := edges[i].From.Node + "/" + edges[i].To.Node
		right := edges[j].From.Node + "/" + edges[j].To.Node
		return left < right
	})
	for _, edge := range edges {
		label := edgeLabel(edge)
		if label == "" {
			builder.WriteString(fmt.Sprintf("  %q -> %q;\n", edge.From.Node, edge.To.Node))
			continue
		}
		builder.WriteString(fmt.Sprintf("  %q -> %q [label=%q];\n", edge.From.Node, edge.To.Node, label))
	}
	builder.WriteString("}\n")
	return builder.String(), true
}

// edgeLabel returns adapter and condition details suitable for DOT labels.
func edgeLabel(edge definition.EdgeDefinition) string {
	parts := []string{}
	if label := adapterLabel(edge.Adapter); label != "" {
		parts = append(parts, label)
	}
	if strings.TrimSpace(edge.When.Expr) != "" {
		parts = append(parts, "when: "+strings.TrimSpace(edge.When.Expr))
	} else if strings.TrimSpace(edge.When.Path) != "" {
		parts = append(parts, "when: "+strings.TrimSpace(edge.When.Path))
	}
	return strings.Join(parts, "\\n")
}

// adapterLabel returns a compact adapter description for visualization.
func adapterLabel(adapter adapters.Definition) string {
	switch {
	case strings.TrimSpace(adapter.MappingRef) != "":
		return "mapping: " + strings.TrimSpace(adapter.MappingRef)
	case adapter.Mapping != nil && strings.TrimSpace(adapter.Mapping.Name) != "":
		return "mapping: " + strings.TrimSpace(adapter.Mapping.Name)
	case strings.TrimSpace(adapter.Kind) != "":
		return "adapter: " + strings.TrimSpace(adapter.Kind)
	default:
		return ""
	}
}
