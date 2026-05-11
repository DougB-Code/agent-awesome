// This file validates provider configuration and resolves provider fields.
package schema

import (
	"fmt"
	"strings"
)

// Adapter returns the normalized adapter name from the selected provider.
func (s ProviderSelection) Adapter() string {
	return strings.TrimSpace(s.Provider.Adapter)
}

// ModelName returns the provider-native model name for the selection.
func (s ProviderSelection) ModelName() string {
	return strings.TrimSpace(s.Model.Model)
}

// AuthMode returns the normalized provider authentication policy.
func (p Provider) AuthMode() string {
	return strings.ToLower(strings.TrimSpace(p.Auth))
}

// validateProvider checks provider-level fields and model ids.
func validateProvider(name string, provider Provider) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return fmt.Errorf("provider name must not be empty")
	}
	if strings.TrimSpace(provider.Adapter) == "" {
		return fmt.Errorf("provider %q requires adapter", name)
	}
	if err := validateProviderAuth(name, provider); err != nil {
		return err
	}

	seen := make(map[string]struct{}, len(provider.Models))
	if len(provider.Models) == 0 {
		return fmt.Errorf("provider %q: no models configured", name)
	}
	for _, model := range provider.Models {
		id := strings.TrimSpace(model.ID)
		if id == "" {
			return fmt.Errorf("provider %q: model id must not be empty", name)
		}
		if strings.TrimSpace(model.Model) == "" {
			return fmt.Errorf("provider %q: model id %q is missing model", name, id)
		}
		if _, ok := seen[id]; ok {
			return fmt.Errorf("provider %q: duplicate model id %q", name, id)
		}
		seen[id] = struct{}{}
	}

	if defaultModel := strings.TrimSpace(provider.Default); defaultModel != "" {
		if _, ok := seen[defaultModel]; !ok {
			return fmt.Errorf("provider %q: default model id %q not found", name, defaultModel)
		}
	}

	return nil
}

// validateProviderAuth checks the provider authentication policy enum.
func validateProviderAuth(name string, provider Provider) error {
	switch provider.AuthMode() {
	case "", ProviderAuthRequired, ProviderAuthOptional:
		return nil
	default:
		return fmt.Errorf("provider %q auth must be %q or %q", name, ProviderAuthRequired, ProviderAuthOptional)
	}
}
