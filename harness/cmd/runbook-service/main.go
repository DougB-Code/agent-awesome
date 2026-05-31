package main

import (
	"context"
	"encoding/json"
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
	"agentawesome/internal/services/launchpad/queueworker"
	runbookembedded "agentawesome/internal/services/runbook/embedded"
	runbookruntime "agentawesome/internal/services/runbook/runtime"
)

const defaultShutdownTimeout = 5 * time.Second

// options stores standalone runbook service configuration.
type options struct {
	ListenAddress              string
	DefinitionsDir             string
	DatabasePath               string
	LaunchpadDatabasePath      string
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
	GatewayBaseURL             string
	GatewayToken               string
	Profile                    string
	TargetID                   string
	LeaseSeconds               int
	PollInterval               time.Duration
	RunTimeout                 time.Duration
	EnqueueDue                 bool
	RecoverExpired             bool
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

// main starts the runbook service with signal-aware shutdown.
func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Args[1:]); err != nil && !errors.Is(err, context.Canceled) {
		log.Fatal(err)
	}
}

// run parses options, opens dependencies, and serves runbook APIs.
func run(ctx context.Context, args []string) error {
	if len(args) > 0 && args[0] == "queue-worker" {
		return runQueueWorker(ctx, args[1:])
	}
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
	var commandClient runbookruntime.CommandClient
	if commandService != nil {
		commandClient = commandService
	}
	server, err := runbookembedded.Start(ctx, runbookembedded.Config{
		ListenAddress:              defaulted(opts.ListenAddress, "127.0.0.1:8092"),
		DefinitionsDir:             defaulted(opts.DefinitionsDir, config.DefaultRunbookDefinitionsDir()),
		DatabasePath:               defaulted(opts.DatabasePath, config.DefaultRunbookDatabasePath()),
		LaunchpadDatabasePath:      defaulted(opts.LaunchpadDatabasePath, config.DefaultLaunchpadDatabasePath()),
		RuntimeTargetsDatabasePath: defaulted(opts.RuntimeTargetsDatabasePath, config.DefaultRuntimeTargetsDatabasePath()),
		HarnessContextBaseURL:      opts.HarnessContextBaseURL,
		RequestTimeout:             opts.RequestTimeout,
		CommandClient:              commandClient,
		MCPServerEndpoints:         runbookMCPServerEndpoints(toolsCfg),
		Capabilities:               capabilities.NewRegistry(toolsCfg, agentCfg),
		ShutdownTimeout:            opts.ShutdownTimeout,
	})
	if err != nil {
		return err
	}
	log.Printf("runbook service listening on %s", defaulted(opts.ListenAddress, "127.0.0.1:8092"))
	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), defaultedDuration(opts.ShutdownTimeout, defaultShutdownTimeout))
	defer cancel()
	return server.Close(shutdownCtx)
}

// runQueueWorker runs one cron-friendly Launchpad queue worker tick.
func runQueueWorker(ctx context.Context, args []string) error {
	opts := defaultOptions(args)
	fs := flag.NewFlagSet("runbook-service queue-worker", flag.ContinueOnError)
	fs.StringVar(&opts.GatewayBaseURL, "gateway-base-url", opts.GatewayBaseURL, "gateway API base URL")
	fs.StringVar(&opts.GatewayToken, "gateway-token", opts.GatewayToken, "gateway bearer token")
	fs.StringVar(&opts.Profile, "profile", opts.Profile, "optional gateway runtime profile")
	fs.StringVar(&opts.TargetID, "target-id", opts.TargetID, "runtime target id this worker may lease")
	fs.IntVar(&opts.LeaseSeconds, "lease-seconds", opts.LeaseSeconds, "queue lease duration in seconds")
	fs.DurationVar(&opts.PollInterval, "poll-interval", opts.PollInterval, "run status polling interval")
	fs.DurationVar(&opts.RunTimeout, "run-timeout", opts.RunTimeout, "maximum time to wait for a started run")
	fs.BoolVar(&opts.EnqueueDue, "enqueue-due", opts.EnqueueDue, "enqueue due Launchpad schedules before leasing work")
	fs.BoolVar(&opts.RecoverExpired, "recover-expired", opts.RecoverExpired, "recover expired queue leases before leasing work")
	if err := fs.Parse(args); err != nil {
		return err
	}
	result, err := queueworker.RunOnce(ctx, queueworker.Config{
		BaseURL:        opts.GatewayBaseURL,
		AuthToken:      opts.GatewayToken,
		Profile:        opts.Profile,
		TargetID:       opts.TargetID,
		LeaseSeconds:   opts.LeaseSeconds,
		PollInterval:   opts.PollInterval,
		RunTimeout:     opts.RunTimeout,
		EnqueueDue:     opts.EnqueueDue,
		RecoverExpired: opts.RecoverExpired,
	})
	if err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(encoded))
	return nil
}

