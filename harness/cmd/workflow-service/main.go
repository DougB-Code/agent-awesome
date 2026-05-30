package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"agentawesome/internal/app"
	"agentawesome/internal/config"
	"agentawesome/internal/config/schema"
	"agentawesome/internal/logging"
	"agentawesome/internal/services/capabilities"
	workflowembedded "agentawesome/internal/services/workflow/embedded"
)

const defaultShutdownTimeout = 5 * time.Second

// options stores standalone workflow service configuration.
type options struct {
	ListenAddress              string
	DefinitionsDir             string
	DatabasePath               string
	OperationsDatabasePath     string
	RuntimeTargetsDatabasePath string
	HarnessContextBaseURL      string
	AgentConfigPath            string
	ToolConfigPath             string
	LogFilePath                string
	CommandDataDir             string
	CommandAllowedWorkdirs     stringList
	CommandAllowedEnv          stringList
	CommandTemplatesJSON       string
	CommandParserDir           string
	CommandDefaultTimeout      time.Duration
	CommandMaxOutputBytes      int64
	RequestTimeout             time.Duration
	ShutdownTimeout            time.Duration
	AgentConfigExplicit        bool
	ToolConfigExplicit         bool
}

// stringList stores repeatable string flags.
type stringList []string

// String returns a comma-separated flag display value.
func (s *stringList) String() string {
	if s == nil {
		return ""
	}
	return strings.Join(*s, ",")
}

// Set appends one repeatable flag value.
func (s *stringList) Set(value string) error {
	if trimmed := strings.TrimSpace(value); trimmed != "" {
		*s = append(*s, trimmed)
	}
	return nil
}

// main starts the workflow service with signal-aware shutdown.
func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Args[1:]); err != nil && !errors.Is(err, context.Canceled) {
		log.Fatal(err)
	}
}

// run parses options, opens dependencies, and serves workflow APIs.
func run(ctx context.Context, args []string) error {
	opts, err := parseOptions(args)
	if err != nil {
		return err
	}
	if err := logging.Configure(opts.LogFilePath); err != nil {
		return fmt.Errorf("configure logging: %w", err)
	}
	agentCfg, err := loadAgent(opts.AgentConfigPath, opts.AgentConfigExplicit)
	if err != nil {
		return err
	}
	toolsCfg, err := config.LoadTools(opts.ToolConfigPath, opts.ToolConfigExplicit)
	if err != nil {
		return err
	}
	commandService, err := app.OpenCommandServiceForTools(commandOptions(opts), toolsCfg)
	if err != nil {
		return err
	}
	if commandService != nil {
		defer commandService.Close()
	}
	server, err := workflowembedded.Start(ctx, workflowembedded.Config{
		ListenAddress:              defaulted(opts.ListenAddress, "127.0.0.1:8092"),
		DefinitionsDir:             defaulted(opts.DefinitionsDir, config.DefaultWorkflowDefinitionsDir()),
		DatabasePath:               defaulted(opts.DatabasePath, config.DefaultWorkflowDatabasePath()),
		OperationsDatabasePath:     defaulted(opts.OperationsDatabasePath, config.DefaultOperationsDatabasePath()),
		RuntimeTargetsDatabasePath: defaulted(opts.RuntimeTargetsDatabasePath, config.DefaultRuntimeTargetsDatabasePath()),
		HarnessContextBaseURL:      opts.HarnessContextBaseURL,
		RequestTimeout:             opts.RequestTimeout,
		CommandClient:              commandService,
		MCPServerEndpoints:         workflowMCPServerEndpoints(toolsCfg),
		Capabilities:               capabilities.NewRegistry(toolsCfg, agentCfg),
		ShutdownTimeout:            opts.ShutdownTimeout,
	})
	if err != nil {
		return err
	}
	log.Printf("workflow service listening on %s", defaulted(opts.ListenAddress, "127.0.0.1:8092"))
	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), defaultedDuration(opts.ShutdownTimeout, defaultShutdownTimeout))
	defer cancel()
	return server.Close(shutdownCtx)
}

