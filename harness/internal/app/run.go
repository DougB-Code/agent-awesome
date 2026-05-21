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
	"agentawesome/internal/console"
	"agentawesome/internal/contextapi"
	"agentawesome/internal/logging"
	"agentawesome/internal/model"
	"agentawesome/internal/runtime"
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
	CommandApprovalTTL     time.Duration
	CommandRequireApproval bool
	CommandAllowArbitrary  bool
	CommandApprovalSet     bool
	CommandArbitrarySet    bool
	MCPManagerAddr         string
	MCPServersJSON         string
	MCPRequestTimeout      time.Duration
}

// Run loads Agent Awesome configuration, builds the runtime config, and starts
// either the built-in console or another runtime mode.
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
	if commandServer, err := startEmbeddedCommand(ctx, opts); err != nil {
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

	runtimeConfig, err := NewRuntimeConfig(ctx, modelCfg, agent, toolsCfg, opts)
	if err != nil {
		return err
	}

	if console.ShouldRun(opts.Args) {
		return console.Run(ctx, runtimeConfig, opts.Args)
	}

	return runtime.Execute(ctx, runtimeConfig, opts.Args)
}

// startEmbeddedCommand serves command MCP routes from the harness process when enabled.
func startEmbeddedCommand(ctx context.Context, opts Options) (*commandembedded.Server, error) {
	if strings.TrimSpace(opts.CommandMCPAddr) == "" {
		return nil, nil
	}
	return commandembedded.Start(ctx, commandembedded.Config{
		ListenAddress:     opts.CommandMCPAddr,
		DataDir:           defaulted(opts.CommandDataDir, config.DefaultCommandDataDir()),
		AllowedWorkdirs:   defaultedStrings(opts.CommandAllowedWorkdirs, []string{"."}),
		AllowedEnv:        defaultedStrings(opts.CommandAllowedEnv, defaultCommandAllowedEnv()),
		TemplatesJSON:     opts.CommandTemplatesJSON,
		ParserDir:         defaulted(opts.CommandParserDir, config.DefaultCommandParserDir()),
		DefaultTimeout:    defaultedDuration(opts.CommandDefaultTimeout, 10*time.Minute),
		DefaultMaxOutput:  defaultedInt64(opts.CommandMaxOutputBytes, 64<<10),
		ApprovalTTL:       defaultedDuration(opts.CommandApprovalTTL, 10*time.Minute),
		RequireApproval:   commandRequireApproval(opts),
		AllowArbitrary:    commandAllowArbitrary(opts),
		ShutdownTimeout:   5 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
	})
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

// commandRequireApproval returns the command approval policy with a secure default.
func commandRequireApproval(opts Options) bool {
	if !opts.CommandApprovalSet {
		return true
	}
	return opts.CommandRequireApproval
}

// commandAllowArbitrary returns the command proposal policy with daemon-compatible default.
func commandAllowArbitrary(opts Options) bool {
	if !opts.CommandArbitrarySet {
		return true
	}
	return opts.CommandAllowArbitrary
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
	if err := validateSelectedModelCapabilities(opts.Args, selection); err != nil {
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
	return fmt.Sprintf("Agent Awesome console:\n%s\nAssistant runtime modes:\n%s", console.Syntax(), runtime.Syntax())
}

// validateSelectedModelCapabilities rejects runtime requests that the selected
// model did not declare support for.
func validateSelectedModelCapabilities(args []string, selection schema.ProviderSelection) error {
	requested, err := console.RequestedModelCapabilities(args)
	if err != nil {
		return err
	}
	return model.ValidateRequestedCapabilities(requested, selection)
}

// agentDefinitionFromConfig converts loaded agent schema into a validated
// runtime definition.
func agentDefinitionFromConfig(agent schema.Agent) (agentpkg.Definition, error) {
	return agentpkg.NewDefinition(agent.Name, agent.Description, agent.Instruction)
}
