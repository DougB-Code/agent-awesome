// This file validates target workflow graph definitions.
package definition

import (
	"agentawesome/internal/services/workflow/adapters"
	"agentawesome/internal/services/workflow/contracts"
	"agentawesome/internal/services/workflow/decision"

	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	// KindWorkflow identifies a pipe-composable workflow graph.
	KindWorkflow = "workflow"
)

var safeIDPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// ActionCatalog reports whether a declarative action type is installed.
type ActionCatalog interface {
	Has(name string) bool
}

// Validate checks a workflow definition for deterministic, registered behavior.
func Validate(def Definition, actions ActionCatalog) error {
	if err := validateSafeID(def.ID, "workflow id"); err != nil {
		return err
	}
	if strings.TrimSpace(def.Kind) != KindWorkflow {
		return fmt.Errorf("workflow %q kind must be %q", def.ID, KindWorkflow)
	}
	if err := validateSchedule(def.Schedule); err != nil {
		return err
	}
	return validateWorkflowGraph(def, actions)
}

// validateWorkflowGraph checks pipe graph nodes, edges, mappings, and runtime policy.
func validateWorkflowGraph(def Definition, actions ActionCatalog) error {
	if len(def.Nodes) == 0 {
		return fmt.Errorf("workflow %q must define nodes", def.ID)
	}
	nodes := map[string]NodeDefinition{}
	for _, node := range def.Nodes {
		if err := validateSafeID(node.ID, "node id"); err != nil {
			return err
		}
		if _, ok := nodes[node.ID]; ok {
			return fmt.Errorf("workflow %q has duplicate node %q", def.ID, node.ID)
		}
		action := NodeAction(node)
		if err := validateAction(action, actions); err != nil {
			return fmt.Errorf("node %s: %w", node.ID, err)
		}
		if node.Retry < 0 {
			return fmt.Errorf("node %q retry must not be negative", node.ID)
		}
		if err := validateDuration(node.Timeout, "timeout", node.ID); err != nil {
			return err
		}
		if err := validateDuration(node.RetryDelay, "retry_delay", node.ID); err != nil {
			return err
		}
		nodes[node.ID] = node
	}
	mappings := map[string]struct{}{}
	for _, spec := range def.Mappings {
		name := strings.TrimSpace(spec.Name)
		if name == "" {
			return fmt.Errorf("workflow %q mapping name is required", def.ID)
		}
		if _, ok := mappings[name]; ok {
			return fmt.Errorf("workflow %q has duplicate mapping %q", def.ID, name)
		}
		mappings[name] = struct{}{}
	}
	for index, edge := range def.Edges {
		if err := validateSafeID(edge.From.Node, fmt.Sprintf("edge %d source node", index)); err != nil {
			return err
		}
		if err := validateSafeID(edge.To.Node, fmt.Sprintf("edge %d target node", index)); err != nil {
			return err
		}
		if _, ok := nodes[edge.From.Node]; !ok {
			return fmt.Errorf("edge %d source node %q is not defined", index, edge.From.Node)
		}
		if _, ok := nodes[edge.To.Node]; !ok {
			return fmt.Errorf("edge %d target node %q is not defined", index, edge.To.Node)
		}
		if strings.TrimSpace(edge.Adapter.MappingRef) != "" {
			if _, ok := mappings[strings.TrimSpace(edge.Adapter.MappingRef)]; !ok {
				return fmt.Errorf("edge %d mappingRef %q is not defined", index, edge.Adapter.MappingRef)
			}
		}
		if err := decision.ValidateWhen(edge.When); err != nil {
			return fmt.Errorf("edge %d: %w", index, err)
		}
		if !adapters.Declared(edge.Adapter) {
			compatibility := contracts.CheckCompatibility(nodes[edge.From.Node].Output, nodes[edge.To.Node].Input)
			if compatibility.Status != contracts.CompatibilityDirect {
				return fmt.Errorf("edge %d from %q to %q is not contract compatible: %s", index, edge.From.Node, edge.To.Node, compatibility.Explanation)
			}
		}
	}
	return validateNodeAcyclic(def)
}

