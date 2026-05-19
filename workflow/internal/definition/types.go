// This file defines the declarative workflow definition model.
package definition

// Definition is one user-authored executable state-machine workflow.
type Definition struct {
	Kind        string            `json:"kind" yaml:"kind"`
	ID          string            `json:"id" yaml:"id"`
	Name        string            `json:"name,omitempty" yaml:"name,omitempty"`
	Description string            `json:"description,omitempty" yaml:"description,omitempty"`
	Schedule    string            `json:"schedule,omitempty" yaml:"schedule,omitempty"`
	Initial     string            `json:"initial,omitempty" yaml:"initial,omitempty"`
	States      []StateDefinition `json:"states,omitempty" yaml:"states,omitempty"`
	Authoring   map[string]any    `json:"authoring,omitempty" yaml:"authoring,omitempty"`
}

// StateDefinition describes one process state or one durable task state.
type StateDefinition struct {
	ID          string                 `json:"id" yaml:"id"`
	Type        string                 `json:"type,omitempty" yaml:"type,omitempty"`
	Uses        string                 `json:"uses,omitempty" yaml:"uses,omitempty"`
	DependsOn   []string               `json:"depends_on,omitempty" yaml:"depends_on,omitempty"`
	With        map[string]any         `json:"with,omitempty" yaml:"with,omitempty"`
	Timeout     string                 `json:"timeout,omitempty" yaml:"timeout,omitempty"`
	Retry       int                    `json:"retry,omitempty" yaml:"retry,omitempty"`
	RetryDelay  string                 `json:"retry_delay,omitempty" yaml:"retry_delay,omitempty"`
	OnEntry     []ActionDefinition     `json:"on_entry,omitempty" yaml:"on_entry,omitempty"`
	Transitions []TransitionDefinition `json:"transitions,omitempty" yaml:"transitions,omitempty"`
}

// TransitionDefinition describes one trigger-driven state transition.
type TransitionDefinition struct {
	Trigger string `json:"trigger" yaml:"trigger"`
	To      string `json:"to" yaml:"to"`
	Guard   string `json:"guard,omitempty" yaml:"guard,omitempty"`
}

// ActionDefinition describes one registered action invocation.
type ActionDefinition struct {
	ID   string         `json:"id,omitempty" yaml:"id,omitempty"`
	Uses string         `json:"uses" yaml:"uses"`
	With map[string]any `json:"with,omitempty" yaml:"with,omitempty"`
}
