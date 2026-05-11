// This file builds Worker secret values from generated and operator credentials.
package workersecrets

import (
	"fmt"
	"strings"

	"agentprovision/internal/cloudflare"
)

// InternalTokens stores generated internal gateway and persistence tokens.
type InternalTokens struct {
	GatewayToken     string
	PersistenceToken string
}

// Source reads one operator-provided Worker secret by name.
type Source interface {
	Lookup(name string) (string, error)
}

// BuildWithTokens builds complete Worker secret values using stable generated tokens.
func BuildWithTokens(deployment cloudflare.Deployment, source Source, tokens InternalTokens) (cloudflare.SecretValues, error) {
	generated, err := generatedValues(tokens)
	if err != nil {
		return nil, err
	}
	if source == nil {
		return nil, fmt.Errorf("secret source is required")
	}
	values := cloudflare.SecretValues{}
	for _, name := range deployment.RequiredSecrets {
		if value, ok := generated[name]; ok {
			values[name] = value
			continue
		}
		value, err := source.Lookup(name)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(value) == "" {
			return nil, fmt.Errorf("credential %s is required", name)
		}
		values[name] = value
	}
	return values, nil
}

// generatedValues maps generated token fields to their Worker secret names.
func generatedValues(tokens InternalTokens) (cloudflare.SecretValues, error) {
	if strings.TrimSpace(tokens.GatewayToken) == "" {
		return nil, fmt.Errorf("gateway token is required")
	}
	if strings.TrimSpace(tokens.PersistenceToken) == "" {
		return nil, fmt.Errorf("persistence token is required")
	}
	return cloudflare.SecretValues{
		"AGENTAWESOME_GATEWAY_TOKEN":     tokens.GatewayToken,
		"AGENTAWESOME_PERSISTENCE_TOKEN": tokens.PersistenceToken,
	}, nil
}