// parseOptions turns CLI flags into workflow service options.
func parseOptions(args []string) (options, error) {
	opts := defaultOptions(args)
	fs := flag.NewFlagSet("workflow-service", flag.ContinueOnError)
	fs.StringVar(&opts.ListenAddress, "addr", opts.ListenAddress, "workflow API listen address")
	fs.StringVar(&opts.DefinitionsDir, "definitions", opts.DefinitionsDir, "workflow definition directory")
	fs.StringVar(&opts.DatabasePath, "db", opts.DatabasePath, "workflow SQLite database path")
	fs.StringVar(&opts.OperationsDatabasePath, "operations-db", opts.OperationsDatabasePath, "operations SQLite database path")
	fs.StringVar(&opts.RuntimeTargetsDatabasePath, "runtime-targets-db", opts.RuntimeTargetsDatabasePath, "runtime target SQLite database path")
	fs.StringVar(&opts.HarnessContextBaseURL, "harness-context-base-url", opts.HarnessContextBaseURL, "optional harness context API base URL for tool.call")
	fs.StringVar(&opts.AgentConfigPath, "agent", opts.AgentConfigPath, "optional agent config path used for capability metadata")
	fs.StringVar(&opts.ToolConfigPath, "tool", opts.ToolConfigPath, "tool config path used for command and MCP workflow actions")
	fs.StringVar(&opts.LogFilePath, "log-file", opts.LogFilePath, "optional workflow service log file path")
	fs.StringVar(&opts.CommandDataDir, "command-data-dir", opts.CommandDataDir, "command service data directory")
	fs.Var(&opts.CommandAllowedWorkdirs, "command-allow-workdir", "allowed command working directory root")
	fs.Var(&opts.CommandAllowedEnv, "command-allow-env", "allowed process environment variable")
	fs.StringVar(&opts.CommandTemplatesJSON, "command-templates-json", opts.CommandTemplatesJSON, "JSON command template list")
	fs.StringVar(&opts.CommandParserDir, "command-parser-dir", opts.CommandParserDir, "Starlark command parser directory")
	fs.DurationVar(&opts.CommandDefaultTimeout, "command-timeout", opts.CommandDefaultTimeout, "default command timeout")
	fs.Int64Var(&opts.CommandMaxOutputBytes, "command-max-output-bytes", opts.CommandMaxOutputBytes, "default command output tail byte limit")
	fs.DurationVar(&opts.RequestTimeout, "request-timeout", opts.RequestTimeout, "maximum workflow action request duration")
	fs.DurationVar(&opts.ShutdownTimeout, "shutdown-timeout", opts.ShutdownTimeout, "maximum graceful shutdown duration")
	if err := fs.Parse(args); err != nil {
		return options{}, err
	}
	return opts, nil
}

