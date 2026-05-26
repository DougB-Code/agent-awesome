// This file coordinates top-level app startup: it loads config, constructs the
// runtime wiring, and dispatches to the requested runtime mode.
package app

import (
	"context"
	"fmt"
	"regexp"
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
	"agentawesome/internal/services/capabilities"
	commandservice "agentawesome/internal/services/command/command"
	workflowactions "agentawesome/internal/services/workflow/actions"
	workflowembedded "agentawesome/internal/services/workflow/embedded"
	workflowruntime "agentawesome/internal/services/workflow/runtime"
	"agentawesome/internal/sessionstore"
	"agentawesome/internal/tools/commandtools"
	"agentawesome/internal/tools/toolsets"
	adksession "google.golang.org/adk/session"
	adktool "google.golang.org/adk/tool"
)

// Options contains CLI-selected runtime and config overrides.
type Options struct {
	Args                       []string
	AgentConfigPath            string
	ModelConfigPath            string
	ToolPath                   string
	ToolSet                    bool
	ModelID                    string
	ProviderName               string
	LogFilePath                string
	ContextAPIAddr             string
	ContextAPIToken            string
	SessionDatabase            string
	WorkflowAPIAddr            string
	WorkflowDefinitionsDir     string
	WorkflowDatabasePath       string
	OperationsDatabasePath     string
	RuntimeTargetsDatabasePath string
	CommandDataDir             string
	CommandAllowedWorkdirs     []string
	CommandAllowedEnv          []string
	CommandTemplatesJSON       string
	CommandParserDir           string
	CommandDefaultTimeout      time.Duration
	CommandMaxOutputBytes      int64
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
	contextServer, err := contextapi.StartWithConfig(ctx, contextapi.Config{
		Addr:      opts.ContextAPIAddr,
		AuthToken: opts.ContextAPIToken,
	}, toolsCfg)
	if err != nil {
		return err
	}
	commandService, err := openCommandService(opts, toolsCfg)
	if err != nil {
		return err
	} else if commandService != nil {
		defer commandService.Close()
	}
	capabilityRegistry := capabilities.NewRegistry(toolsCfg, agent)
	if workflowServer, err := startEmbeddedWorkflow(ctx, opts, toolsCfg, agent, capabilityRegistry, contextServer, commandService); err != nil {
		return err
	} else if workflowServer != nil {
		defer func() {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			_ = workflowServer.Close(shutdownCtx)
		}()
	}

	runtimeConfig, err := NewRuntimeConfig(ctx, modelCfg, agent, toolsCfg, opts, commandService)
	if err != nil {
		return err
	}

	return runtime.Execute(ctx, runtimeConfig, opts.Args)
}

// startEmbeddedWorkflow serves workflow routes from the harness process when enabled.
func startEmbeddedWorkflow(ctx context.Context, opts Options, toolsCfg *schema.Tools, agent schema.Agent, capabilityRegistry *capabilities.Registry, contextServer *contextapi.Server, commandService *commandservice.Service) (*workflowembedded.Server, error) {
	if strings.TrimSpace(opts.WorkflowAPIAddr) == "" {
		return nil, nil
	}
	if capabilityRegistry == nil {
		capabilityRegistry = capabilities.NewRegistry(toolsCfg, agent)
	}
	return workflowembedded.Start(ctx, workflowembedded.Config{
		ListenAddress:              opts.WorkflowAPIAddr,
		DefinitionsDir:             defaulted(opts.WorkflowDefinitionsDir, config.DefaultWorkflowDefinitionsDir()),
		DatabasePath:               defaulted(opts.WorkflowDatabasePath, config.DefaultWorkflowDatabasePath()),
		OperationsDatabasePath:     defaulted(opts.OperationsDatabasePath, config.DefaultOperationsDatabasePath()),
		RuntimeTargetsDatabasePath: defaulted(opts.RuntimeTargetsDatabasePath, config.DefaultRuntimeTargetsDatabasePath()),
		RequestTimeout:             10 * time.Minute,
		ToolClient:                 embeddedWorkflowToolClient(contextServer),
		CommandClient:              commandService,
		Capabilities:               capabilityRegistry,
		MCPServerEndpoints: workflowMCPServerEndpoints(
			toolsCfg,
		),
	})
}

