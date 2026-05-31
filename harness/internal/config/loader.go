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
	return loadToolsWithVisited(path, explicit, mergeMCPPackages, map[string]struct{}{})
}

// loadToolsWithVisited decodes inherited tool packages and rejects cycles.
func loadToolsWithVisited(path string, explicit bool, mergeMCPPackages bool, visited map[string]struct{}) (*schema.Tools, error) {
	if strings.TrimSpace(path) == "" {
		path = DefaultToolPath()
	}
	identity, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	if _, ok := visited[identity]; ok {
		return nil, fmt.Errorf("tool config inheritance cycle at %s", path)
	}
	visited[identity] = struct{}{}
	defer delete(visited, identity)

	var cfg schema.Tools
	if err := loadYAML(path, &cfg); err != nil {
		if !explicit && path == DefaultToolPath() && isNotExist(err) {
			cfg = schema.Tools{}
		} else {
			return nil, fmt.Errorf("decode %s: %w", path, err)
		}
	}
	if strings.TrimSpace(cfg.Extends) != "" {
		basePath := toolExtendsPath(path, cfg.Extends)
		base, err := loadToolsWithVisited(basePath, true, false, visited)
		if err != nil {
			return nil, fmt.Errorf("load inherited tool config %s: %w", basePath, err)
		}
		cfg = mergeInheritedTools(*base, cfg)
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

// toolExtendsPath resolves an inherited package path relative to the child.
func toolExtendsPath(childPath string, extends string) string {
	trimmed := strings.TrimSpace(extends)
	if filepath.IsAbs(trimmed) {
		return trimmed
	}
	return filepath.Clean(filepath.Join(filepath.Dir(childPath), trimmed))
}

// mergeInheritedTools overlays a package delta on an inherited tool package.
func mergeInheritedTools(base schema.Tools, delta schema.Tools) schema.Tools {
	merged := base
	if strings.TrimSpace(delta.Name) != "" {
		merged.Name = delta.Name
	}
	merged.Version = delta.Version
	merged.Extends = delta.Extends
	merged.LocalExec = mergeLocalExec(base.LocalExec, delta.LocalExec)
	merged.MCP = mergeMCP(base.MCP, delta.MCP)
	merged.Memory = mergeMemory(base.Memory, delta.Memory)
	merged.NodePresets = mergeNodePresets(base.NodePresets, delta.NodePresets)
	merged.Validations = mergeToolValidations(base.Validations, delta.Validations)
	return merged
}

// mergeLocalExec overlays command operation deltas by command name.
func mergeLocalExec(base schema.LocalExec, delta schema.LocalExec) schema.LocalExec {
	merged := base
	if delta.Enabled {
		merged.Enabled = true
	}
	if strings.TrimSpace(delta.DefaultTimeout) != "" {
		merged.DefaultTimeout = delta.DefaultTimeout
	}
	if delta.DefaultMaxOutputBytes > 0 {
		merged.DefaultMaxOutputBytes = delta.DefaultMaxOutputBytes
	}
	merged.Commands = mergeByStringKey(base.Commands, delta.Commands, func(command schema.LocalExecCommand) string {
		return strings.TrimSpace(command.Name)
	})
	return merged
}

// mergeMCP overlays MCP server deltas by server name.
func mergeMCP(base schema.MCP, delta schema.MCP) schema.MCP {
	merged := base
	if delta.Enabled {
		merged.Enabled = true
	}
	merged.Servers = mergeByStringKey(base.Servers, delta.Servers, func(server schema.MCPServer) string {
		return strings.TrimSpace(server.Name)
	})
	return merged
}

// mergeMemory overlays memory-domain grants while preserving inherited grants.
func mergeMemory(base schema.Memory, delta schema.Memory) schema.Memory {
	merged := base
	if strings.TrimSpace(delta.Actor) != "" {
		merged.Actor = delta.Actor
	}
	merged.ReadDomains = mergeByStringKey(base.ReadDomains, delta.ReadDomains, func(domain schema.MemoryDomain) string {
		return strings.TrimSpace(domain.ID)
	})
	merged.WriteDomains = appendUniqueStrings(base.WriteDomains, delta.WriteDomains)
	if strings.TrimSpace(delta.DefaultWriteDomain) != "" {
		merged.DefaultWriteDomain = delta.DefaultWriteDomain
	}
	merged.AllowedSensitivities = appendUniqueStrings(base.AllowedSensitivities, delta.AllowedSensitivities)
	merged.AllowedFlows = mergeMemoryFlows(base.AllowedFlows, delta.AllowedFlows)
	return merged
}

// mergeNodePresets overlays reusable runbook node presets by preset id.
func mergeNodePresets(base []schema.NodePreset, delta []schema.NodePreset) []schema.NodePreset {
	return mergeByStringKey(base, delta, func(preset schema.NodePreset) string {
		return strings.TrimSpace(preset.ID)
	})
}

// mergeToolValidations overlays portable validation cases by validation id.
func mergeToolValidations(base []schema.ToolValidation, delta []schema.ToolValidation) []schema.ToolValidation {
	return mergeByStringKey(base, delta, func(validation schema.ToolValidation) string {
		return strings.TrimSpace(validation.ID)
	})
}

// mergeMemoryFlows appends new domain flow grants by source and destination.
func mergeMemoryFlows(base []schema.MemoryFlow, delta []schema.MemoryFlow) []schema.MemoryFlow {
	merged := append([]schema.MemoryFlow{}, base...)
	seen := map[string]struct{}{}
	for _, flow := range merged {
		seen[memoryFlowKey(flow)] = struct{}{}
	}
	for _, flow := range delta {
		key := memoryFlowKey(flow)
		if strings.TrimSpace(key) == "" {
			merged = append(merged, flow)
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		merged = append(merged, flow)
	}
	return merged
}

// memoryFlowKey returns a stable identity for one memory information-flow grant.
func memoryFlowKey(flow schema.MemoryFlow) string {
	from := strings.TrimSpace(flow.From)
	to := strings.TrimSpace(flow.To)
	if from == "" || to == "" {
		return ""
	}
	return from + "->" + to
}

// appendUniqueStrings appends non-empty strings while keeping inherited order.
func appendUniqueStrings(base []string, delta []string) []string {
	merged := append([]string{}, base...)
	seen := map[string]struct{}{}
	for _, value := range merged {
		seen[strings.TrimSpace(value)] = struct{}{}
	}
	for _, value := range delta {
		key := strings.TrimSpace(value)
		if key == "" {
			merged = append(merged, value)
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		merged = append(merged, value)
	}
	return merged
}

// mergeByStringKey appends keyed deltas and replaces inherited items with the same key.
func mergeByStringKey[T any](base []T, delta []T, key func(T) string) []T {
	merged := append([]T{}, base...)
	indexByKey := make(map[string]int, len(merged))
	for index, item := range merged {
		itemKey := key(item)
		if itemKey == "" {
			continue
		}
		indexByKey[itemKey] = index
	}
	for _, item := range delta {
		itemKey := key(item)
		if itemKey == "" {
			merged = append(merged, item)
			continue
		}
		if index, ok := indexByKey[itemKey]; ok {
			merged[index] = item
			continue
		}
		indexByKey[itemKey] = len(merged)
		merged = append(merged, item)
	}
	return merged
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
// destroying runbook-style references that intentionally remain unresolved.
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

// mcpConfigDirForToolPath resolves the MCP package directory paired with a tool config.
func mcpConfigDirForToolPath(path string) string {
	clean := filepath.Clean(path)
	if clean == filepath.Clean(DefaultToolPath()) {
		return DefaultMCPConfigDir()
	}
	for dir := filepath.Dir(clean); dir != "." && dir != string(filepath.Separator); dir = filepath.Dir(dir) {
		parent := filepath.Dir(dir)
		if filepath.Base(parent) == schema.DefaultToolConfigDirName {
			return filepath.Join(
				filepath.Dir(parent),
				schema.DefaultMCPConfigDirName,
				filepath.Base(dir),
			)
		}
		if filepath.Base(dir) == schema.DefaultToolConfigDirName {
			return filepath.Join(filepath.Dir(dir), schema.DefaultMCPConfigDirName)
		}
		if parent == dir {
			break
		}
	}
	return ""
}

// isYAMLConfigPath reports whether a path is a YAML config file.
func isYAMLConfigPath(path string) bool {
	lower := strings.ToLower(path)
	return strings.HasSuffix(lower, ".yaml") || strings.HasSuffix(lower, ".yml")
}
