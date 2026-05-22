// This file coordinates top-level app startup: it loads config, constructs the
// runtime wiring, and dispatches to the requested runtime mode.
package app

import (
	"context"
	"fmt"
	"strings"
	"time"

	"agentawesome/internal/adkmemory"
	agentpkg "agentawesome/internal/agent"
	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
	"agentawesome/internal/contextapi"
	"agentawesome/internal/logging"
	"agentawesome/internal/model"
	"agentawesome/internal/runtime"
	commandservice "agentawesome/internal/services/command/command"
	commandembedded "agentawesome/internal/services/command/embedded"
	mcpembedded "agentawesome/internal/services/mcp/embedded"
	workflowembedded "agentawesome/internal/services/workflow/embedded"
	"agentawesome/internal/sessionstore"
	"agentawesome/internal/tools/toolsets"
)

// Options contains CLI-selected runtime and config overrides.
type Options struct {
	Args                   []string
	AgentConfigPath        string
	ModelConfigPath        string
	ToolPath               string
	ToolSet                bool
	ModelID                string
	ProviderName           string
	LogFilePath            string
	ContextAPIAddr         string
	ContextAPIToken        string
	SessionDatabase        string
	WorkflowAPIAddr        string
	WorkflowDefinitionsDir string
	WorkflowDatabasePath   string
	WorkflowContextBaseURL string
	CommandMCPAddr         string
	CommandDataDir         string
	CommandAllowedWorkdirs []string
	CommandAllowedEnv      []string
	CommandTemplatesJSON   string
	CommandParserDir       string
	CommandDefaultTimeout  time.Duration
	CommandMaxOutputBytes  int64
	MCPManagerAddr         string
	MCPServersJSON         string
	MCPRequestTimeout      time.Duration
}

// Run loads Agent Awesome configuration, builds the runtime config, and starts
// the selected ADK runtime mode.
func Run(ctx context.Context, opts Options) error {
	if err := logging.Configure(opts.LogFilePath); err != nil {
		return fmt.Errorf("configure logging: %w", err)
	}

	modelCfg, err := config.LoadModel(opts.ModelConfigPath)
	if err != nil {
		return err
	}
	agent, err := config.LoadAgent(opts.AgentConfigPath)
	if err != nil {
		return err
	}
	toolsCfg, err := config.LoadTools(opts.ToolPath, opts.ToolSet)
	if err != nil {
		return err
	}
	if _, err := contextapi.StartWithConfig(ctx, contextapi.Config{
		Addr:      opts.ContextAPIAddr,
		AuthToken: opts.ContextAPIToken,
	}, toolsCfg); err != nil {
		return err
	}
	commandServer, commandEndpoint, err := startEmbeddedCommand(ctx, opts, toolsCfg)
	if err != nil {
		return err
	} else if commandServer != nil {
		defer func() {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = commandServer.Close(shutdownCtx)
		}()
	}
	if mcpServer, err := startEmbeddedMCP(ctx, opts); err != nil {
		return err
	} else if mcpServer != nil {
		defer func() {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = mcpServer.Close(shutdownCtx)
		}()
	}
	if workflowServer, err := startEmbeddedWorkflow(ctx, opts); err != nil {
		return err
	} else if workflowServer != nil {
		defer func() {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = workflowServer.Close(shutdownCtx)
		}()
	}

	runtimeConfig, err := NewRuntimeConfig(ctx, modelCfg, agent, toolsWithEmbeddedCommandEndpoint(toolsCfg, commandEndpoint), opts)
	if err != nil {
		return err
	}

	return runtime.Execute(ctx, runtimeConfig, opts.Args)
}

