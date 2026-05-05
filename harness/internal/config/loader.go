// This file loads and validates YAML configuration files.
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"agentawesome/internal/config/schema"
	"github.com/go-viper/mapstructure/v2"
	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

// LoadModel reads and validates model provider configuration.
func LoadModel(path string) (*schema.ModelConfig, error) {
	if strings.TrimSpace(path) == "" {
		path = DefaultModelPath()
	}

	var cfg schema.ModelConfig
	if err := loadYAML(path, &cfg); err != nil {
		return nil, fmt.Errorf("decode %s: %w", path, err)
	}
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("validate %s: %w", path, err)
	}
	return &cfg, nil
}

// LoadAgent reads and validates the agent definition configuration.
func LoadAgent(path string) (schema.Agent, error) {
	if strings.TrimSpace(path) == "" {
		path = DefaultAgentPath()
	}

	var agent schema.Agent
	if err := loadYAML(path, &agent); err != nil {
		return schema.Agent{}, fmt.Errorf("decode %s: %w", path, err)
	}
	if err := schema.ValidateAgent(agent); err != nil {
		return schema.Agent{}, fmt.Errorf("validate %s: %w", path, err)
	}
	return agent, nil
}

// LoadTools reads and validates tool configuration, treating a missing default
// tools file as an empty tool config.
func LoadTools(path string, explicit bool) (*schema.Tools, error) {
	if strings.TrimSpace(path) == "" {
		path = DefaultToolPath()
	}

	var cfg schema.Tools
	if err := loadYAML(path, &cfg); err != nil {
		if !explicit && path == DefaultToolPath() && isNotExist(err) {
			return &schema.Tools{}, nil
		}
		return nil, fmt.Errorf("decode %s: %w", path, err)
	}
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("validate %s: %w", path, err)
	}
	return &cfg, nil
}

// loadYAML decodes a YAML file into the target and rejects unknown fields.
func loadYAML(path string, target any) error {
	k := koanf.New(".")
	if err := k.Load(file.Provider(path), yaml.Parser()); err != nil {
		return fmt.Errorf("load %s: %w", path, err)
	}
	if err := k.UnmarshalWithConf("", target, koanf.UnmarshalConf{
		DecoderConfig: &mapstructure.DecoderConfig{
			ErrorUnused:      true,
			WeaklyTypedInput: true,
		},
	}); err != nil {
		return err
	}
	return nil
}

// isNotExist reports whether an error chain contains an os-not-exist error.
func isNotExist(err error) bool {
	for err != nil {
		if os.IsNotExist(err) {
			return true
		}
		err = errors.Unwrap(err)
	}
	return false
}