// workflowMCPServerEndpoints indexes configured MCP endpoints for workflow actions.
func workflowMCPServerEndpoints(toolsCfg *schema.Tools) map[string]string {
	endpoints := map[string]string{}
	if toolsCfg == nil {
		return endpoints
	}
	for _, server := range toolsCfg.MCP.Servers {
		name := strings.TrimSpace(server.Name)
		endpoint := strings.TrimSpace(server.Endpoint)
		if endpoint == "" {
			endpoint = strings.TrimSpace(server.URL)
		}
		if name != "" && endpoint != "" {
			endpoints[name] = endpoint
		}
	}
	return endpoints
}

// embeddedWorkflowToolClient returns a direct tool client when workflow shares this process.
func embeddedWorkflowToolClient(contextServer *contextapi.Server) workflowruntime.ContextToolClient {
	if contextServer == nil {
		return nil
	}
	return workflowContextToolClient{contextServer: contextServer}
}

// workflowContextToolClient adapts the context API service to workflow tool.call actions.
type workflowContextToolClient struct {
	contextServer *contextapi.Server
}

// List returns harness context tool names without an HTTP loopback.
func (c workflowContextToolClient) List(ctx context.Context) ([]string, error) {
	return c.contextServer.List(ctx)
}

// Call invokes a harness context tool without an HTTP loopback.
func (c workflowContextToolClient) Call(ctx context.Context, req workflowactions.ToolRequest) (map[string]any, error) {
	result, err := c.contextServer.Call(ctx, req.Name, req.DomainID, req.Arguments)
	if err != nil {
		return nil, err
	}
	if resultMap, ok := result.(map[string]any); ok {
		return resultMap, nil
	}
	return map[string]any{"value": result}, nil
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

// commandRuntimeEnabled reports whether command templates should be model-visible
// through direct ADK tools.
func commandRuntimeEnabled(opts Options, toolsCfg *schema.Tools) bool {
	return localExecRuntimeEnabled(toolsCfg) || strings.TrimSpace(opts.CommandTemplatesJSON) != ""
}

// openCommandService creates the shared command service for ADK and workflow calls.
func openCommandService(opts Options, toolsCfg *schema.Tools) (*commandservice.Service, error) {
	if !commandRuntimeEnabled(opts, toolsCfg) {
		return nil, nil
	}
	cfg, err := commandServiceConfig(opts, toolsCfg)
	if err != nil {
		return nil, err
	}
	service, err := commandservice.Open(cfg)
	if err != nil {
		return nil, fmt.Errorf("open command service: %w", err)
	}
	return service, nil
}

// OpenCommandServiceForTools creates the command boundary for a tool package.
func OpenCommandServiceForTools(opts Options, toolsCfg *schema.Tools) (*commandservice.Service, error) {
	return openCommandService(opts, toolsCfg)
}

// commandServiceTools creates direct ADK tools for configured command templates.
func commandServiceTools(service *commandservice.Service) ([]adktool.Tool, error) {
	if service == nil {
		return nil, nil
	}
	tools, err := commandtools.New(service)
	if err != nil {
		return nil, err
	}
	return tools, nil
}

// commandServiceConfig translates harness options into command service config.
func commandServiceConfig(opts Options, toolsCfg *schema.Tools) (commandservice.Config, error) {
	templates, err := commandServiceTemplates(opts, toolsCfg)
	if err != nil {
		return commandservice.Config{}, err
	}
	return commandservice.Config{
		DataDir:          defaulted(opts.CommandDataDir, config.DefaultCommandDataDir()),
		AllowedWorkdirs:  commandAllowedWorkdirs(opts, toolsCfg),
		AllowedEnv:       defaultedStrings(opts.CommandAllowedEnv, defaultCommandAllowedEnv()),
		Templates:        templates,
		ParserDir:        defaulted(opts.CommandParserDir, config.DefaultCommandParserDir()),
		DefaultTimeout:   defaultedDuration(opts.CommandDefaultTimeout, 10*time.Minute),
		DefaultMaxOutput: defaultedInt64(opts.CommandMaxOutputBytes, 64<<10),
	}, nil
}

// commandServiceTemplates merges JSON command templates with local-exec commands.
func commandServiceTemplates(opts Options, toolsCfg *schema.Tools) ([]commandservice.Template, error) {
	templates, err := commandservice.ParseTemplatesJSON(opts.CommandTemplatesJSON)
	if err != nil {
		return nil, err
	}
	localTemplates, err := localExecCommandTemplates(toolsCfg)
	if err != nil {
		return nil, err
	}
	return append(templates, localTemplates...), nil
}

// localExecRuntimeEnabled reports whether local-exec commands should be exposed
// through the command service boundary.
func localExecRuntimeEnabled(toolsCfg *schema.Tools) bool {
	return toolsCfg != nil && toolsCfg.LocalExec.Enabled
}

// localExecCommandTemplates converts local-exec commands into service templates.
func localExecCommandTemplates(toolsCfg *schema.Tools) ([]commandservice.Template, error) {
	if !localExecRuntimeEnabled(toolsCfg) {
		return nil, nil
	}
	localExec := toolsCfg.LocalExec
	templates := make([]commandservice.Template, 0, len(localExec.Commands))
	for _, item := range localExec.Commands {
		if len(item.Operations) > 0 {
			operationTemplates, err := localExecOperationTemplates(localExec, item)
			if err != nil {
				return nil, err
			}
			templates = append(templates, operationTemplates...)
			continue
		}
		timeout, err := localExecCommandTimeout(localExec, item)
		if err != nil {
			return nil, err
		}
		templates = append(templates, commandservice.Template{
			ID:              strings.TrimSpace(item.Name),
			Description:     strings.TrimSpace(item.Description),
			Executable:      strings.TrimSpace(item.Executable),
			Args:            localExecCommandArgs(item),
			Env:             copyStringMap(item.Env),
			Timeout:         timeout,
			MaxOutputBytes:  localExecCommandOutputLimit(localExec, item),
			ParameterSchema: localExecCommandParameterSchema(item),
			Surface:         localExecCommandSurface(item.Surface),
		})
	}
	return templates, nil
}

// localExecOperationTemplates converts deterministic operations into templates.
func localExecOperationTemplates(localExec schema.LocalExec, item schema.LocalExecCommand) ([]commandservice.Template, error) {
	templates := make([]commandservice.Template, 0, len(item.Operations))
	for _, operation := range item.Operations {
		timeout, err := localExecOperationTimeout(localExec, item, operation)
		if err != nil {
			return nil, err
		}
		templates = append(templates, commandservice.Template{
			ID:                     localExecOperationTemplateID(item, operation),
			Description:            strings.TrimSpace(operation.Description),
			Executable:             strings.TrimSpace(item.Executable),
			Args:                   append([]string(nil), operation.Args...),
			WorkingDir:             strings.TrimSpace(operation.WorkingDir),
			Env:                    mergeStringMaps(item.Env, operation.Env),
			Timeout:                timeout,
			MaxOutputBytes:         localExecOperationOutputLimit(localExec, item, operation),
			ParameterSchema:        localExecOperationParameterSchema(operation),
			OutputContract:         localExecOperationOutputContract(operation.Output),
			ParserID:               strings.TrimSpace(operation.ParserID),
			OutputSource:           strings.TrimSpace(operation.OutputSource),
			ArtifactGlobs:          append([]string(nil), operation.ArtifactGlobs...),
			WorkingDirectoryPolicy: strings.TrimSpace(operation.WorkingDirPolicy),
			ValidationSchema:       cloneAnyMap(operation.OutputSchema),
			Surface:                localExecCommandSurface(item.Surface),
			Annotations:            cloneAnyMap(operation.Annotations),
		})
	}
	return templates, nil
}

// localExecOperationTemplateID returns the workflow-callable operation id.
func localExecOperationTemplateID(command schema.LocalExecCommand, operation schema.CommandOperation) string {
	return strings.TrimSpace(command.Name) + "." + strings.TrimSpace(operation.Name)
}

// localExecCommandArgs returns configured args or a generic CLI argument list.
func localExecCommandArgs(command schema.LocalExecCommand) []string {
	if len(command.Args) > 0 {
		return append([]string(nil), command.Args...)
	}
	if hasCommandSurface(command.Surface) {
		return []string{"{{args}}"}
	}
	return nil
}

// localExecOperationParameterSchema returns configured or inferred operation input.
func localExecOperationParameterSchema(operation schema.CommandOperation) map[string]any {
	if len(operation.InputSchema) > 0 {
		return cloneAnyMap(operation.InputSchema)
	}
	return inferTemplateParameterSchema(operation.Args)
}

// localExecCommandParameterSchema returns the workflow parameter contract.
func localExecCommandParameterSchema(command schema.LocalExecCommand) map[string]any {
	if len(command.Args) > 0 || !hasCommandSurface(command.Surface) {
		return nil
	}
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"args": map[string]any{"type": "array"},
		},
		"required": []any{"args"},
	}
}

