// This file resolves runbook node manifests from action metadata and node policy.
package runtime

import (
	"strings"

	"agentawesome/internal/services/runbook/actions"
	"agentawesome/internal/services/runbook/contracts"
	"agentawesome/internal/services/runbook/definition"
)

// manifestForNode resolves the callable contract for one graph node.
func manifestForNode(node definition.NodeDefinition) contracts.ToolManifest {
	actionName := definition.NodeAction(node)
	action := actions.ManifestForMetadata(actions.MetadataFor(actionName))
	manifest := action
	manifest.ID = nodeManifestID(node, actionName)
	manifest.Input = mergeContract(action.Input, node.Input)
	manifest.Output = mergeContract(action.Output, node.Output)
	manifest.Effects = mergeEffects(action.Effects, node.Effects)
	manifest.Runtime = mergeRuntime(action.Runtime, node.Runtime)
	return manifest
}

// nodeManifestID returns a stable manifest id for a concrete node.
func nodeManifestID(node definition.NodeDefinition, actionName string) string {
	if strings.TrimSpace(node.Tool) != "" {
		return strings.TrimSpace(node.Tool)
	}
	if strings.TrimSpace(node.Uses) == "tool.call" {
		if name, ok := node.With["name"].(string); ok && strings.TrimSpace(name) != "" {
			return strings.TrimSpace(name)
		}
	}
	if strings.TrimSpace(node.Uses) != "" {
		return strings.TrimSpace(node.Uses)
	}
	return strings.TrimSpace(actionName)
}

// mergeContract prefers explicit node contracts over action defaults.
func mergeContract(base contracts.Contract, override contracts.Contract) contracts.Contract {
	if !contractDeclared(override) {
		return base
	}
	return override
}

// contractDeclared reports whether a node side declares contract data.
func contractDeclared(contract contracts.Contract) bool {
	return len(contract.Accepts) > 0 ||
		len(contract.Produces) > 0 ||
		len(contract.RequiredFacets) > 0 ||
		len(contract.Facets) > 0 ||
		len(contract.Schema) > 0 ||
		len(contract.Examples) > 0
}

// mergeEffects prefers explicit node effects over action defaults.
func mergeEffects(base contracts.Effects, override contracts.Effects) contracts.Effects {
	if len(override.Filesystem.Read) > 0 ||
		len(override.Filesystem.Write) > 0 ||
		len(override.Network.AllowedHosts) > 0 ||
		len(override.Secrets.Required) > 0 ||
		len(override.UserConfirmation.RequiredFor) > 0 {
		return override
	}
	return base
}

// mergeRuntime prefers explicit node runtime policy over action defaults.
func mergeRuntime(base contracts.Runtime, override contracts.Runtime) contracts.Runtime {
	merged := base
	if override.TimeoutMS != 0 {
		merged.TimeoutMS = override.TimeoutMS
	}
	if override.MaxInputBytes != 0 {
		merged.MaxInputBytes = override.MaxInputBytes
	}
	if override.MaxArtifactBytes != 0 {
		merged.MaxArtifactBytes = override.MaxArtifactBytes
	}
	if override.RateLimitPerMinute != 0 {
		merged.RateLimitPerMinute = override.RateLimitPerMinute
	}
	if override.Idempotent {
		merged.Idempotent = true
	}
	if override.Retryable {
		merged.Retryable = true
	}
	if strings.TrimSpace(override.Sandbox) != "" {
		merged.Sandbox = strings.TrimSpace(override.Sandbox)
	}
	return merged
}
