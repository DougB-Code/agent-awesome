// This file defines the declarative workflow definition model.
package definition

// Definition is one user-authored state machine or DAG workflow.
type Definition struct {
	Kind        string            `json:"kind" yaml:"kind"`
	ID          string            `json:"id" yaml:"id"`
	Name        string            `json:"name,omitempty" yaml:"name,omitempty"`
	Description string            `json:"description,omitempty" yaml:"description,omitempty"`
	Schedule    string            `json:"schedule,omitempty" yaml:"schedule,omitempty"`
	Initial     string            `json:"initial,omitempty" yaml:"initial,omitempty"`
	States      []StateDefinition `json:"states,omitempty" yaml:"states,omitempty"`
	Nodes       []NodeDefinition  `json:"nodes,omitempty" yaml:"nodes,omitempty"`
}

// StateDefinition describes one state-machine state and its entry behavior.
type StateDefinition struct {
	ID          string                 `json:"id" yaml:"id"`
	OnEntry     []ActionDefinition     `json:"on_entry,omitempty" yaml:"on_entry,omitempty"`
	Transitions []TransitionDefinition `json:"transitions,omitempty" yaml:"transitions,omitempty"`
}

// TransitionDefinition describes one trigger-driven state transition.
type TransitionDefinition struct {
	Trigger string `json:"trigger" yaml:"trigger"`
	To      string `json:"to" yaml:"to"`
	Guard   string `json:"guard,omitempty" yaml:"guard,omitempty"`
}

// NodeDefinition describes one DAG node backed by a registered action.
type NodeDefinition struct {
	ID         string         `json:"id" yaml:"id"`
	Uses       string         `json:"uses" yaml:"uses"`
	DependsOn  []string       `json:"depends_on,omitempty" yaml:"depends_on,omitempty"`
	With       map[string]any `json:"with,omitempty" yaml:"with,omitempty"`
	Timeout    string         `json:"timeout,omitempty" yaml:"timeout,omitempty"`
	Retry      int            `json:"retry,omitempty" yaml:"retry,omitempty"`
	RetryDelay string         `json:"retry_delay,omitempty" yaml:"retry_delay,omitempty"`
}

// ActionDefinition describes one registered action invocation.
type ActionDefinition struct {
	ID   string         `json:"id,omitempty" yaml:"id,omitempty"`
	Uses string         `json:"uses" yaml:"uses"`
	With map[string]any `json:"with,omitempty" yaml:"with,omitempty"`
}