// parseOptions turns CLI flags into runbook service options.
func parseOptions(args []string) (options, error) {
	opts := defaultOptions(args)
	fs := flag.NewFlagSet("runbook-service", flag.ContinueOnError)
	fs.StringVar(&opts.ListenAddress, "addr", opts.ListenAddress, "runbook API listen address")
	fs.StringVar(&opts.DefinitionsDir, "definitions", opts.DefinitionsDir, "runbook definition directory")
	fs.StringVar(&opts.DatabasePath, "db", opts.DatabasePath, "runbook SQLite database path")
	fs.StringVar(&opts.LaunchpadDatabasePath, "launchpad-db", opts.LaunchpadDatabasePath, "launchpad SQLite database path")
	fs.StringVar(&opts.RuntimeTargetsDatabasePath, "runtime-targets-db", opts.RuntimeTargetsDatabasePath, "runtime target SQLite database path")
	fs.StringVar(&opts.HarnessContextBaseURL, "harness-context-base-url", opts.HarnessContextBaseURL, "optional harness context API base URL for tool.call")
	fs.StringVar(&opts.AgentConfigPath, "agent", opts.AgentConfigPath, "optional agent config path used for capability metadata")
	fs.StringVar(&opts.ToolConfigPath, "tool", opts.ToolConfigPath, "tool config path used for command and MCP runbook actions")
	fs.StringVar(&opts.LogFilePath, "log-file", opts.LogFilePath, "optional runbook service log file path")
	fs.StringVar(&opts.CommandDataDir, "command-data-dir", opts.CommandDataDir, "command service data directory")
	fs.Var(&opts.CommandAllowedWorkdirs, "command-allow-workdir", "allowed command working directory root")
	fs.Var(&opts.CommandAllowedEnv, "command-allow-env", "allowed process environment variable")
	fs.StringVar(&opts.CommandTemplatesJSON, "command-templates-json", opts.CommandTemplatesJSON, "JSON command template list")
	fs.StringVar(&opts.CommandParserDir, "command-parser-dir", opts.CommandParserDir, "Starlark command parser directory")
	fs.DurationVar(&opts.CommandDefaultTimeout, "command-timeout", opts.CommandDefaultTimeout, "default command timeout")
	fs.Int64Var(&opts.CommandMaxOutputBytes, "command-max-output-bytes", opts.CommandMaxOutputBytes, "default command output tail byte limit")
	fs.DurationVar(&opts.RequestTimeout, "request-timeout", opts.RequestTimeout, "maximum runbook action request duration")
	fs.DurationVar(&opts.ShutdownTimeout, "shutdown-timeout", opts.ShutdownTimeout, "maximum graceful shutdown duration")
	if err := fs.Parse(args); err != nil {
		return options{}, err
	}
	return opts, nil
}

