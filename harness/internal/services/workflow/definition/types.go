// This file defines the declarative workflow state-machine model.
package definition

import (
	"agentawesome/internal/services/workflow/contracts"
)

// Definition is one user-authored executable hierarchical state machine.
type Definition struct {
	APIVersion  string             `json:"apiVersion,omitempty" yaml:"apiVersion,omitempty"`
	Kind        string             `json:"kind" yaml:"kind"`
	ID          string             `json:"id" yaml:"id"`
	Metadata    MetadataDefinition `json:"metadata,omitempty" yaml:"metadata,omitempty"`
	Name        string             `json:"name,omitempty" yaml:"name,omitempty"`
	Description string             `json:"description,omitempty" yaml:"description,omitempty"`
	Schedule    string             `json:"schedule,omitempty" yaml:"schedule,omitempty"`
	Initial     string             `json:"initial,omitempty" yaml:"initial,omitempty"`
	States      []StateDefinition  `json:"states,omitempty" yaml:"states,omitempty"`
	Authoring   map[string]any     `json:"authoring,omitempty" yaml:"authoring,omitempty"`
}

// MetadataDefinition stores workflow identity metadata for published definitions.
type MetadataDefinition struct {
	ID      string `json:"id,omitempty" yaml:"id,omitempty"`
	Name    string `json:"name,omitempty" yaml:"name,omitempty"`
	Version int    `json:"version,omitempty" yaml:"version,omitempty"`
}

// NodeDefinition describes one executable state entry action.
type NodeDefinition struct {
	ID         string             `json:"id" yaml:"id"`
	Type       string             `json:"type,omitempty" yaml:"type,omitempty"`
	Uses       string             `json:"uses,omitempty" yaml:"uses,omitempty"`
	Tool       string             `json:"tool,omitempty" yaml:"tool,omitempty"`
	With       map[string]any     `json:"with,omitempty" yaml:"with,omitempty"`
	Input      contracts.Contract `json:"input,omitempty" yaml:"input,omitempty"`
	Output     contracts.Contract `json:"output,omitempty" yaml:"output,omitempty"`
	Effects    contracts.Effects  `json:"effects,omitempty" yaml:"effects,omitempty"`
	Runtime    contracts.Runtime  `json:"runtime,omitempty" yaml:"runtime,omitempty"`
	Timeout    string             `json:"timeout,omitempty" yaml:"timeout,omitempty"`
	Retry      int                `json:"retry,omitempty" yaml:"retry,omitempty"`
	RetryDelay string             `json:"retry_delay,omitempty" yaml:"retry_delay,omitempty"`
}

// StateDefinition describes one hierarchical state-machine state.
type StateDefinition struct {
	ID          string                 `json:"id" yaml:"id"`
	Initial     string                 `json:"initial,omitempty" yaml:"initial,omitempty"`
	States      []StateDefinition      `json:"states,omitempty" yaml:"states,omitempty"`
	OnEntry     []NodeDefinition       `json:"on_entry,omitempty" yaml:"on_entry,omitempty"`
	Transitions []TransitionDefinition `json:"transitions,omitempty" yaml:"transitions,omitempty"`
}

// TransitionDefinition routes one completed state trigger to another state.
type TransitionDefinition struct {
	Trigger string `json:"trigger" yaml:"trigger"`
	To      string `json:"to,omitempty" yaml:"to,omitempty"`
}