// validateNodeAcyclic rejects pipe graph cycles before runtime scheduling.
func validateNodeAcyclic(def Definition) error {
	graph := map[string][]string{}
	for _, node := range def.Nodes {
		graph[node.ID] = nil
	}
	for _, edge := range def.Edges {
		graph[edge.To.Node] = append(graph[edge.To.Node], edge.From.Node)
	}
	visiting := map[string]bool{}
	visited := map[string]bool{}
	var visit func(string) error
	visit = func(id string) error {
		if visiting[id] {
			return fmt.Errorf("workflow nodes have dependency cycle involving %q", id)
		}
		if visited[id] {
			return nil
		}
		visiting[id] = true
		for _, dep := range graph[id] {
			if err := visit(dep); err != nil {
				return err
			}
		}
		visiting[id] = false
		visited[id] = true
		return nil
	}
	for id := range graph {
		if err := visit(id); err != nil {
			return err
		}
	}
	return nil
}

// validateAction ensures the action is supplied by the installed registry.
func validateAction(name string, actions ActionCatalog) error {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return fmt.Errorf("action uses is required")
	}
	if actions == nil || !actions.Has(trimmed) {
		return fmt.Errorf("action %q is not registered", trimmed)
	}
	return nil
}

// validateDuration checks one optional node duration field.
func validateDuration(value string, field string, nodeID string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	if _, err := time.ParseDuration(value); err != nil {
		return fmt.Errorf("node %q %s: %w", nodeID, field, err)
	}
	return nil
}

// validateSchedule accepts an empty schedule or a simple five-field cron shape.
func validateSchedule(value string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	fields := strings.Fields(trimmed)
	if len(fields) != 5 {
		return fmt.Errorf("schedule %q must use five-field cron syntax", trimmed)
	}
	if fields[2] != "*" || fields[3] != "*" || fields[4] != "*" {
		return fmt.Errorf("schedule %q must use daily minute/hour syntax", trimmed)
	}
	minute, err := strconv.Atoi(fields[0])
	if err != nil || minute < 0 || minute > 59 {
		return fmt.Errorf("schedule %q has invalid minute", trimmed)
	}
	hour, err := strconv.Atoi(fields[1])
	if err != nil || hour < 0 || hour > 23 {
		return fmt.Errorf("schedule %q has invalid hour", trimmed)
	}
	return nil
}

// validateSafeID checks ids used in durable records and route payloads.
func validateSafeID(value string, label string) error {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return fmt.Errorf("%s is required", label)
	}
	if !safeIDPattern.MatchString(trimmed) {
		return fmt.Errorf("%s %q is invalid", label, trimmed)
	}
	return nil
}

// HasPipeGraph reports whether a definition uses the target node-edge graph model.
func HasPipeGraph(def Definition) bool {
	return strings.TrimSpace(def.Kind) == KindWorkflow && len(def.Nodes) > 0
}

// NodeAction resolves the registered action used by a pipe graph node.
func NodeAction(node NodeDefinition) string {
	if strings.TrimSpace(node.Uses) != "" {
		return strings.TrimSpace(node.Uses)
	}
	switch strings.ToLower(strings.TrimSpace(node.Type)) {
	case "tool":
		return "tool.call"
	case "mcp":
		return "mcp.call"
	case "command":
		return "command.execute"
	case "llm", "model":
		return "llm.generate"
	case "workflow":
		return "workflow.run"
	case "assert", "validation":
		return "data.assert"
	case "decision":
		return "decision.route"
	case "human":
		return "human.request"
	case "delay", "wait":
		return "delay.until"
	default:
		return strings.TrimSpace(node.Type)
	}
}
