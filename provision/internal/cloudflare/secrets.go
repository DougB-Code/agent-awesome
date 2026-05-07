package cloudflare

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"os"
)

const generatedTokenBytes = 32

// SecretValues stores secret material only in memory during provisioning.
type SecretValues map[string]string

// InternalTokens stores generated internal gateway and persistence tokens.
type InternalTokens struct {
	GatewayToken     string
	PersistenceToken string
}

// BuildSecrets builds per-agent secret values for one deployment.
func BuildSecrets(deployment Deployment, env SecretEnvironment) (SecretValues, error) {
	gatewayToken, err := randomToken()
	if err != nil {
		return nil, err
	}
	persistenceToken, err := randomToken()
	if err != nil {
		return nil, err
	}
	return BuildSecretsWithTokens(deployment, env, InternalTokens{GatewayToken: gatewayToken, PersistenceToken: persistenceToken})
}

// BuildSecretsWithTokens builds secret values using stable generated tokens.
func BuildSecretsWithTokens(deployment Deployment, env SecretEnvironment, tokens InternalTokens) (SecretValues, error) {
	if tokens.GatewayToken == "" {
		return nil, fmt.Errorf("gateway token is required")
	}
	if tokens.PersistenceToken == "" {
		return nil, fmt.Errorf("persistence token is required")
	}
	secrets := SecretValues{
		"AGENTAWESOME_GATEWAY_TOKEN":     tokens.GatewayToken,
		"AGENTAWESOME_PERSISTENCE_TOKEN": tokens.PersistenceToken,
	}
	openAIKey, err := env.Lookup("OPENAI_API_KEY")
	if err != nil {
		return nil, err
	}
	secrets["OPENAI_API_KEY"] = openAIKey
	if deployment.SlackEnabled {
		signingSecret, err := env.Lookup("SLACK_SIGNING_SECRET")
		if err != nil {
			return nil, err
		}
		botToken, err := env.Lookup("SLACK_BOT_TOKEN")
		if err != nil {
			return nil, err
		}
		secrets["SLACK_SIGNING_SECRET"] = signingSecret
		secrets["SLACK_BOT_TOKEN"] = botToken
	}
	return secrets, nil
}

// SecretEnvironment reads secret values from a provider.
type SecretEnvironment interface {
	Lookup(name string) (string, error)
}

// OSEnvironment reads secret values from process environment variables.
type OSEnvironment struct{}

// Lookup returns one non-empty process environment variable.
func (OSEnvironment) Lookup(name string) (string, error) {
	value := os.Getenv(name)
	if value == "" {
		return "", fmt.Errorf("environment variable %s is required", name)
	}
	return value, nil
}

// randomToken returns a URL-safe generated secret token.
func randomToken() (string, error) {
	data := make([]byte, generatedTokenBytes)
	if _, err := rand.Read(data); err != nil {
		return "", fmt.Errorf("generate token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}
