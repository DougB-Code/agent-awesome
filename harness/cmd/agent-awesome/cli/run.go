package cli

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"agentawesome/internal/app"
	"agentawesome/internal/config"
	"github.com/spf13/cobra"
)

// newRunCommand creates the production run command.
func newRunCommand(ctx context.Context) *cobra.Command {
	return newRunCommandWithRunner(ctx, app.Run)
}

// newRunCommandWithRunner creates a run command with an injectable runtime
// runner so tests can assert parsed options without launching the full runtime.
func newRunCommandWithRunner(ctx context.Context, runner func(context.Context, app.Options) error) *cobra.Command {
	commandRequireApproval, commandApprovalSet := envBoolWithPresence("AGENTAWESOME_COMMAND_REQUIRE_APPROVAL", true)
	commandAllowArbitrary, commandArbitrarySet := envBoolWithPresence("AGENTAWESOME_COMMAND_ALLOW_ARBITRARY", true)
	opts := app.Options{
		AgentConfigPath:        config.DefaultAgentPath(),
		ModelConfigPath:        config.DefaultModelPath(),
		ToolPath:               config.DefaultToolPath(),
		ContextAPIToken:        os.Getenv("AGENTAWESOME_CONTEXT_API_TOKEN"),
		WorkflowAPIAddr:        os.Getenv("AGENTAWESOME_WORKFLOW_ADDR"),
		WorkflowDefinitionsDir: os.Getenv("AGENTAWESOME_WORKFLOW_DEFINITIONS_DIR"),
		WorkflowDatabasePath:   os.Getenv("AGENTAWESOME_WORKFLOW_DB"),
		WorkflowContextBaseURL: os.Getenv("AGENTAWESOME_WORKFLOW_CONTEXT_BASE_URL"),
		CommandMCPAddr:         os.Getenv("AGENTAWESOME_COMMAND_ADDR"),
		CommandDataDir:         envString("AGENTAWESOME_COMMAND_DATA_DIR", config.DefaultCommandDataDir()),
		CommandAllowedWorkdirs: envList("AGENTAWESOME_COMMAND_ALLOWED_WORKDIRS", []string{"."}),
		CommandAllowedEnv:      envList("AGENTAWESOME_COMMAND_ALLOWED_ENV", []string{"PATH", "HOME", "USER", "TMPDIR"}),
		CommandTemplatesJSON:   os.Getenv("AGENTAWESOME_COMMAND_TEMPLATES_JSON"),
		CommandParserDir:       envString("AGENTAWESOME_COMMAND_PARSER_DIR", config.DefaultCommandParserDir()),
		CommandDefaultTimeout:  envDuration("AGENTAWESOME_COMMAND_TIMEOUT", 10*time.Minute),
		CommandMaxOutputBytes:  envInt64("AGENTAWESOME_COMMAND_MAX_OUTPUT_BYTES", 64<<10),
		CommandApprovalTTL:     envDuration("AGENTAWESOME_COMMAND_APPROVAL_TTL", 10*time.Minute),
		CommandRequireApproval: commandRequireApproval,
		CommandAllowArbitrary:  commandAllowArbitrary,
		CommandApprovalSet:     commandApprovalSet,
		CommandArbitrarySet:    commandArbitrarySet,
		MCPManagerAddr:         os.Getenv("AGENTAWESOME_MCP_ADDR"),
		MCPServersJSON:         os.Getenv("AGENTAWESOME_MCP_SERVERS_JSON"),
		MCPRequestTimeout:      envDuration("AGENTAWESOME_MCP_REQUEST_TIMEOUT", 10*time.Minute),
	}

	cmd := &cobra.Command{
		Use:   "run [runtime args]",
		Short: "Run the configured agent",
		Long: fmt.Sprintf(`Run the configured agent.

Runtime arguments are passed to the Agent Awesome runtime. Put Agent Awesome flags
before runtime arguments, or use -- to make the boundary explicit.

Examples:
  agent-awesome run -- web --port 8080 api
  agent-awesome run --model model.yaml --agent agent.yaml --tool tool.yaml -- web --port 8080 api

AA runtime syntax:
%s`, runtimeSyntax()),
		Args: cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			opts.Args = args
			opts.ToolSet = cmd.Flags().Changed("tool")
			opts.CommandApprovalSet = opts.CommandApprovalSet || cmd.Flags().Changed("command-require-approval")
			opts.CommandArbitrarySet = opts.CommandArbitrarySet || cmd.Flags().Changed("command-allow-arbitrary")
			return runner(ctx, opts)
		},
	}

	cmd.Flags().StringVar(&opts.ModelConfigPath, "model", opts.ModelConfigPath, "model config path")
	cmd.Flags().StringVar(&opts.AgentConfigPath, "agent", opts.AgentConfigPath, "agent config path")
	cmd.Flags().StringVar(&opts.ToolPath, "tool", opts.ToolPath, "tool config path")
	cmd.Flags().StringVar(&opts.ProviderName, "provider", opts.ProviderName, "provider name from config")
	cmd.Flags().StringVar(&opts.ModelID, "model-id", opts.ModelID, "model id from provider config")
	cmd.Flags().StringVar(&opts.LogFilePath, "log-file", opts.LogFilePath, "log file path")
	cmd.Flags().StringVar(&opts.ContextAPIAddr, "context-api-addr", opts.ContextAPIAddr, "optional harness-owned context API listen address")
	cmd.Flags().StringVar(&opts.ContextAPIToken, "context-api-token", opts.ContextAPIToken, "optional bearer token for direct context API requests")
	cmd.Flags().StringVar(&opts.SessionDatabase, "session-db", opts.SessionDatabase, "assistant session SQLite database path; defaults to the memory database")
	cmd.Flags().StringVar(&opts.WorkflowAPIAddr, "workflow-api-addr", opts.WorkflowAPIAddr, "optional embedded workflow API listen address")
	cmd.Flags().StringVar(&opts.WorkflowDefinitionsDir, "workflow-definitions", opts.WorkflowDefinitionsDir, "embedded workflow definition directory")
	cmd.Flags().StringVar(&opts.WorkflowDatabasePath, "workflow-db", opts.WorkflowDatabasePath, "embedded workflow SQLite database path")
	cmd.Flags().StringVar(&opts.WorkflowContextBaseURL, "workflow-context-base-url", opts.WorkflowContextBaseURL, "context API base URL used by embedded workflow tool.call actions")
	cmd.Flags().StringVar(&opts.CommandMCPAddr, "command-mcp-addr", opts.CommandMCPAddr, "optional embedded command MCP listen address")
	cmd.Flags().StringVar(&opts.CommandDataDir, "command-data-dir", opts.CommandDataDir, "embedded command service data directory")
	cmd.Flags().StringArrayVar(&opts.CommandAllowedWorkdirs, "command-allow-workdir", opts.CommandAllowedWorkdirs, "allowed command working directory root")
	cmd.Flags().StringArrayVar(&opts.CommandAllowedEnv, "command-allow-env", opts.CommandAllowedEnv, "allowed process environment variable")
	cmd.Flags().StringVar(&opts.CommandTemplatesJSON, "command-templates-json", opts.CommandTemplatesJSON, "JSON command template list")
	cmd.Flags().StringVar(&opts.CommandParserDir, "command-parser-dir", opts.CommandParserDir, "Starlark command parser directory")
	cmd.Flags().DurationVar(&opts.CommandDefaultTimeout, "command-timeout", opts.CommandDefaultTimeout, "default embedded command timeout")
	cmd.Flags().Int64Var(&opts.CommandMaxOutputBytes, "command-max-output-bytes", opts.CommandMaxOutputBytes, "default command output tail byte limit")
	cmd.Flags().DurationVar(&opts.CommandApprovalTTL, "command-approval-ttl", opts.CommandApprovalTTL, "command approval expiry")
	cmd.Flags().BoolVar(&opts.CommandRequireApproval, "command-require-approval", opts.CommandRequireApproval, "require approval for configured command templates by default")
	cmd.Flags().BoolVar(&opts.CommandAllowArbitrary, "command-allow-arbitrary", opts.CommandAllowArbitrary, "allow arbitrary reviewed command proposals")
	cmd.Flags().StringVar(&opts.MCPManagerAddr, "mcp-manager-addr", opts.MCPManagerAddr, "optional embedded MCP manager listen address")
	cmd.Flags().StringVar(&opts.MCPServersJSON, "mcp-servers-json", opts.MCPServersJSON, "JSON MCP server configuration list")
	cmd.Flags().DurationVar(&opts.MCPRequestTimeout, "mcp-request-timeout", opts.MCPRequestTimeout, "upstream MCP manager request timeout")
	cmd.Flags().SetInterspersed(false)
	return cmd
}

// runtimeSyntax returns the runtime argument syntax shown in CLI help.
func runtimeSyntax() string {
	return app.RuntimeSyntax()
}

// envString returns a string environment value or fallback.
func envString(name string, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// envBoolWithPresence returns a bool environment value and whether it was configured.
func envBoolWithPresence(name string, fallback bool) (bool, bool) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, false
	}
	return value == "1" || strings.EqualFold(value, "true") || strings.EqualFold(value, "yes"), true
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

// envInt64 returns an int64 environment value or fallback.
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

// envList returns a comma-separated string list environment value.
func envList(name string, fallback []string) []string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return append([]string(nil), fallback...)
	}
	parts := strings.Split(value, ",")
	items := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			items = append(items, trimmed)
		}
	}
	return items
}