// defaultOptions builds environment-aware workflow service defaults.
func defaultOptions(args []string) options {
	commandAllowedWorkdirs := envStringList("AGENTAWESOME_COMMAND_ALLOWED_WORKDIRS", []string{"."})
	if flagProvided(args, "command-allow-workdir") {
		commandAllowedWorkdirs = stringList{}
	}
	commandAllowedEnv := envStringList("AGENTAWESOME_COMMAND_ALLOWED_ENV", []string{"PATH", "HOME", "USER", "TMPDIR"})
	if flagProvided(args, "command-allow-env") {
		commandAllowedEnv = stringList{}
	}
	return options{
		ListenAddress:              envString("AGENTAWESOME_WORKFLOW_ADDR", "127.0.0.1:8092"),
		DefinitionsDir:             envString("AGENTAWESOME_WORKFLOW_DEFINITIONS_DIR", config.DefaultWorkflowDefinitionsDir()),
		DatabasePath:               envString("AGENTAWESOME_WORKFLOW_DB", config.DefaultWorkflowDatabasePath()),
		OperationsDatabasePath:     envString("AGENTAWESOME_OPERATIONS_DB", config.DefaultOperationsDatabasePath()),
		RuntimeTargetsDatabasePath: envString("AGENTAWESOME_RUNTIME_TARGETS_DB", config.DefaultRuntimeTargetsDatabasePath()),
		HarnessContextBaseURL:      envString("AGENTAWESOME_CONTEXT_API_BASE_URL", ""),
		AgentConfigPath:            envString("AGENTAWESOME_AGENT_CONFIG", ""),
		ToolConfigPath:             envString("AGENTAWESOME_TOOL_CONFIG", config.DefaultToolPath()),
		LogFilePath:                envString("AGENTAWESOME_WORKFLOW_LOG_FILE", ""),
		CommandDataDir:             envString("AGENTAWESOME_COMMAND_DATA_DIR", config.DefaultCommandDataDir()),
		CommandAllowedWorkdirs:     commandAllowedWorkdirs,
		CommandAllowedEnv:          commandAllowedEnv,
		CommandTemplatesJSON:       envString("AGENTAWESOME_COMMAND_TEMPLATES_JSON", ""),
		CommandParserDir:           envString("AGENTAWESOME_COMMAND_PARSER_DIR", config.DefaultCommandParserDir()),
		CommandDefaultTimeout:      envDuration("AGENTAWESOME_COMMAND_TIMEOUT", 10*time.Minute),
		CommandMaxOutputBytes:      envInt64("AGENTAWESOME_COMMAND_MAX_OUTPUT_BYTES", 64<<10),
		RequestTimeout:             envDuration("AGENTAWESOME_WORKFLOW_REQUEST_TIMEOUT", 10*time.Minute),
		ShutdownTimeout:            defaultShutdownTimeout,
		AgentConfigExplicit:        flagProvided(args, "agent") || strings.TrimSpace(os.Getenv("AGENTAWESOME_AGENT_CONFIG")) != "",
		ToolConfigExplicit:         flagProvided(args, "tool") || strings.TrimSpace(os.Getenv("AGENTAWESOME_TOOL_CONFIG")) != "",
	}
}

// commandOptions maps workflow flags onto the shared command service options.
func commandOptions(opts options) app.Options {
	return app.Options{
		ToolPath:               opts.ToolConfigPath,
		ToolSet:                opts.ToolConfigExplicit,
		CommandDataDir:         opts.CommandDataDir,
		CommandAllowedWorkdirs: []string(opts.CommandAllowedWorkdirs),
		CommandAllowedEnv:      []string(opts.CommandAllowedEnv),
		CommandTemplatesJSON:   opts.CommandTemplatesJSON,
		CommandParserDir:       opts.CommandParserDir,
		CommandDefaultTimeout:  opts.CommandDefaultTimeout,
		CommandMaxOutputBytes:  opts.CommandMaxOutputBytes,
	}
}

// loadAgent reads optional agent metadata without requiring an agent to run workflows.
func loadAgent(path string, explicit bool) (schema.Agent, error) {
	if !explicit && strings.TrimSpace(path) == "" {
		return schema.Agent{}, nil
	}
	agentCfg, err := config.LoadAgent(path)
	if err == nil {
		return agentCfg, nil
	}
	if !explicit && errors.Is(err, os.ErrNotExist) {
		return schema.Agent{}, nil
	}
	return schema.Agent{}, err
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

// flagProvided reports whether one long flag appeared in the process arguments.
func flagProvided(args []string, name string) bool {
	prefix := "--" + name
	for _, arg := range args {
		if arg == prefix || strings.HasPrefix(arg, prefix+"=") {
			return true
		}
	}
	return false
}

// envString returns a string environment value or fallback.
func envString(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// envStringList returns a comma-separated string list environment value.
func envStringList(name string, fallback []string) stringList {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return append(stringList{}, fallback...)
	}
	parts := strings.Split(value, ",")
	items := stringList{}
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			items = append(items, trimmed)
		}
	}
	return items
}

// envDuration returns a duration environment value or fallback.
func envDuration(name string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}

// envInt64 returns an integer environment value or fallback.
func envInt64(name string, fallback int64) int64 {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return fallback
	}
	return parsed
}

// defaulted returns fallback when value is blank.
func defaulted(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

// defaultedDuration returns fallback when value is not positive.
func defaultedDuration(value time.Duration, fallback time.Duration) time.Duration {
	if value <= 0 {
		return fallback
	}
	return value
}