// inferTemplateParameterSchema creates a string-object schema from placeholders.
func inferTemplateParameterSchema(values []string) map[string]any {
	names := templateParameterNames(values)
	if len(names) == 0 {
		return nil
	}
	properties := make(map[string]any, len(names))
	required := make([]any, 0, len(names))
	for _, name := range names {
		properties[name] = map[string]any{"type": "string"}
		required = append(required, name)
	}
	return map[string]any{
		"type":       "object",
		"properties": properties,
		"required":   required,
	}
}

// templateParameterNames extracts unique placeholders from argv template tokens.
func templateParameterNames(values []string) []string {
	seen := map[string]struct{}{}
	names := []string{}
	for _, value := range values {
		for _, match := range commandTemplateParameterPattern.FindAllStringSubmatch(value, -1) {
			if len(match) != 2 {
				continue
			}
			name := strings.TrimSpace(match[1])
			if name == "" {
				continue
			}
			if _, ok := seen[name]; ok {
				continue
			}
			seen[name] = struct{}{}
			names = append(names, name)
		}
	}
	return names
}

var commandTemplateParameterPattern = regexp.MustCompile(`\{\{\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}`)

// hasCommandSurface reports whether a CLI has model-facing surface metadata.
func hasCommandSurface(surface schema.CommandSurface) bool {
	return len(surface.GlobalFlags) > 0 || len(surface.Subcommands) > 0
}