// startEmbeddedCommand serves command MCP routes from the harness process when enabled.
func startEmbeddedCommand(ctx context.Context, opts Options, toolsCfg *schema.Tools) (*commandembedded.Server, string, error) {
	listenAddress := strings.TrimSpace(opts.CommandMCPAddr)
	if listenAddress == "" && localExecRuntimeEnabled(toolsCfg) {
		listenAddress = "127.0.0.1:0"
	}
	if listenAddress == "" {
		return nil, "", nil
	}
	templates, err := localExecCommandTemplates(toolsCfg)
	if err != nil {
		return nil, "", err
	}
	server, err := commandembedded.Start(ctx, commandembedded.Config{
		ListenAddress:     listenAddress,
		DataDir:           defaulted(opts.CommandDataDir, config.DefaultCommandDataDir()),
		AllowedWorkdirs:   commandAllowedWorkdirs(opts, toolsCfg),
		AllowedEnv:        defaultedStrings(opts.CommandAllowedEnv, defaultCommandAllowedEnv()),
		Templates:         templates,
		TemplatesJSON:     opts.CommandTemplatesJSON,
		ParserDir:         defaulted(opts.CommandParserDir, config.DefaultCommandParserDir()),
		DefaultTimeout:    defaultedDuration(opts.CommandDefaultTimeout, 10*time.Minute),
		DefaultMaxOutput:  defaultedInt64(opts.CommandMaxOutputBytes, 64<<10),
		ShutdownTimeout:   5 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
	})
	if err != nil {
		return nil, "", err
	}
	return server, "http://" + server.Address() + "/mcp", nil
}

// startEmbeddedMCP serves MCP manager routes from the harness process when enabled.
func startEmbeddedMCP(ctx context.Context, opts Options) (*mcpembedded.Server, error) {
	if strings.TrimSpace(opts.MCPManagerAddr) == "" {
		return nil, nil
	}
	return mcpembedded.Start(ctx, mcpembedded.Config{
		ListenAddress:     opts.MCPManagerAddr,
		ServersJSON:       opts.MCPServersJSON,
		RequestTimeout:    defaultedDuration(opts.MCPRequestTimeout, 10*time.Minute),
		ShutdownTimeout:   5 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
	})
}

// startEmbeddedWorkflow serves workflow routes from the harness process when enabled.
func startEmbeddedWorkflow(ctx context.Context, opts Options) (*workflowembedded.Server, error) {
	if strings.TrimSpace(opts.WorkflowAPIAddr) == "" {
		return nil, nil
	}
	contextBaseURL := strings.TrimSpace(opts.WorkflowContextBaseURL)
	if contextBaseURL == "" {
		contextBaseURL = contextBaseURLFromAddress(opts.ContextAPIAddr)
	}
	return workflowembedded.Start(ctx, workflowembedded.Config{
		ListenAddress:         opts.WorkflowAPIAddr,
		DefinitionsDir:        defaulted(opts.WorkflowDefinitionsDir, config.DefaultWorkflowDefinitionsDir()),
		DatabasePath:          defaulted(opts.WorkflowDatabasePath, config.DefaultWorkflowDatabasePath()),
		HarnessContextBaseURL: contextBaseURL,
		RequestTimeout:        10 * time.Minute,
	})
}

// contextBaseURLFromAddress builds the harness context API URL for workflow calls.
func contextBaseURLFromAddress(address string) string {
	if strings.TrimSpace(address) == "" {
		return "http://127.0.0.1:8081/api/context"
	}
	return "http://" + strings.TrimSpace(address) + "/api/context"
}

