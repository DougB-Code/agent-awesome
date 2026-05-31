// This file resolves provider endpoint templates for concrete adapters.
package adapter

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"agentawesome/internal/config/schema"
)

// EnvLookup resolves one environment variable name.
type EnvLookup func(string) (string, bool)

const (
	// ProviderEndpointChat is the provider endpoint used for chat generation.
	ProviderEndpointChat = "chat"
)

// ResolveProviderURL expands a provider URL through the supplied lookup.
func ResolveProviderURL(provider schema.Provider, lookup EnvLookup) (string, error) {
	return expandEnv(strings.TrimSpace(provider.URL), lookup)
}

// ResolveProviderEndpoint expands a named provider endpoint through the lookup.
func ResolveProviderEndpoint(provider schema.Provider, endpoint string, lookup EnvLookup) (string, error) {
	key := strings.TrimSpace(endpoint)
	if key == "" {
		key = ProviderEndpointChat
	}
	raw := ""
	if provider.Endpoints != nil {
		raw = strings.TrimSpace(provider.Endpoints[key])
	}
	if raw == "" && key == ProviderEndpointChat {
		raw = strings.TrimSpace(provider.URL)
	}
	return expandEnv(raw, lookup)
}

// expandEnv expands environment variables and reports the first missing value.
func expandEnv(value string, lookup EnvLookup) (string, error) {
	if lookup == nil {
		lookup = func(string) (string, bool) { return "", false }
	}
	var missing []string
	expanded := os.Expand(value, func(name string) string {
		raw, ok := lookup(name)
		if !ok || strings.TrimSpace(raw) == "" {
			missing = append(missing, name)
			return ""
		}
		return raw
	})
	if len(missing) > 0 {
		sort.Strings(missing)
		return "", fmt.Errorf("environment variable %q is not set", missing[0])
	}
	return strings.TrimSpace(expanded), nil
}
