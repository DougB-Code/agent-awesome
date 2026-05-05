// This file validates model configuration and resolves provider selections.
package schema

import (
	"fmt"
	"sort"
	"strings"
)

// Validate checks the model config shape and verifies the configured default.
func (c *ModelConfig) Validate() error {
	if c == nil {
		return fmt.Errorf("config is nil")
	}
	if len(c.Providers) == 0 {
		return fmt.Errorf("providers must not be empty")
	}

	for name, provider := range c.Providers {
		if err := validateProvider(name, provider); err != nil {
			return err
		}
	}

	providerName, modelID, err := parseDefault(c.Default)
	if err != nil {
		return err
	}
	if _, err := c.resolveProvider(providerName, modelID, false); err != nil {
		return fmt.Errorf("default %q: %w", c.Default, err)
	}
	return nil
}

// ResolveProvider returns the provider and model selected by explicit values or
// by the configured default.
func (c *ModelConfig) ResolveProvider(providerName, modelID string) (ProviderSelection, error) {
	if c == nil {
		return ProviderSelection{}, fmt.Errorf("config is nil")
	}

	providerName = strings.TrimSpace(providerName)
	explicitProvider := providerName != ""
	if !explicitProvider {
		defaultProvider, defaultModel, err := parseDefault(c.Default)
		if err != nil {
			return ProviderSelection{}, err
		}
		providerName = defaultProvider
		if strings.TrimSpace(modelID) == "" {
			modelID = defaultModel
		}
	}
	if providerName == "" {
		return ProviderSelection{}, fmt.Errorf("default is not set")
	}

	return c.resolveProvider(providerName, modelID, explicitProvider)
}

// resolveProvider validates and resolves one provider/model pair.
func (c *ModelConfig) resolveProvider(providerName, modelID string, explicitProvider bool) (ProviderSelection, error) {
	provider, ok := c.Providers[providerName]
	if !ok {
		return ProviderSelection{}, fmt.Errorf("provider %q not found", providerName)
	}

	if strings.TrimSpace(modelID) == "" && explicitProvider {
		modelID = strings.TrimSpace(provider.Default)
		if modelID == "" {
			return ProviderSelection{}, fmt.Errorf("provider %q requires --model-id; available models: %s", providerName, strings.Join(modelIDs(provider.Models), ", "))
		}
	}

	model, err := selectModel(provider.Models, modelID)
	if err != nil {
		return ProviderSelection{}, fmt.Errorf("provider %q: %w", providerName, err)
	}

	return ProviderSelection{Name: providerName, Provider: provider, Model: model}, nil
}

// parseDefault splits a provider:model default selector into its parts.
func parseDefault(value string) (providerName string, modelID string, err error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", "", fmt.Errorf("default is not set")
	}

	parts := strings.Split(value, ":")
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		return "", "", fmt.Errorf("default must be provider:model")
	}
	return strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1]), nil
}

// selectModel returns the configured model with the requested id.
func selectModel(models []Model, requestedID string) (Model, error) {
	if len(models) == 0 {
		return Model{}, fmt.Errorf("no models configured")
	}

	requestedID = strings.TrimSpace(requestedID)
	if requestedID == "" {
		return Model{}, fmt.Errorf("model id is required")
	}

	for _, model := range models {
		if strings.TrimSpace(model.ID) == requestedID {
			if strings.TrimSpace(model.Model) == "" {
				return Model{}, fmt.Errorf("model id %q is missing model", requestedID)
			}
			return model, nil
		}
	}
	return Model{}, fmt.Errorf("model id %q not found", requestedID)
}

// modelIDs returns sorted non-empty model ids for diagnostics.
func modelIDs(models []Model) []string {
	ids := make([]string, 0, len(models))
	for _, model := range models {
		if id := strings.TrimSpace(model.ID); id != "" {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	return ids
}