// defaulted returns fallback when value is blank.
func defaulted(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

// defaultedStrings returns fallback when values is empty.
func defaultedStrings(values []string, fallback []string) []string {
	if len(values) == 0 {
		return append([]string(nil), fallback...)
	}
	return append([]string(nil), values...)
}

// defaultedDuration returns fallback when value is not positive.
func defaultedDuration(value time.Duration, fallback time.Duration) time.Duration {
	if value <= 0 {
		return fallback
	}
	return value
}

// defaultedInt64 returns fallback when value is not positive.
func defaultedInt64(value int64, fallback int64) int64 {
	if value <= 0 {
		return fallback
	}
	return value
}

// defaultCommandAllowedEnv returns conservative process env passthrough names.
func defaultCommandAllowedEnv() []string {
	return []string{"PATH", "HOME", "USER", "TMPDIR"}
}

// localExecRuntimeEnabled reports whether legacy local-exec aliases should be
// served through the command MCP boundary.
func localExecRuntimeEnabled(toolsCfg *schema.Tools) bool {
	return toolsCfg != nil && toolsCfg.LocalExec.Enabled
}

// localExecCommandTemplates converts legacy aliases into command service templates.
func localExecCommandTemplates(toolsCfg *schema.Tools) ([]commandservice.Template, error) {
	if !localExecRuntimeEnabled(toolsCfg) {
		return nil, nil
	}
	localExec := toolsCfg.LocalExec
	templates := make([]commandservice.Template, 0, len(localExec.Commands))
	for _, item := range localExec.Commands {
		timeout, err := localExecCommandTimeout(localExec, item)
		if err != nil {
			return nil, err
		}
		templates = append(templates, commandservice.Template{
			ID:             strings.TrimSpace(item.Name),
			Description:    strings.TrimSpace(item.Description),
			Executable:     strings.TrimSpace(item.Executable),
			Args:           append([]string(nil), item.Args...),
			Timeout:        timeout,
			MaxOutputBytes: localExecCommandOutputLimit(localExec, item),
		})
	}
	return templates, nil
}

// localExecCommandTimeout returns the command-specific or local-exec default timeout.
func localExecCommandTimeout(localExec schema.LocalExec, command schema.LocalExecCommand) (time.Duration, error) {
	if strings.TrimSpace(command.Timeout) != "" {
		return time.ParseDuration(strings.TrimSpace(command.Timeout))
	}
	return localExec.DefaultTimeoutDuration(), nil
}

// localExecCommandOutputLimit returns the command-specific or local-exec default output limit.
func localExecCommandOutputLimit(localExec schema.LocalExec, command schema.LocalExecCommand) int64 {
	if command.MaxOutputBytes > 0 {
		return int64(command.MaxOutputBytes)
	}
	return int64(localExec.DefaultOutputLimit())
}

// commandAllowedWorkdirs merges command-service roots with legacy local-exec roots.
func commandAllowedWorkdirs(opts Options, toolsCfg *schema.Tools) []string {
	roots := defaultedStrings(opts.CommandAllowedWorkdirs, []string{"."})
	if localExecRuntimeEnabled(toolsCfg) {
		roots = append(roots, toolsCfg.LocalExec.AllowedWorkdirs...)
	}
	return uniqueNonEmptyStrings(roots)
}

// toolsWithEmbeddedCommandEndpoint adds the embedded command MCP endpoint to the runtime tool config.
func toolsWithEmbeddedCommandEndpoint(toolsCfg *schema.Tools, endpoint string) *schema.Tools {
	if strings.TrimSpace(endpoint) == "" {
		return toolsCfg
	}
	next := cloneToolsConfig(toolsCfg)
	if commandMCPServerConfigured(next, endpoint) {
		return next
	}
	next.MCP.Enabled = true
	next.MCP.Servers = append(next.MCP.Servers, schema.MCPServer{
		Name:                     "command",
		Transport:                "streamable-http",
		Endpoint:                 strings.TrimSpace(endpoint),
		RequireConfirmationTools: []string{"command_execute"},
		Tools: schema.MCPToolFilter{
			Allow: []string{
				"command_execute",
				"command_template_list",
				"command_status",
			},
		},
	})
	return next
}

// commandMCPServerConfigured reports whether command MCP is already model-visible.
func commandMCPServerConfigured(toolsCfg *schema.Tools, endpoint string) bool {
	if toolsCfg == nil {
		return false
	}
	endpoint = strings.TrimSpace(endpoint)
	for _, server := range toolsCfg.MCP.Servers {
		if strings.TrimSpace(server.Name) == "command" || strings.TrimSpace(server.Endpoint) == endpoint || strings.TrimSpace(server.URL) == endpoint {
			return true
		}
	}
	return false
}

// cloneToolsConfig clones the slices/maps touched by runtime tool augmentation.
func cloneToolsConfig(toolsCfg *schema.Tools) *schema.Tools {
	if toolsCfg == nil {
		return &schema.Tools{}
	}
	next := *toolsCfg
	next.MCP.Servers = append([]schema.MCPServer(nil), toolsCfg.MCP.Servers...)
	for i := range next.MCP.Servers {
		next.MCP.Servers[i].Args = append([]string(nil), toolsCfg.MCP.Servers[i].Args...)
		next.MCP.Servers[i].RequireConfirmationTools = append([]string(nil), toolsCfg.MCP.Servers[i].RequireConfirmationTools...)
		next.MCP.Servers[i].Tools.Allow = append([]string(nil), toolsCfg.MCP.Servers[i].Tools.Allow...)
		next.MCP.Servers[i].Env = cloneStringMap(toolsCfg.MCP.Servers[i].Env)
		next.MCP.Servers[i].Headers = cloneStringMap(toolsCfg.MCP.Servers[i].Headers)
		next.MCP.Servers[i].HeadersFromEnv = cloneStringMap(toolsCfg.MCP.Servers[i].HeadersFromEnv)
	}
	return &next
}

// cloneStringMap returns a shallow copy of a string map.
func cloneStringMap(values map[string]string) map[string]string {
	if values == nil {
		return nil
	}
	next := make(map[string]string, len(values))
	for key, value := range values {
		next[key] = value
	}
	return next
}

// uniqueNonEmptyStrings returns stable first-seen values after trimming.
func uniqueNonEmptyStrings(values []string) []string {
	seen := map[string]struct{}{}
	unique := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		unique = append(unique, trimmed)
	}
	return unique
}