// localExecCommandSurface converts schema CLI documentation into command metadata.
func localExecCommandSurface(surface schema.CommandSurface) commandservice.CommandSurface {
	globalFlags := make([]commandservice.CommandFlag, 0, len(surface.GlobalFlags))
	for _, flag := range surface.GlobalFlags {
		globalFlags = append(globalFlags, commandservice.CommandFlag{
			Name:        strings.TrimSpace(flag.Name),
			Description: strings.TrimSpace(flag.Description),
		})
	}
	subcommands := make([]commandservice.CommandSubcommand, 0, len(surface.Subcommands))
	for _, subcommand := range surface.Subcommands {
		subcommands = append(subcommands, localExecCommandSubcommand(subcommand))
	}
	return commandservice.CommandSurface{
		GlobalFlags: globalFlags,
		Subcommands: subcommands,
	}
}

// localExecCommandSubcommand converts one recursive CLI subcommand node.
func localExecCommandSubcommand(subcommand schema.CommandSubcommand) commandservice.CommandSubcommand {
	flags := make([]commandservice.CommandFlag, 0, len(subcommand.Flags))
	for _, flag := range subcommand.Flags {
		flags = append(flags, commandservice.CommandFlag{
			Name:        strings.TrimSpace(flag.Name),
			Description: strings.TrimSpace(flag.Description),
		})
	}
	subcommands := make([]commandservice.CommandSubcommand, 0, len(subcommand.Subcommands))
	for _, child := range subcommand.Subcommands {
		subcommands = append(subcommands, localExecCommandSubcommand(child))
	}
	return commandservice.CommandSubcommand{
		Name:        strings.TrimSpace(subcommand.Name),
		Description: strings.TrimSpace(subcommand.Description),
		Flags:       flags,
		Subcommands: subcommands,
	}
}

