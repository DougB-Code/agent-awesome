// This file loads and validates YAML configuration files.
package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"time"

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
	return loadTools(path, explicit, true)
}

// LoadToolPackage reads and validates one package without merging sibling MCP
// package configs.
func LoadToolPackage(path string) (*schema.Tools, error) {
	return loadTools(path, true, false)
}

// loadTools decodes a tool config with optional adjacent MCP package merging.
func loadTools(path string, explicit bool, mergeMCPPackages bool) (*schema.Tools, error) {
	if strings.TrimSpace(path) == "" {
		path = DefaultToolPath()
	}

	var cfg schema.Tools
	if err := loadYAML(path, &cfg); err != nil {
		if !explicit && path == DefaultToolPath() && isNotExist(err) {
			cfg = schema.Tools{}
		} else {
			return nil, fmt.Errorf("decode %s: %w", path, err)
		}
	}
	if mergeMCPPackages {
		if err := loadMCPPackageConfigs(mcpConfigDirForToolPath(path), &cfg); err != nil {
			return nil, err
		}
	}
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("validate %s: %w", path, err)
	}
	return &cfg, nil
}

// loadYAML decodes a YAML file into the target and rejects unknown fields.
func loadYAML(path string, target any) error {
	k := koanf.New(".")
	data, err := os.ReadFile(path)
	if err != nil {
		if err := k.Load(file.Provider(path), yaml.Parser()); err != nil {
			return fmt.Errorf("load %s: %w", path, err)
		}
	} else if err := k.Load(bytesProvider{data: expandKnownEnvironment(data)}, yaml.Parser()); err != nil {
		return fmt.Errorf("load %s: %w", path, err)
	}
	if err := k.UnmarshalWithConf("", target, koanf.UnmarshalConf{
		DecoderConfig: &mapstructure.DecoderConfig{
			ErrorUnused:      true,
			WeaklyTypedInput: true,
			DecodeHook:       mapstructure.ComposeDecodeHookFunc(yamlTimeToStringHook),
		},
	}); err != nil {
		return err
	}
	return nil
}

// yamlTimeToStringHook preserves timestamp-like scalar strings parsed by YAML.
func yamlTimeToStringHook(from reflect.Type, to reflect.Type, data any) (any, error) {
	if from == reflect.TypeOf(time.Time{}) && to.Kind() == reflect.String {
		return data.(time.Time).Format(time.RFC3339Nano), nil
	}
	return data, nil
}

// expandKnownEnvironment expands configured environment references without
// destroying workflow-style references that intentionally remain unresolved.
func expandKnownEnvironment(data []byte) []byte {
	text := string(data)
	var out strings.Builder
	out.Grow(len(text))
	for index := 0; index < len(text); {
		if text[index] != '$' || index+1 >= len(text) {
			out.WriteByte(text[index])
			index++
			continue
		}
		if text[index+1] == '{' {
			end := strings.IndexByte(text[index+2:], '}')
			if end < 0 {
				out.WriteByte(text[index])
				index++
				continue
			}
			end += index + 2
			name := text[index+2 : end]
			if value, ok := os.LookupEnv(name); ok {
				out.WriteString(value)
			} else {
				out.WriteString(text[index : end+1])
			}
			index = end + 1
			continue
		}
		nameEnd := index + 1
		for nameEnd < len(text) && isEnvironmentNameByte(text[nameEnd]) {
			nameEnd++
		}
		if nameEnd == index+1 {
			out.WriteByte(text[index])
			index++
			continue
		}
		name := text[index+1 : nameEnd]
		if value, ok := os.LookupEnv(name); ok {
			out.WriteString(value)
		} else {
			out.WriteString(text[index:nameEnd])
		}
		index = nameEnd
	}
	return []byte(out.String())
}

// isEnvironmentNameByte reports whether b is valid in simple $NAME references.
func isEnvironmentNameByte(b byte) bool {
	return b == '_' ||
		('A' <= b && b <= 'Z') ||
		('a' <= b && b <= 'z') ||
		('0' <= b && b <= '9')
}

// bytesProvider gives koanf already-expanded configuration bytes.
type bytesProvider struct {
	data []byte
}

// ReadBytes returns raw configuration bytes.
func (p bytesProvider) ReadBytes() ([]byte, error) {
	return p.data, nil
}

// Read is unused when a parser is supplied.
func (p bytesProvider) Read() (map[string]any, error) {
	return nil, nil
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

// loadMCPPackageConfigs merges package-scoped MCP server configs beside tools.
func loadMCPPackageConfigs(directory string, cfg *schema.Tools) error {
	if strings.TrimSpace(directory) == "" {
		return nil
	}
	paths, err := mcpPackageConfigPaths(directory)
	if err != nil {
		return err
	}
	for _, path := range paths {
		var packageCfg schema.Tools
		if err := loadYAML(path, &packageCfg); err != nil {
			return fmt.Errorf("decode MCP package %s: %w", path, err)
		}
		mergeMCPConfig(cfg, packageCfg.MCP)
	}
	return nil
}

// mcpPackageConfigPaths returns package mcp.yaml files in stable order.
func mcpPackageConfigPaths(directory string) ([]string, error) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("list MCP package directory %s: %w", directory, err)
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.Type()&os.ModeSymlink != 0 {
			continue
		}
		path := filepath.Join(directory, entry.Name())
		if entry.IsDir() {
			candidate := filepath.Join(path, schema.DefaultMCPFilename)
			if _, err := os.Stat(candidate); err == nil {
				paths = append(paths, candidate)
			} else if err != nil && !os.IsNotExist(err) {
				return nil, fmt.Errorf("stat MCP package %s: %w", candidate, err)
			}
			continue
		}
		if isYAMLConfigPath(path) {
			paths = append(paths, path)
		}
	}
	sort.Strings(paths)
	return paths, nil
}

// mergeMCPConfig appends MCP package servers into the root tool config.
func mergeMCPConfig(cfg *schema.Tools, mcp schema.MCP) {
	if !mcp.Enabled && len(mcp.Servers) == 0 {
		return
	}
	cfg.MCP.Enabled = cfg.MCP.Enabled || mcp.Enabled || len(mcp.Servers) > 0
	cfg.MCP.Servers = append(cfg.MCP.Servers, mcp.Servers...)
}

// mcpConfigDirForToolPath resolves the sibling MCP package directory for a tool config.
func mcpConfigDirForToolPath(path string) string {
	clean := filepath.Clean(path)
	for dir := filepath.Dir(clean); dir != "." && dir != string(filepath.Separator); dir = filepath.Dir(dir) {
		if filepath.Base(dir) == schema.DefaultToolConfigDirName {
			return filepath.Join(filepath.Dir(dir), schema.DefaultMCPConfigDirName)
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
	}
	if clean == filepath.Clean(DefaultToolPath()) {
		return DefaultMCPConfigDir()
	}
	return ""
}

// isYAMLConfigPath reports whether a path is a YAML config file.
func isYAMLConfigPath(path string) bool {
	lower := strings.ToLower(path)
	return strings.HasSuffix(lower, ".yaml") || strings.HasSuffix(lower, ".yml")
}