// NewRuntimeConfig resolves the selected model/provider, converts the configured
// agent, attaches configured tools and toolsets, and returns the executable
// runtime config.
func NewRuntimeConfig(ctx context.Context, modelCfg *schema.ModelConfig, agentCfg schema.Agent, toolsCfg *schema.Tools, opts Options) (*runtime.Config, error) {
	modelFactory := model.NewFactory()
	if err := modelFactory.ValidateConfig(modelCfg); err != nil {
		return nil, err
	}

	selection, err := modelCfg.ResolveProvider(opts.ProviderName, opts.ModelID)
	if err != nil {
		return nil, err
	}

	llm, err := modelFactory.CreateRouter(ctx, modelCfg, selection)
	if err != nil {
		return nil, err
	}

	def, err := agentDefinitionFromConfig(agentCfg)
	if err != nil {
		return nil, err
	}

	tools, err := toolsets.Build(toolsCfg)
	if err != nil {
		return nil, err
	}
	memoryService, memoryEnabled, err := adkmemory.NewFromToolsConfig(toolsCfg)
	if err != nil {
		return nil, err
	}
	if memoryEnabled {
		tools.Tools = append(tools.Tools, adkmemory.RuntimeTools()...)
	}

	runtimeConfig, err := runtime.NewConfig(def, llm, tools)
	if err != nil {
		return nil, err
	}
	sessionService, err := sessionstore.Open(opts.SessionDatabase)
	if err != nil {
		return nil, err
	}
	runtimeConfig.SessionService = sessionService
	if memoryEnabled {
		plugin, err := adkmemory.NewSessionCapturePlugin()
		if err != nil {
			return nil, err
		}
		runtimeConfig.MemoryService = memoryService
		runtimeConfig.PluginConfig.Plugins = append(runtimeConfig.PluginConfig.Plugins, plugin)
	}
	return runtimeConfig, nil
}

// RuntimeSyntax returns the run command syntax owned by runtime packages.
func RuntimeSyntax() string {
	return runtime.Syntax()
}

// agentDefinitionFromConfig converts loaded agent schema into a validated
// runtime definition.
func agentDefinitionFromConfig(agent schema.Agent) (agentpkg.Definition, error) {
	return agentpkg.NewDefinition(agent.Name, agent.Description, agent.Instruction)
}