// copyStringMap returns a detached copy of string metadata.
func copyStringMap(values map[string]string) map[string]string {
	if len(values) == 0 {
		return nil
	}
	next := make(map[string]string, len(values))
	for key, value := range values {
		next[key] = value
	}
	return next
}

// mergeStringMaps returns command env with operation-specific values overriding.
func mergeStringMaps(base map[string]string, overrides map[string]string) map[string]string {
	if len(base) == 0 && len(overrides) == 0 {
		return nil
	}
	next := copyStringMap(base)
	if next == nil {
		next = map[string]string{}
	}
	for key, value := range overrides {
		next[key] = value
	}
	return next
}

// cloneAnyMap returns a detached copy of generic schema metadata.
func cloneAnyMap(values map[string]any) map[string]any {
	if len(values) == 0 {
		return nil
	}
	next := make(map[string]any, len(values))
	for key, value := range values {
		next[key] = value
	}
	return next
}

// localExecOperationOutputContract converts configured operation output parsing.
func localExecOperationOutputContract(output schema.CommandOutput) commandservice.OutputContract {
	return commandservice.OutputContract{
		Format: strings.TrimSpace(output.Format),
		Source: strings.TrimSpace(output.Source),
	}
}

// localExecCommandTimeout returns the command-specific or local-exec default timeout.
func localExecCommandTimeout(localExec schema.LocalExec, command schema.LocalExecCommand) (time.Duration, error) {
	if strings.TrimSpace(command.Timeout) != "" {
		return time.ParseDuration(strings.TrimSpace(command.Timeout))
	}
	return localExec.DefaultTimeoutDuration(), nil
}

// localExecOperationTimeout returns operation, command, or local-exec timeout.
func localExecOperationTimeout(localExec schema.LocalExec, command schema.LocalExecCommand, operation schema.CommandOperation) (time.Duration, error) {
	if strings.TrimSpace(operation.Timeout) != "" {
		return time.ParseDuration(strings.TrimSpace(operation.Timeout))
	}
	return localExecCommandTimeout(localExec, command)
}

// localExecCommandOutputLimit returns the command-specific or local-exec default output limit.
func localExecCommandOutputLimit(localExec schema.LocalExec, command schema.LocalExecCommand) int64 {
	if command.MaxOutputBytes > 0 {
		return int64(command.MaxOutputBytes)
	}
	return int64(localExec.DefaultOutputLimit())
}

// localExecOperationOutputLimit returns operation, command, or local-exec output limit.
func localExecOperationOutputLimit(localExec schema.LocalExec, command schema.LocalExecCommand, operation schema.CommandOperation) int64 {
	if operation.MaxOutputBytes > 0 {
		return int64(operation.MaxOutputBytes)
	}
	return localExecCommandOutputLimit(localExec, command)
}

// commandAllowedWorkdirs returns command-service roots from runtime options.
func commandAllowedWorkdirs(opts Options, toolsCfg *schema.Tools) []string {
	roots := defaultedStrings(opts.CommandAllowedWorkdirs, []string{"."})
	return uniqueNonEmptyStrings(roots)
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
func NewRuntimeConfig(ctx context.Context, modelCfg *schema.ModelConfig, agentCfg schema.Agent, toolsCfg *schema.Tools, opts Options, commandService *commandservice.Service) (*runtime.Config, error) {
	sessionService, err := sessionstore.Open(opts.SessionDatabase)
	if err != nil {
		return nil, err
	}
	return newRuntimeConfig(ctx, modelCfg, agentCfg, toolsCfg, opts, commandService, sessionService)
}

// newRuntimeConfig builds runtime wiring with a caller-owned session service.
func newRuntimeConfig(ctx context.Context, modelCfg *schema.ModelConfig, agentCfg schema.Agent, toolsCfg *schema.Tools, opts Options, commandService *commandservice.Service, sessionService adksession.Service) (*runtime.Config, error) {
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
	commandTools, err := commandServiceTools(commandService)
	if err != nil {
		return nil, fmt.Errorf("create command tools: %w", err)
	}
	tools.Tools = append(tools.Tools, commandTools...)
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
	if sessionService == nil {
		sessionService = adksession.InMemoryService()
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
