// This file selects memory MCP configuration and exposes runtime memory tools.
package adkmemory

import (
	"fmt"
	"strings"

	"agentawesome/internal/config/schema"
	"agentawesome/internal/tools/mcpclient"
	"google.golang.org/adk/tool"
	"google.golang.org/adk/tool/loadmemorytool"
	"google.golang.org/adk/tool/preloadmemorytool"
)

// NewFromToolsConfig creates a runtime memory service from configured domains.
func NewFromToolsConfig(cfg *schema.Tools) (*Service, bool, error) {
	runtime, ok := memoryRuntimeFromConfig(cfg)
	if !ok {
		return nil, false, nil
	}
	for _, domain := range runtime.domains {
		if err := mcpclient.ValidateServer(domain.server); err != nil {
			return nil, true, fmt.Errorf("create memory MCP transport for %s: %w", domain.id, err)
		}
	}
	return New(runtime), true, nil
}

// RuntimeTools returns runtime tools that search and preload configured memory.
func RuntimeTools() []tool.Tool {
	return []tool.Tool{
		preloadmemorytool.New(),
		loadmemorytool.New(),
	}
}

// memoryRuntimeConfig stores domain grants resolved from tool config.
type memoryRuntimeConfig struct {
	actor                string
	domains              []memoryDomain
	writeDomains         map[string]struct{}
	defaultWriteDomain   string
	allowedSensitivities []string
	allowedFlows         map[string]map[string]struct{}
}

// memoryDomain stores one memory endpoint.
type memoryDomain struct {
	id         string
	label      string
	server     schema.MCPServer
	searchTool string
}

// memoryRuntimeFromConfig resolves memory domains from target config.
func memoryRuntimeFromConfig(cfg *schema.Tools) (memoryRuntimeConfig, bool) {
	if cfg == nil || len(cfg.Memory.ReadDomains) == 0 {
		return memoryRuntimeConfig{}, false
	}
	runtime := memoryRuntimeConfig{
		actor:                strings.TrimSpace(cfg.Memory.Actor),
		writeDomains:         make(map[string]struct{}, len(cfg.Memory.WriteDomains)),
		defaultWriteDomain:   strings.TrimSpace(cfg.Memory.DefaultWriteDomain),
		allowedSensitivities: cfg.Memory.AllowedSensitivities,
		allowedFlows:         map[string]map[string]struct{}{},
	}
	for _, id := range cfg.Memory.WriteDomains {
		runtime.writeDomains[strings.TrimSpace(id)] = struct{}{}
	}
	for _, flow := range cfg.Memory.AllowedFlows {
		from := strings.TrimSpace(flow.From)
		to := strings.TrimSpace(flow.To)
		if runtime.allowedFlows[from] == nil {
			runtime.allowedFlows[from] = map[string]struct{}{}
		}
		runtime.allowedFlows[from][to] = struct{}{}
	}
	for _, domain := range cfg.Memory.ReadDomains {
		server := schema.MCPServer{
			Name:           memoryServerName(domain.ID),
			Transport:      "streamable-http",
			Endpoint:       strings.TrimSpace(domain.Endpoint),
			HeadersFromEnv: domain.HeadersFromEnv,
			Tools:          schema.MCPToolFilter{Allow: []string{saveMemoryToolName, searchMemoryToolName, searchSourcesToolName}},
		}
		runtime.domains = append(runtime.domains, memoryDomain{
			id:         strings.TrimSpace(domain.ID),
			label:      strings.TrimSpace(domain.Label),
			server:     server,
			searchTool: preferredSearchTool(server.Tools.Allow),
		})
	}
	return runtime, true
}

// memoryServerName returns a deterministic server name for a memory domain.
func memoryServerName(domainID string) string {
	normalized := strings.NewReplacer("-", "_").Replace(strings.TrimSpace(domainID))
	if normalized == "" {
		return "memory"
	}
	return "memory_" + normalized
}

// preferredSearchTool returns the richest configured memory search tool.
func preferredSearchTool(allowed []string) string {
	if len(allowed) == 0 {
		return searchSourcesToolName
	}
	for _, name := range allowed {
		if strings.TrimSpace(name) == searchSourcesToolName {
			return searchSourcesToolName
		}
	}
	for _, name := range allowed {
		if strings.TrimSpace(name) == searchMemoryToolName {
			return searchMemoryToolName
		}
	}
	return searchSourcesToolName
}
