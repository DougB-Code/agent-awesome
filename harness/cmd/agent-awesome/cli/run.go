package cli

import (
	"context"
	"fmt"
	"os"
	"strings"

	"agentawesome/internal/app"
	"agentawesome/internal/config"
	"agentawesome/internal/console"
	"agentawesome/internal/runtime"
	"github.com/spf13/cobra"
)

// newRunCommand creates the production run command.
func newRunCommand(ctx context.Context) *cobra.Command {
	return newRunCommandWithRunner(ctx, app.Run)
}

// newRunCommandWithRunner creates a run command with an injectable runtime
// runner so tests can assert parsed options without launching the full runtime.
func newRunCommandWithRunner(ctx context.Context, runner func(context.Context, app.Options) error) *cobra.Command {
	opts := app.Options{
		AgentConfigPath: config.DefaultAgentPath(),
		ModelConfigPath: config.DefaultModelPath(),
		ToolPath:        config.DefaultToolPath(),
		ContextAPIToken: os.Getenv("AGENTAWESOME_CONTEXT_API_TOKEN"),
	}

	cmd := &cobra.Command{
		Use:   "run [runtime args]",
		Short: "Run the configured agent",
		Long: fmt.Sprintf(`Run the configured agent.

Runtime arguments are passed to the Agent Awesome runtime. Put Agent Awesome flags
before runtime arguments, or use -- to make the boundary explicit.

Examples:
  agent-awesome run -- console
  agent-awesome run --model model.yaml --agent agent.yaml --tool tool.yaml -- web --port 8080

AA runtime syntax:
%s`, runtimeSyntax()),
		Args: cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			opts.Args = args
			opts.ToolSet = cmd.Flags().Changed("tool")
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
	cmd.Flags().StringVar(&opts.SessionDatabase, "session-db", opts.SessionDatabase, "ADK session SQLite database path; defaults to the memory database")
	cmd.Flags().SetInterspersed(false)
	return cmd
}

// runtimeSyntax returns the runtime argument syntax shown in CLI help.
func runtimeSyntax() string {
	var b strings.Builder
	fmt.Fprintf(&b, "Agent Awesome console:\n%s\n", console.Syntax())
	fmt.Fprintf(&b, "Delegated ADK runtime modes:\n%s", runtime.Syntax())
	return b.String()
}