// defaultOptions builds environment-aware runbook service defaults.
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
		ListenAddress:              envString("AGENTAWESOME_RUNBOOK_ADDR", "127.0.0.1:8092"),
		DefinitionsDir:             envString("AGENTAWESOME_RUNBOOK_DEFINITIONS_DIR", config.DefaultRunbookDefinitionsDir()),
		DatabasePath:               envString("AGENTAWESOME_RUNBOOK_DB", config.DefaultRunbookDatabasePath()),
		LaunchpadDatabasePath:      envString("AGENTAWESOME_LAUNCHPAD_DB", config.DefaultLaunchpadDatabasePath()),
		RuntimeTargetsDatabasePath: envString("AGENTAWESOME_RUNTIME_TARGETS_DB", config.DefaultRuntimeTargetsDatabasePath()),
		HarnessContextBaseURL:      envString("AGENTAWESOME_CONTEXT_API_BASE_URL", ""),
		AgentConfigPath:            envString("AGENTAWESOME_AGENT_CONFIG", ""),
		ToolConfigPath:             envString("AGENTAWESOME_TOOL_CONFIG", config.DefaultToolPath()),
		LogFilePath:                envString("AGENTAWESOME_RUNBOOK_LOG_FILE", ""),
		CommandDataDir:             envString("AGENTAWESOME_COMMAND_DATA_DIR", config.DefaultCommandDataDir()),
		CommandAllowedWorkdirs:     commandAllowedWorkdirs,
		CommandAllowedEnv:          commandAllowedEnv,
		CommandTemplatesJSON:       envString("AGENTAWESOME_COMMAND_TEMPLATES_JSON", ""),
		CommandParserDir:           envString("AGENTAWESOME_COMMAND_PARSER_DIR", config.DefaultCommandParserDir()),
		CommandDefaultTimeout:      envDuration("AGENTAWESOME_COMMAND_TIMEOUT", 10*time.Minute),
		CommandMaxOutputBytes:      envInt64("AGENTAWESOME_COMMAND_MAX_OUTPUT_BYTES", 64<<10),
		RequestTimeout:             envDuration("AGENTAWESOME_RUNBOOK_REQUEST_TIMEOUT", 10*time.Minute),
		ShutdownTimeout:            defaultShutdownTimeout,
		GatewayBaseURL:             envString("AGENTAWESOME_GATEWAY_BASE_URL", "http://127.0.0.1:8070/api"),
		GatewayToken:               envString("AGENTAWESOME_GATEWAY_TOKEN", ""),
		Profile:                    envString("AGENTAWESOME_PROFILE", ""),
		TargetID:                   envString("AGENTAWESOME_QUEUE_TARGET_ID", "this_computer"),
		LeaseSeconds:               int(envInt64("AGENTAWESOME_QUEUE_LEASE_SECONDS", 300)),
		PollInterval:               envDuration("AGENTAWESOME_QUEUE_POLL_INTERVAL", 5*time.Second),
		RunTimeout:                 envDuration("AGENTAWESOME_QUEUE_RUN_TIMEOUT", 12*time.Hour),
		EnqueueDue:                 envBool("AGENTAWESOME_QUEUE_ENQUEUE_DUE", true),
		RecoverExpired:             envBool("AGENTAWESOME_QUEUE_RECOVER_EXPIRED", true),
		AgentConfigExplicit:        flagProvided(args, "agent") || strings.TrimSpace(os.Getenv("AGENTAWESOME_AGENT_CONFIG")) != "",
		ToolConfigExplicit:         flagProvided(args, "tool") || strings.TrimSpace(os.Getenv("AGENTAWESOME_TOOL_CONFIG")) != "",
	}
}

// commandOptions maps runbook flags onto the shared command service options.
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

// loadAgent reads optional agent metadata without requiring an agent to run runbooks.
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

// runbookMCPServerEndpoints indexes configured MCP endpoints for runbook actions.
func runbookMCPServerEndpoints(toolsCfg *schema.Tools) map[string]string {
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

// envBool returns a boolean environment value or fallback.
func envBool(name string, fallback bool) bool {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
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
