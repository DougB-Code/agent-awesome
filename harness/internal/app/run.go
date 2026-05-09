// This file coordinates top-level app startup: it loads config, constructs the
// runtime wiring, and dispatches to the requested runtime mode.
package app

import (
	"context"
	"fmt"
	"strings"

	"agentawesome/internal/adkmemory"
	agentpkg "agentawesome/internal/agent"
	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
	"agentawesome/internal/console"
	"agentawesome/internal/contextapi"
	"agentawesome/internal/logging"
	"agentawesome/internal/model"
	"agentawesome/internal/runtime"
	"agentawesome/internal/sessionstore"
	"agentawesome/internal/tools/toolsets"
	"google.golang.org/adk/cmd/launcher"
)

// Options contains CLI-selected runtime and config overrides.
type Options struct {
	Args            []string
	AgentConfigPath string
	ModelConfigPath string
	ToolPath        string
	ToolSet         bool
	ModelID         string
	ProviderName    string
	LogFilePath     string
	ContextAPIAddr  string
	ContextAPIToken string
	SessionDatabase string
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

	// @TODO why is this the only runtime config in this package. Model, agent, tools are loaded from config
	runtimeConfig, err := NewRuntimeConfig(ctx, modelCfg, agent, toolsCfg, opts)
	if err != nil {
		return err
	}

	if console.ShouldRun(opts.Args) {
		return console.Run(ctx, runtimeConfig, opts.Args)
	}

	return runtime.Execute(ctx, runtimeConfig, opts.Args)
}

// @TODO is this breading SRP
// NewRuntimeConfig resolves the selected model/provider, converts the configured
// agent, attaches configured tools and toolsets, and returns the executable
// runtime config.
func NewRuntimeConfig(ctx context.Context, modelCfg *schema.ModelConfig, agentCfg schema.Agent, toolsCfg *schema.Tools, opts Options) (*launcher.Config, error) {
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

	llm, err := modelFactory.Create(ctx, selection)
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

// @TODO is more of a CLI concern and better suited for the cmd folder
// RuntimeSyntax returns the runtime argument syntax shown in CLI help.
func RuntimeSyntax() string {
	var b strings.Builder
	fmt.Fprintf(&b, "Agent Awesome console:\n%s\n", console.Syntax())
	fmt.Fprintf(&b, "Delegated ADK runtime modes:\n%s", runtime.Syntax())
	return b.String()
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
